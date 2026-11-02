///|
/// These fixtures are constructed independently of the production writer.
fn dec_test_header(
  blocks : UInt32,
  chunks : UInt32,
  block_size~ : UInt32 = 4U,
  file_size~ : Int32 = 28,
  chunk_size~ : Int32 = 12,
  major~ : Int32 = 1,
  minor~ : Int32 = 0,
  checksum~ : UInt32 = 0U,
) -> Bytes {
  let out = Buffer()
  out.write_uint_le(0xed26ff3aU)
  out.write_uint16_le(major.to_uint16())
  out.write_uint16_le(minor.to_uint16())
  out.write_uint16_le(file_size.to_uint16())
  out.write_uint16_le(chunk_size.to_uint16())
  out.write_uint_le(block_size)
  out.write_uint_le(blocks)
  out.write_uint_le(chunks)
  out.write_uint_le(checksum)
  for _ in 28..<file_size {
    out.write_byte(b'\xa5')
  }
  out.to_bytes()
}

///|
fn dec_test_chunk(
  kind : Int32,
  blocks : UInt32,
  payload : Bytes,
  header_size~ : Int32 = 12,
  total_size? : UInt32,
) -> Bytes {
  let out = Buffer()
  out.write_uint16_le(kind.to_uint16())
  out.write_uint16_le(0U.to_uint16())
  out.write_uint_le(blocks)
  out.write_uint_le(
    total_size.unwrap_or((header_size + payload.length()).reinterpret_as_uint()),
  )
  for _ in 12..<header_size {
    out.write_byte(b'\x5a')
  }
  out.write_bytes(payload[:])
  out.to_bytes()
}

///|
fn dec_test_join(parts : Array[Bytes]) -> Bytes {
  let out = Buffer()
  for part in parts {
    out.write_bytes(part[:])
  }
  out.to_bytes()
}

///|
fn dec_test_word(value : UInt32) -> Bytes {
  let out = Buffer()
  out.write_uint_le(value)
  out.to_bytes()
}

///|
/// Small independent bit-at-a-time IEEE CRC oracle, not production CRC code.
fn dec_test_crc(data : BytesView) -> UInt32 {
  let mut crc = 0xffffffffU
  for byte in data {
    crc = crc ^ byte.to_uint()
    for _ in 0..<8 {
      crc = if (crc & 1U) == 0U { crc >> 1 } else { (crc >> 1) ^ 0xedb88320U }
    }
  }
  crc ^ 0xffffffffU
}

///|
fn dec_test_mixed(file_size~ : Int32 = 28, chunk_size~ : Int32 = 12) -> Bytes {
  let expanded = b"12345678\x11\x22\x33\x44\x11\x22\x33\x44\x00\x00\x00\x00"
  let crc = dec_test_crc(expanded[:])
  dec_test_join([
    dec_test_header(5U, 4U, file_size~, chunk_size~, minor=7, checksum=crc),
    dec_test_chunk(0xcac1, 2U, b"12345678", header_size=chunk_size),
    dec_test_chunk(
      0xcac2,
      2U,
      dec_test_word(0x44332211U),
      header_size=chunk_size,
    ),
    dec_test_chunk(0xcac3, 1U, b"", header_size=chunk_size),
    dec_test_chunk(0xcac4, 0U, dec_test_word(crc), header_size=chunk_size),
  ])
}

///|
fn dec_test_assert_invalid(data : Bytes, offset? : UInt64) -> Unit raise {
  let parser = Decoder::new()
  let mut caught = false
  try {
    parser.feed(data[:], _ => ())
    ignore(parser.finish())
  } catch {
    SparseError::Invalid(at, _) => {
      caught = true
      if offset is Some(expected) {
        assert_eq(at, expected)
      }
    }
    other => raise other
  }
  assert_true(caught)
}

///|
test "decoder emits all chunk kinds under every-byte and irregular segmentation" {
  let data = dec_test_mixed()
  let expected = b"12345678\x11\x22\x33\x44\x11\x22\x33\x44\x00\x00\x00\x00"
  for sizes in [[1], [3], [1, 7, 2, 13, 5], [data.length()]] {
    let parser = Decoder::new(verify_crc=true)
    let out = Buffer()
    let chunks : Array[Chunk] = []
    let mut header_count = 0
    let mut checksum_count = 0
    let mut position = 0
    let mut part = 0
    while position < data.length() {
      let count = Int32::min(
        sizes[part % sizes.length()],
        data.length() - position,
      )
      parser.feed(data[position:position + count], event => {
        match event {
          FileHeader(_) => header_count += 1
          ChunkHeader(chunk) => chunks.push(chunk)
          RawData(raw) => out.write_bytes(raw)
          FillData(pattern, length) => {
            let word = dec_test_word(pattern)
            for i in 0..<length.to_int() {
              out.write_byte(word[i % 4])
            }
          }
          SkipData(length) =>
            for _ in 0..<length.to_int() {
              out.write_byte(b'\x00')
            }
          Checksum(value) => {
            assert_eq(value, dec_test_crc(expected[:]))
            checksum_count += 1
          }
        }
      })
      assert_true(parser.buffered_bytes() <= 28)
      position += count
      part += 1
    }
    let header = parser.finish()
    assert_eq(header.minor_version, 7)
    assert_eq(parser.header(), Some(header))
    assert_eq(parser.input_offset(), data.length().to_uint64())
    assert_eq(parser.output_offset(), 20UL)
    assert_eq(parser.chunks_read(), 4U)
    assert_eq(out.to_bytes(), expected)
    assert_eq(header_count, 1)
    assert_eq(checksum_count, 1)
    assert_eq(chunks.map(c => c.kind), [Raw, Fill, Skip, Crc32])
    assert_eq(chunks.map(c => c.input_offset), [28UL, 48UL, 64UL, 76UL])
    assert_eq(chunks.map(c => c.output_offset), [0UL, 8UL, 16UL, 20UL])
  }
}

///|
test "decoder skips extended file and chunk headers without buffering extensions" {
  let data = dec_test_mixed(file_size=65535, chunk_size=65535)
  let parser = Decoder::new(verify_crc=true)
  let raw = Buffer()
  let mut position = 0
  while position < data.length() {
    let end = Int32::min(position + 73, data.length())
    parser.feed(data[position:end], event => {
      if event is RawData(bytes) {
        raw.write_bytes(bytes)
      }
    })
    assert_true(parser.buffered_bytes() <= 28)
    position = end
  }
  assert_eq(parser.finish().file_header_size, 65535)
  assert_eq(raw.to_bytes(), b"12345678")
  assert_eq(parser.output_offset(), 20UL)
}

///|
test "decoder borrows RAW fragments instead of waiting for a full payload" {
  let parser = Decoder::new()
  let prefix = dec_test_join([
    dec_test_header(3U, 1U),
    dec_test_chunk(0xcac1, 3U, b"", total_size=24U),
  ])
  let mut calls = 0
  parser.feed(prefix[:], _ => ())
  for part in [b"abc", b"defgh", b"ijkl"] {
    parser.feed(part[:], event => {
      if event is RawData(raw) {
        assert_eq(raw.to_owned(), part)
        calls += 1
      }
    })
    assert_eq(parser.buffered_bytes(), 0)
  }
  ignore(parser.finish())
  assert_eq(calls, 3)
}

///|
test "decoder rejects malformed base headers with field offsets" {
  dec_test_assert_invalid(Bytes::make(28, b'\x00'), offset=0UL)
  dec_test_assert_invalid(dec_test_header(0U, 0U, major=2), offset=4UL)
  dec_test_assert_invalid(dec_test_header(0U, 0U, file_size=27), offset=8UL)
  dec_test_assert_invalid(dec_test_header(0U, 0U, chunk_size=11), offset=10UL)
  dec_test_assert_invalid(dec_test_header(0U, 0U, block_size=0U), offset=12UL)
  dec_test_assert_invalid(dec_test_header(0U, 0U, block_size=6U), offset=12UL)
  dec_test_assert_invalid(dec_test_header(0U, 0U), offset=16UL)
}

///|
test "decoder rejects wrong chunk lengths unknown kinds block counts and CRC blocks" {
  for
    chunk in [
      dec_test_chunk(0xcac1, 1U, b"abc"),
      dec_test_chunk(0xcac2, 1U, b"abcde"),
      dec_test_chunk(0xcac3, 1U, b"x"),
      dec_test_chunk(0xcac4, 0U, b"abc"),
      dec_test_chunk(0xcac4, 1U, b"abcd"),
      dec_test_chunk(0xcaff, 1U, b""),
      dec_test_chunk(0xcac3, 2U, b""),
    ] {
    dec_test_assert_invalid(dec_test_join([dec_test_header(1U, 1U), chunk]))
  }
  dec_test_assert_invalid(
    dec_test_join([dec_test_header(2U, 1U), dec_test_chunk(0xcac3, 1U, b"")]),
  )
  dec_test_assert_invalid(dec_test_header(1U, 0U))
}

///|
test "decoder rejects every truncated prefix payload and extension" {
  let data = dec_test_mixed(file_size=31, chunk_size=15)
  for cut in 0..<data.length() {
    dec_test_assert_invalid(data[:cut].to_owned())
  }
  dec_test_assert_invalid(dec_test_join([dec_test_mixed(), b"x"]), offset=92UL)
}

///|
test "decoder checks expanded chunk and checksum limits before emitting events" {
  let data = dec_test_header(5U, 4U)
  for
    (limits, verify_crc) in [
      (
        { max_expanded_bytes: 19UL, max_crc_bytes: 100UL, max_chunks: 4U, },
        false,
      ),
      (
        { max_expanded_bytes: 20UL, max_crc_bytes: 100UL, max_chunks: 3U, },
        false,
      ),
      ({ max_expanded_bytes: 20UL, max_crc_bytes: 19UL, max_chunks: 4U, }, true),
    ] {
    let parser = Decoder::new(limits~, verify_crc~)
    let mut events = 0
    let mut caught = false
    parser.feed(data[:], _ => events += 1) catch {
      SparseError::LimitExceeded(_, _) => caught = true
      other => raise other
    }
    assert_true(caught)
    assert_eq(events, 0)
  }
}

///|
test "decoder inspects a huge logical hole without expanded allocation or CRC work" {
  let logical = 0xffffffffU.to_uint64() * 4096UL
  let data = dec_test_join([
    dec_test_header(0xffffffffU, 1U, block_size=4096U),
    dec_test_chunk(0xcac3, 0xffffffffU, b""),
  ])
  let limits : Limits = {
    max_expanded_bytes: logical,
    max_crc_bytes: 0UL,
    max_chunks: 1U,
  }
  let parser = Decoder::new(limits~)
  let mut skip = 0UL
  parser.feed(data[:], event => if event is SkipData(length) { skip = length })
  assert_eq(parser.finish().expanded_size(), logical)
  assert_eq(skip, logical)
  assert_eq(parser.buffered_bytes(), 0)
  assert_eq(parser.input_offset(), 40UL)
}

///|
test "decoder uses u64 length arithmetic before comparing serialized RAW size" {
  let limits : Limits = {
    max_expanded_bytes: 0xffffffffffffffffUL,
    max_crc_bytes: 0UL,
    max_chunks: 1U,
  }
  let parser = Decoder::new(limits~)
  let data = dec_test_join([
    dec_test_header(0xffffffffU, 1U, block_size=0xfffffffcU),
    dec_test_chunk(0xcac1, 0xffffffffU, b"", total_size=16U),
  ])
  let mut caught = false
  parser.feed(data[:], _ => ()) catch {
    SparseError::Invalid(at, _) => {
      caught = true
      assert_eq(at, 36UL)
    }
    other => raise other
  }
  assert_true(caught)
}

///|
test "decoder verifies both prefix CRC chunks and a nonzero final header CRC" {
  let raw = b"12345678"
  let expected_crc = dec_test_crc(raw[:])
  for bad_header in [false, true] {
    let data = dec_test_join([
      dec_test_header(
        2U,
        2U,
        checksum=if bad_header { expected_crc ^ 1U } else { expected_crc },
      ),
      dec_test_chunk(0xcac1, 2U, raw),
      dec_test_chunk(
        0xcac4,
        0U,
        dec_test_word(if bad_header { expected_crc } else { expected_crc ^ 1U }),
      ),
    ])
    let parser = Decoder::new(verify_crc=true)
    let mut caught = false
    try {
      parser.feed(data[:], _ => ())
      ignore(parser.finish())
    } catch {
      SparseError::Invalid(at, _) => {
        caught = true
        assert_eq(at, if bad_header { 24UL } else { 60UL })
      }
      other => raise other
    }
    assert_true(caught)
    let unchecked = Decoder::new()
    unchecked.feed(data[:], _ => ())
    ignore(unchecked.finish())
  }
}

///|
test "decoder propagates callback cancellation and remains poisoned" {
  let data = dec_test_mixed()
  for fail_at in 0..<9 {
    let parser = Decoder::new()
    let mut calls = 0
    let mut cancelled = false
    parser.feed(data[:], _ => {
      if calls == fail_at {
        raise Failure("sink cancelled")
      }
      calls += 1
    }) catch {
      Failure(message) => {
        assert_eq(message, "sink cancelled")
        cancelled = true
      }
      other => raise other
    }
    assert_true(cancelled)
    let mut poisoned = false
    parser.feed(b"", _ => ()) catch {
      SparseError::Invalid(_, message) => {
        assert_eq(message, "decoder is poisoned")
        poisoned = true
      }
      other => raise other
    }
    assert_true(poisoned)
  }
}

///|
test "decoder rejects callback reentry even when the callback catches its error" {
  let parser = Decoder::new()
  let data = dec_test_join([
    dec_test_header(1U, 1U),
    dec_test_chunk(0xcac3, 1U, b""),
  ])
  let mut rejected = false
  parser.feed(data[:], _ => parser.feed(b"", _ => ()) catch { _ => () }) catch {
    SparseError::Invalid(_, _) => rejected = true
    other => raise other
  }
  assert_true(rejected)
}

///|
test "decoder rejects empty images at the total_blocks field and poisons the parser" {
  let parser = Decoder::new()
  let data = dec_test_header(0U, 0U)
  let mut rejected = false
  parser.feed(data[:], _ => ()) catch {
    SparseError::Invalid(at, message) => {
      assert_eq(at, 16UL)
      assert_eq(message, "total blocks must be positive")
      rejected = true
    }
    other => raise other
  }
  assert_true(rejected)
  let mut poisoned = false
  parser.feed(b"", _ => ()) catch {
    SparseError::Invalid(_, message) => {
      assert_eq(message, "decoder is poisoned")
      poisoned = true
    }
    other => raise other
  }
  assert_true(poisoned)
}

///|
test "decoder rejects reuse after finish" {
  let parser = Decoder::new(verify_crc=true)
  parser.feed(b"", _ => ())
  let data = dec_test_join([
    dec_test_header(1U, 1U),
    dec_test_chunk(0xcac3, 1U, b""),
  ])
  parser.feed(data[:], _ => ())
  assert_eq(parser.finish().total_blocks, 1U)
  let mut rejected = false
  parser.feed(b"", _ => ()) catch {
    SparseError::Invalid(_, _) => rejected = true
    other => raise other
  }
  assert_true(rejected)
}

///|
test "decoder accepts optional and repeated prefix CRC chunks without resetting CRC" {
  let first = b"abcd"
  let second = b"efgh"
  let whole = b"abcdefgh"
  let first_crc = dec_test_crc(first[:])
  let whole_crc = dec_test_crc(whole[:])
  let data = dec_test_join([
    dec_test_header(2U, 6U, checksum=whole_crc),
    dec_test_chunk(0xcac4, 0U, dec_test_word(0U)),
    dec_test_chunk(0xcac1, 1U, first),
    dec_test_chunk(0xcac4, 0U, dec_test_word(first_crc)),
    dec_test_chunk(0xcac1, 1U, second),
    dec_test_chunk(0xcac4, 0U, dec_test_word(whole_crc)),
    dec_test_chunk(0xcac4, 0U, dec_test_word(whole_crc)),
  ])
  let parser = Decoder::new(verify_crc=true)
  let checksums : Array[UInt32] = []
  parser.feed(data[:], event => {
    if event is Checksum(value) {
      checksums.push(value)
    }
  })
  assert_eq(parser.finish().total_chunks, 6U)
  assert_eq(checksums, [0U, first_crc, whole_crc, whole_crc])
  assert_eq(parser.output_offset(), 8UL)

  // Header CRC verification works even if the image has no CRC chunks.
  let without_chunks = dec_test_join([
    dec_test_header(2U, 1U, checksum=whole_crc),
    dec_test_chunk(0xcac1, 2U, whole),
  ])
  let parser = Decoder::new(verify_crc=true)
  parser.feed(without_chunks[:], event => {
    if event is Checksum(_) {
      fail("unexpected CRC event")
    }
  })
  assert_eq(parser.finish().total_chunks, 1U)
}

///|
test "decoder rejects zero-payload CRC chunks instead of treating them as empty events" {
  dec_test_assert_invalid(
    dec_test_join([
      dec_test_header(1U, 2U),
      dec_test_chunk(0xcac3, 1U, b""),
      dec_test_chunk(0xcac4, 0U, b""),
    ]),
    offset=48UL,
  )
}

///|
test "decoder rejects finish from inside a callback even when its error is caught" {
  let parser = Decoder::new()
  let data = dec_test_join([
    dec_test_header(1U, 1U),
    dec_test_chunk(0xcac3, 1U, b""),
  ])
  let mut rejected = false
  parser.feed(data[:], _ => ignore(parser.finish()) catch { _ => () }) catch {
    SparseError::Invalid(_, _) => rejected = true
    other => raise other
  }
  assert_true(rejected)
}
