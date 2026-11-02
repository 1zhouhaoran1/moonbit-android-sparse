///|
/// Borrow raw payloads; never materialize FILL or DONT_CARE output.
priv enum WriterPiece {
  Raw(BytesView)
  Fill(UInt32, UInt32)
  Hole(UInt32)
}

///|
priv struct WriterPlan {
  blocks : UInt32
  chunks : UInt32
  serialized_bytes : UInt64
}

///|
fn writer_check_block_size(block_size : UInt32) -> Unit raise {
  if block_size == 0U || block_size % 4U != 0U {
    raise SparseError::Invalid(
      0UL, "block size must be a positive multiple of four",
    )
  }
}

///|
fn writer_check_chunk_count(
  count : Int32,
  checksum : Bool,
  limits : Limits,
) -> UInt64 raise {
  let total = count.to_uint64() + (if checksum { 1UL } else { 0UL })
  if total > 0xffffffffUL || total > limits.max_chunks.to_uint64() {
    raise SparseError::LimitExceeded(0UL, "chunk count exceeds limit")
  }
  total
}

///|
/// Every Bytes payload is Int-sized, so a RAW payload plus its 12-byte
/// header fits the serialized UInt32 total-size field without splitting.
fn writer_plan(
  pieces : Array[WriterPiece],
  block_size : UInt32,
  checksum : Bool,
  limits : Limits,
) -> WriterPlan raise {
  writer_check_block_size(block_size)
  let chunk_count = writer_check_chunk_count(pieces.length(), checksum, limits)
  let mut blocks = 0UL
  let mut serialized_bytes = 28UL + (if checksum { 16UL } else { 0UL })
  for piece in pieces {
    let (piece_blocks, piece_size) = match piece {
      Raw(data) => {
        let size = data.length().to_uint64()
        if size == 0UL || size % block_size.to_uint64() != 0UL {
          raise SparseError::Invalid(
            0UL, "RAW data must contain complete nonempty blocks",
          )
        }
        (size / block_size.to_uint64(), size + 12UL)
      }
      Fill(_, count) => (count.to_uint64(), 16UL)
      Hole(count) => (count.to_uint64(), 12UL)
    }
    if piece_blocks == 0UL {
      raise SparseError::Invalid(0UL, "pieces must contain at least one block")
    }
    if piece_size > 0xffffffffUL {
      raise SparseError::Invalid(0UL, "serialized chunk exceeds UInt32 size")
    }
    if piece_blocks > 0xffffffffUL - blocks {
      raise SparseError::Invalid(0UL, "total block count exceeds UInt32")
    }
    blocks = blocks + piece_blocks
    if piece_size > 0xffffffffffffffffUL - serialized_bytes {
      raise SparseError::Invalid(0UL, "serialized size overflow")
    }
    serialized_bytes = serialized_bytes + piece_size
  }
  if blocks == 0UL {
    raise SparseError::Invalid(
      0UL, "sparse images must contain at least one block",
    )
  }
  let expanded = blocks * block_size.to_uint64()
  if expanded > limits.max_expanded_bytes {
    raise SparseError::LimitExceeded(0UL, "expanded output exceeds limit")
  }
  if checksum && expanded > limits.max_crc_bytes {
    raise SparseError::LimitExceeded(0UL, "checksum work exceeds limit")
  }
  { blocks: blocks.to_uint(), chunks: chunk_count.to_uint(), serialized_bytes, }
}

///|
fn writer_header(block_size : UInt32, plan : WriterPlan) -> Bytes {
  let out = @buffer.Buffer(size_hint=28)
  out.write_uint_le(0xed26ff3aU)
  out.write_uint16_le(1U.to_uint16())
  out.write_uint16_le(0U.to_uint16())
  out.write_uint16_le(28U.to_uint16())
  out.write_uint16_le(12U.to_uint16())
  out.write_uint_le(block_size)
  out.write_uint_le(plan.blocks)
  out.write_uint_le(plan.chunks)
  // The optional trailing CRC32 chunk carries the complete image checksum.
  out.write_uint_le(0U)
  out.to_bytes()
}

///|
fn writer_chunk_header(kind : UInt32, blocks : UInt32, size : UInt32) -> Bytes {
  let out = @buffer.Buffer(size_hint=12)
  out.write_uint16_le(kind.to_uint16())
  out.write_uint16_le(0U.to_uint16())
  out.write_uint_le(blocks)
  out.write_uint_le(size)
  out.to_bytes()
}

///|
fn writer_word(value : UInt32) -> Bytes {
  let out = @buffer.Buffer(size_hint=4)
  out.write_uint_le(value)
  out.to_bytes()
}

///|
fn writer_emit(
  pieces : Array[WriterPiece],
  plan : WriterPlan,
  block_size : UInt32,
  checksum : Bool,
  emit : (Bytes) -> Unit raise,
) -> Unit raise {
  emit(writer_header(block_size, plan))
  let mut crc = 0U
  for piece in pieces {
    match piece {
      Raw(data) => {
        let blocks = (data.length().to_uint64() / block_size.to_uint64()).to_uint()
        emit(
          writer_chunk_header(
            0xcac1U,
            blocks,
            data.length().reinterpret_as_uint() + 12U,
          ),
        )
        // Bound each emitted copy even when the caller supplies a large RAW piece.
        let mut at = 0
        while at < data.length() {
          let end = at +
            (if data.length() - at > 65536 {
              65536
            } else {
              data.length() - at
            })
          let part = data[at:end]
          if checksum {
            crc = crc32_update(crc, part)
          }
          emit(part.to_owned())
          at = end
        }
      }
      Fill(pattern, count) => {
        emit(writer_chunk_header(0xcac2U, count, 16U))
        emit(writer_word(pattern))
        if checksum {
          crc = crc32_repeat(
            crc,
            pattern,
            count.to_uint64() * block_size.to_uint64(),
          )
        }
      }
      Hole(count) => {
        emit(writer_chunk_header(0xcac3U, count, 12U))
        if checksum {
          crc = crc32_repeat(
            crc,
            0U,
            count.to_uint64() * block_size.to_uint64(),
          )
        }
      }
    }
  }
  if checksum {
    emit(writer_chunk_header(0xcac4U, 0U, 16U))
    emit(writer_word(crc))
  }
}

///|
fn writer_borrow(pieces : Array[Piece]) -> Array[WriterPiece] {
  pieces.map(fn(piece) {
    match piece {
      Data(data) => WriterPiece::Raw(data[:])
      Fill(pattern, count) => WriterPiece::Fill(pattern, count)
      Hole(count) => WriterPiece::Hole(count)
    }
  })
}

///|
/// Validate every piece before emitting the first byte. Only explicit Hole
/// pieces produce DONT_CARE; Data pieces preserve their literal RAW bytes.
pub fn write_sparse(
  pieces : Array[Piece],
  emit~ : (Bytes) -> Unit raise,
  block_size~ : UInt32 = 4096U,
  checksum~ : Bool = true,
  limits~ : Limits = default_limits(),
) -> Unit raise {
  ignore(writer_check_chunk_count(pieces.length(), checksum, limits))
  let borrowed = writer_borrow(pieces)
  let plan = writer_plan(borrowed, block_size, checksum, limits)
  writer_emit(borrowed, plan, block_size, checksum, emit)
}

///|
fn writer_collect(
  pieces : Array[WriterPiece],
  block_size : UInt32,
  checksum : Bool,
  limits : Limits,
  max_output_bytes : UInt64,
) -> Bytes raise {
  let plan = writer_plan(pieces, block_size, checksum, limits)
  if plan.serialized_bytes > max_output_bytes ||
    plan.serialized_bytes > 2147483647UL {
    raise SparseError::LimitExceeded(
      0UL, "serialized output exceeds allocation limit",
    )
  }
  let out = @buffer.Buffer()
  writer_emit(pieces, plan, block_size, checksum, fn(bytes) {
    out.write_bytes(bytes)
  })
  out.to_bytes()
}

///|
/// Collect a sparse file with an explicit serialized-output allocation cap.
pub fn encode(
  pieces : Array[Piece],
  max_output_bytes~ : UInt64,
  block_size~ : UInt32 = 4096U,
  checksum~ : Bool = true,
  limits~ : Limits = default_limits(),
) -> Bytes raise {
  ignore(writer_check_chunk_count(pieces.length(), checksum, limits))
  writer_collect(
    writer_borrow(pieces),
    block_size,
    checksum,
    limits,
    max_output_bytes,
  )
}

///|
fn writer_pattern(data : BytesView) -> UInt32? {
  let pattern = read_u32(data, 0)
  let mut at = 4
  while at < data.length() {
    if read_u32(data, at) != pattern {
      return None
    }
    at = at + 4
  }
  Some(pattern)
}

///|
/// Reject empty input and partial final blocks. Repeated little-endian words, including zero,
/// become FILL; all other data remains RAW. No filesystem holes are inferred.
pub fn pack(
  raw : BytesView,
  max_output_bytes~ : UInt64,
  block_size~ : UInt32 = 4096U,
  checksum~ : Bool = true,
  limits~ : Limits = default_limits(),
) -> Bytes raise {
  writer_check_block_size(block_size)
  let raw_size = raw.length().to_uint64()
  if raw_size % block_size.to_uint64() != 0UL {
    raise SparseError::Invalid(
      0UL, "raw input length must be a multiple of block size",
    )
  }
  if raw_size == 0UL {
    raise SparseError::Invalid(
      0UL, "sparse images must contain at least one block",
    )
  }
  if raw_size > limits.max_expanded_bytes {
    raise SparseError::LimitExceeded(0UL, "expanded output exceeds limit")
  }
  if checksum && raw_size > limits.max_crc_bytes {
    raise SparseError::LimitExceeded(0UL, "checksum work exceeds limit")
  }
  let allocation_limit = if max_output_bytes < 2147483647UL {
    max_output_bytes
  } else {
    2147483647UL
  }
  let mut serialized = 28UL + (if checksum { 16UL } else { 0UL })
  if serialized > allocation_limit {
    raise SparseError::LimitExceeded(
      0UL, "serialized output exceeds allocation limit",
    )
  }
  let pieces : Array[WriterPiece] = []
  if raw.length() > 0 {
    // A nonempty aligned BytesView proves block_size fits a positive Int.
    let stride = block_size.reinterpret_as_int()
    let mut start = 0
    let mut kind = writer_pattern(raw[0:stride])
    let mut at = stride
    while at <= raw.length() {
      let next = if at < raw.length() {
        writer_pattern(raw[at:at + stride])
      } else {
        None
      }
      if at == raw.length() || next != kind {
        let piece = match kind {
          Some(pattern) =>
            WriterPiece::Fill(
              pattern,
              ((at - start) / stride).reinterpret_as_uint(),
            )
          None => WriterPiece::Raw(raw[start:at])
        }
        let count = pieces.length().to_uint64() +
          1UL +
          (if checksum { 1UL } else { 0UL })
        if count > limits.max_chunks.to_uint64() {
          raise SparseError::LimitExceeded(0UL, "chunk count exceeds limit")
        }
        let piece_size = match piece {
          Raw(data) => data.length().to_uint64() + 12UL
          Fill(_, _) | Hole(_) => 16UL
        }
        if piece_size > allocation_limit - serialized {
          raise SparseError::LimitExceeded(
            0UL, "serialized output exceeds allocation limit",
          )
        }
        serialized = serialized + piece_size
        pieces.push(piece)
        start = at
        kind = next
      }
      if at == raw.length() {
        break
      }
      at = at + stride
    }
  }
  writer_collect(pieces, block_size, checksum, limits, max_output_bytes)
}
