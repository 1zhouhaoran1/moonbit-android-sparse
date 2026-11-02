///|
/// The parser retains only a fixed-size prefix; extended headers are skipped.
priv enum DecoderPhase {
  FilePrefix
  FileExtension
  ChunkPrefix
  ChunkExtension
  RawPayload
  WordPayload
  Complete
  Finished
  Failed
}

///|
/// Incremental sparse-v1 decoder. Event callbacks may raise to cancel parsing.
pub struct Decoder {
  priv verify_crc : Bool
  priv limits : Limits
  priv scratch : FixedArray[Byte]
  priv mut buffered : Int32
  priv mut phase : DecoderPhase
  priv mut remaining : UInt64
  priv mut file_header : Header?
  priv mut chunk : Chunk?
  priv mut serialized_offset : UInt64
  priv mut expanded_offset : UInt64
  priv mut blocks_seen : UInt64
  priv mut completed_chunks : UInt32
  priv mut crc : UInt32
  priv mut busy : Bool
}

///|
/// CRC limits apply only when verification is requested.
pub fn Decoder::new(
  verify_crc~ : Bool = false,
  limits~ : Limits = default_limits(),
) -> Decoder {
  {
    verify_crc,
    limits,
    scratch: FixedArray::make(28, b'\x00'),
    buffered: 0,
    phase: FilePrefix,
    remaining: 0UL,
    file_header: None,
    chunk: None,
    serialized_offset: 0UL,
    expanded_offset: 0UL,
    blocks_seen: 0UL,
    completed_chunks: 0U,
    crc: 0U,
    busy: false,
  }
}

///|
/// Returns the validated base header, if it has arrived.
pub fn Decoder::header(self : Decoder) -> Header? {
  self.file_header
}

///|
/// Number of serialized bytes consumed, including skipped header extensions.
pub fn Decoder::input_offset(self : Decoder) -> UInt64 {
  self.serialized_offset
}

///|
/// Number of logical output bytes emitted so far, including Skip events.
pub fn Decoder::output_offset(self : Decoder) -> UInt64 {
  self.expanded_offset
}

///|
/// Number of fully consumed chunks.
pub fn Decoder::chunks_read(self : Decoder) -> UInt32 {
  self.completed_chunks
}

///|
/// Pending prefix bytes. The decoder's total scratch capacity is 28 bytes.
pub fn Decoder::buffered_bytes(self : Decoder) -> Int32 {
  self.buffered
}

///|
fn Decoder::consume(self : Decoder, length : Int32) -> Unit raise {
  let amount = length.to_uint64()
  if amount > 0xffffffffffffffffUL - self.serialized_offset {
    raise SparseError::Invalid(
      self.serialized_offset,
      "serialized offset overflow",
    )
  }
  self.serialized_offset += amount
}

///|
fn Decoder::prefix(self : Decoder) -> Bytes {
  Bytes::makei(self.buffered, i => self.scratch[i])
}

///|
fn Decoder::deliver(
  self : Decoder,
  event : Event,
  emit : (Event) -> Unit raise,
) -> Unit raise {
  emit(event)
  // A callback cannot catch a reentrant call's failure and revive the parser.
  if self.phase is Failed {
    raise SparseError::Invalid(self.serialized_offset, "decoder is poisoned")
  }
}

///|
fn decoder_take_count(remaining : UInt64, available : Int32) -> Int32 {
  if remaining < available.to_uint64() {
    remaining.to_int()
  } else {
    available
  }
}

///|
fn Decoder::parse_file_header(self : Decoder) -> Unit raise {
  let data = self.prefix()
  if read_u32(data[:], 0) != 0xed26ff3aU {
    raise SparseError::Invalid(0UL, "invalid sparse magic")
  }
  let header : Header = {
    major_version: read_u16(data[:], 4),
    minor_version: read_u16(data[:], 6),
    file_header_size: read_u16(data[:], 8),
    chunk_header_size: read_u16(data[:], 10),
    block_size: read_u32(data[:], 12),
    total_blocks: read_u32(data[:], 16),
    total_chunks: read_u32(data[:], 20),
    image_checksum: read_u32(data[:], 24),
  }
  if header.major_version != 1 {
    raise SparseError::Invalid(4UL, "unsupported sparse major version")
  }
  if header.file_header_size < 28 {
    raise SparseError::Invalid(8UL, "file header size is smaller than 28")
  }
  if header.chunk_header_size < 12 {
    raise SparseError::Invalid(10UL, "chunk header size is smaller than 12")
  }
  if header.block_size == 0U || header.block_size % 4U != 0U {
    raise SparseError::Invalid(
      12UL, "block size must be a positive multiple of four",
    )
  }
  if header.total_blocks == 0U {
    raise SparseError::Invalid(16UL, "total blocks must be positive")
  }
  // Both factors are u32, so their product is representable in u64.
  let expanded = header.expanded_size()
  if expanded > self.limits.max_expanded_bytes {
    raise SparseError::LimitExceeded(
      16UL, "expanded size exceeds configured limit",
    )
  }
  if header.total_chunks > self.limits.max_chunks {
    raise SparseError::LimitExceeded(
      20UL, "chunk count exceeds configured limit",
    )
  }
  if self.verify_crc && expanded > self.limits.max_crc_bytes {
    raise SparseError::LimitExceeded(
      16UL, "checksum work exceeds configured limit",
    )
  }
  self.file_header = Some(header)
  self.buffered = 0
  self.remaining = (header.file_header_size - 28).to_uint64()
  self.phase = FileExtension
}

///|
fn Decoder::begin_chunks(
  self : Decoder,
  emit : (Event) -> Unit raise,
) -> Unit raise {
  let header = self.file_header.unwrap()
  self.deliver(FileHeader(header), emit)
  if header.total_chunks == 0U {
    if header.total_blocks != 0U {
      raise SparseError::Invalid(
        self.serialized_offset,
        "chunk/block totals disagree",
      )
    }
    self.phase = Complete
  } else {
    self.phase = ChunkPrefix
  }
}

///|
fn Decoder::parse_chunk_header(self : Decoder) -> Unit raise {
  let data = self.prefix()
  let header = self.file_header.unwrap()
  let at = self.serialized_offset - 12UL
  let wire_kind = read_u16(data[:], 0)
  let kind = match wire_kind {
    0xcac1 => ChunkKind::Raw
    0xcac2 => ChunkKind::Fill
    0xcac3 => ChunkKind::Skip
    0xcac4 => ChunkKind::Crc32
    _ => raise SparseError::Invalid(at, "unknown sparse chunk type")
  }
  let blocks = read_u32(data[:], 4)
  let total_size = read_u32(data[:], 8)
  let logical_size = blocks.to_uint64() * header.block_size.to_uint64()
  let payload_size = match kind {
    Raw => logical_size
    Fill | Crc32 => 4UL
    Skip => 0UL
  }
  // Compare in u64: RAW payload + header can exceed the serialized u32 field.
  if total_size.to_uint64() !=
    header.chunk_header_size.to_uint64() + payload_size {
    raise SparseError::Invalid(
      at + 8UL,
      "chunk total_size does not match payload",
    )
  }
  if kind == Crc32 && blocks != 0U {
    raise SparseError::Invalid(at + 4UL, "CRC32 chunk must have zero blocks")
  }
  let new_blocks = self.blocks_seen + blocks.to_uint64()
  if new_blocks > header.total_blocks.to_uint64() {
    raise SparseError::Invalid(at + 4UL, "chunk blocks exceed declared total")
  }
  self.blocks_seen = new_blocks
  self.chunk = Some({
    index: self.completed_chunks,
    kind,
    input_offset: at,
    output_offset: self.expanded_offset,
    blocks,
    total_size,
  })
  self.buffered = 0
  self.remaining = (header.chunk_header_size - 12).to_uint64()
  self.phase = ChunkExtension
}

///|
fn Decoder::complete_chunk(self : Decoder) -> Unit raise {
  self.completed_chunks += 1U
  self.chunk = None
  self.buffered = 0
  let header = self.file_header.unwrap()
  if self.completed_chunks == header.total_chunks {
    if self.blocks_seen != header.total_blocks.to_uint64() {
      raise SparseError::Invalid(
        self.serialized_offset,
        "chunk/block totals disagree",
      )
    }
    self.phase = Complete
  } else {
    self.phase = ChunkPrefix
  }
}

///|
fn Decoder::begin_payload(
  self : Decoder,
  emit : (Event) -> Unit raise,
) -> Unit raise {
  let chunk = self.chunk.unwrap()
  let length = chunk.blocks.to_uint64() *
    self.file_header.unwrap().block_size.to_uint64()
  self.deliver(ChunkHeader(chunk), emit)
  match chunk.kind {
    Raw => {
      self.remaining = length
      self.phase = RawPayload
    }
    Fill | Crc32 => self.phase = WordPayload
    Skip => {
      if self.verify_crc {
        self.crc = crc32_repeat(self.crc, 0U, length)
      }
      self.expanded_offset += length
      self.deliver(SkipData(length), emit)
      self.complete_chunk()
    }
  }
}

///|
fn Decoder::complete_word(
  self : Decoder,
  emit : (Event) -> Unit raise,
) -> Unit raise {
  let data = self.prefix()
  let value = read_u32(data[:], 0)
  let chunk = self.chunk.unwrap()
  match chunk.kind {
    Fill => {
      let length = chunk.blocks.to_uint64() *
        self.file_header.unwrap().block_size.to_uint64()
      if self.verify_crc {
        self.crc = crc32_repeat(self.crc, value, length)
      }
      self.expanded_offset += length
      self.deliver(FillData(value, length), emit)
    }
    Crc32 => {
      if self.verify_crc && value != self.crc {
        raise SparseError::Invalid(
          self.serialized_offset - 4UL,
          "CRC32 chunk checksum mismatch",
        )
      }
      self.deliver(Checksum(value), emit)
    }
    _ =>
      raise SparseError::Invalid(self.serialized_offset, "invalid parser state")
  }
  self.complete_chunk()
}

///|
fn Decoder::feed_inner(
  self : Decoder,
  input : BytesView,
  emit : (Event) -> Unit raise,
) -> Unit raise {
  let mut position = 0
  while true {
    match self.phase {
      FilePrefix | ChunkPrefix | WordPayload => {
        let required = match self.phase {
          FilePrefix => 28
          ChunkPrefix => 12
          _ => 4
        }
        if self.buffered == required {
          match self.phase {
            FilePrefix => self.parse_file_header()
            ChunkPrefix => self.parse_chunk_header()
            _ => self.complete_word(emit)
          }
          continue
        }
        if position == input.length() {
          return
        }
        let count = Int32::min(
          required - self.buffered,
          input.length() - position,
        )
        for i in 0..<count {
          self.scratch[self.buffered + i] = input[position + i]
        }
        self.buffered += count
        self.consume(count)
        position += count
      }
      FileExtension | ChunkExtension => {
        if self.remaining == 0UL {
          match self.phase {
            FileExtension => self.begin_chunks(emit)
            _ => self.begin_payload(emit)
          }
          continue
        }
        if position == input.length() {
          return
        }
        let count = decoder_take_count(
          self.remaining,
          input.length() - position,
        )
        self.consume(count)
        self.remaining -= count.to_uint64()
        position += count
      }
      RawPayload => {
        if self.remaining == 0UL {
          self.complete_chunk()
          continue
        }
        if position == input.length() {
          return
        }
        let count = decoder_take_count(
          self.remaining,
          input.length() - position,
        )
        let data = input[position:position + count]
        if self.verify_crc {
          self.crc = crc32_update(self.crc, data)
        }
        self.consume(count)
        self.remaining -= count.to_uint64()
        self.expanded_offset += count.to_uint64()
        position += count
        self.deliver(RawData(data), emit)
      }
      Complete => {
        if position != input.length() {
          raise SparseError::Invalid(
            self.serialized_offset,
            "trailing bytes after declared chunks",
          )
        }
        return
      }
      Failed =>
        raise SparseError::Invalid(
          self.serialized_offset,
          "decoder is poisoned",
        )
      Finished =>
        raise SparseError::Invalid(
          self.serialized_offset,
          "decoder is finished",
        )
    }
  }
}

///|
/// Feed any segmentation, including empty input. Any error poisons this decoder.
/// RawData borrows the current input; retain it only after calling to_owned().
pub fn Decoder::feed(
  self : Decoder,
  input : BytesView,
  emit : (Event) -> Unit raise,
) -> Unit raise {
  if self.busy {
    self.phase = Failed
    raise SparseError::Invalid(
      self.serialized_offset,
      "decoder callback must not reenter parsing",
    )
  }
  self.busy = true
  defer {
    self.busy = false
  }
  errdefer {
    self.phase = Failed
  }
  self.feed_inner(input, emit)
}

///|
/// Finish exactly once. Truncated prefixes/payloads and checksum mismatches fail.
pub fn Decoder::finish(self : Decoder) -> Header raise {
  if self.busy {
    self.phase = Failed
    raise SparseError::Invalid(
      self.serialized_offset,
      "decoder callback must not finish parsing",
    )
  }
  match self.phase {
    Complete => {
      let header = self.file_header.unwrap()
      if self.verify_crc &&
        header.image_checksum != 0U &&
        header.image_checksum != self.crc {
        self.phase = Failed
        raise SparseError::Invalid(24UL, "file header checksum mismatch")
      }
      self.phase = Finished
      header
    }
    Finished =>
      raise SparseError::Invalid(self.serialized_offset, "decoder is finished")
    Failed =>
      raise SparseError::Invalid(self.serialized_offset, "decoder is poisoned")
    _ => {
      self.phase = Failed
      raise SparseError::Invalid(
        self.serialized_offset,
        "truncated sparse image",
      )
    }
  }
}
