///|
fn writer_test_error(action : () -> Unit raise) -> String {
  try {
    action()
    "accepted"
  } catch {
    SparseError::Invalid(_, _) => "invalid"
    SparseError::LimitExceeded(_, _) => "limit"
    _ => "other"
  }
}

///|
test "CRC32 matches the standard vector and segmented updates" {
  assert_eq(crc32_update(0U, b"123456789"), 0xcbf43926U)
  let first = crc32_update(0U, b"1234")
  assert_eq(crc32_update(first, b"56789"), 0xcbf43926U)
  assert_eq(crc32_update(first, b""), first)
}

///|
test "CRC32 repeated patterns use little-endian bytes and allow a partial word" {
  // Independent Python zlib.crc32 vectors, not sparse-decoder round trips.
  assert_eq(crc32_repeat(0U, 0x04030201U, 12UL), 0xb19e38c6U)
  assert_eq(crc32_repeat(0U, 0x04030201U, 6UL), 0xe2f77639U)
  assert_eq(crc32_repeat(0U, 0U, 8UL), 0x6522df69U)
  assert_eq(crc32_repeat(0x12345678U, 0U, 0UL), 0x12345678U)
}

///|
test "writer emits exact v1 headers RAW FILL holes and final CRC32" {
  let encoded = encode(
    [Data(b"abcd"), Fill(0x04030201U, 2U), Hole(1U)],
    block_size=4U,
    max_output_bytes=88UL,
  )
  assert_eq(encoded.length(), 88)
  assert_eq(
    encoded[0:28],
    b"\x3a\xff\x26\xed\x01\x00\x00\x00\x1c\x00\x0c\x00\x04\x00\x00\x00\x04\x00\x00\x00\x04\x00\x00\x00\x00\x00\x00\x00"[:],
  )
  assert_eq(
    encoded[28:44],
    b"\xc1\xca\x00\x00\x01\x00\x00\x00\x10\x00\x00\x00abcd"[:],
  )
  assert_eq(
    encoded[44:60],
    b"\xc2\xca\x00\x00\x02\x00\x00\x00\x10\x00\x00\x00\x01\x02\x03\x04"[:],
  )
  assert_eq(
    encoded[60:72],
    b"\xc3\xca\x00\x00\x01\x00\x00\x00\x0c\x00\x00\x00"[:],
  )
  assert_eq(
    encoded[72:88],
    b"\xc4\xca\x00\x00\x00\x00\x00\x00\x10\x00\x00\x00\x73\x63\xef\xf2"[:],
  )
}

///|
test "pack groups consecutive RAW and equal FILL blocks" {
  let raw = b"abcdefghABCDEFGH\x01\x02\x03\x04\x01\x02\x03\x04\x01\x02\x03\x04\x01\x02\x03\x04\x00\x00\x00\x00\x00\x00\x00\x00"
  let encoded = pack(raw, block_size=8U, checksum=false, max_output_bytes=88UL)
  assert_eq(encoded.length(), 88)
  assert_eq(read_u32(encoded, 16), 5U)
  assert_eq(read_u32(encoded, 20), 3U)
  assert_eq(
    encoded[28:40],
    b"\xc1\xca\x00\x00\x02\x00\x00\x00\x1c\x00\x00\x00"[:],
  )
  assert_eq(encoded[40:56], b"abcdefghABCDEFGH"[:])
  assert_eq(
    encoded[56:72],
    b"\xc2\xca\x00\x00\x02\x00\x00\x00\x10\x00\x00\x00\x01\x02\x03\x04"[:],
  )
  assert_eq(
    encoded[72:88],
    b"\xc2\xca\x00\x00\x01\x00\x00\x00\x10\x00\x00\x00\x00\x00\x00\x00"[:],
  )
}

///|
test "pack zero data becomes FILL zero and never DONT_CARE" {
  let encoded = pack(
    b"\x00\x00\x00\x00\x00\x00\x00\x00",
    block_size=4U,
    max_output_bytes=60UL,
  )
  assert_eq(
    encoded[28:44],
    b"\xc2\xca\x00\x00\x02\x00\x00\x00\x10\x00\x00\x00\x00\x00\x00\x00"[:],
  )
  assert_eq(encoded[56:60], b"\x69\xdf\x22\x65"[:])
}

///|
test "explicit Data preserves RAW including literal zeros" {
  let encoded = encode(
    [Data(b"\x00\x00\x00\x00")],
    block_size=4U,
    checksum=false,
    max_output_bytes=44UL,
  )
  assert_eq(read_u16(encoded, 28), 0xcac1)
}

///|
test "writer rejects zero-block images for AOSP interoperability" {
  assert_eq(
    writer_test_error(() => {
      ignore(pack(b"", block_size=4U, max_output_bytes=44UL))
    }),
    "invalid",
  )
  assert_eq(
    writer_test_error(() => ignore(encode([], max_output_bytes=44UL))),
    "invalid",
  )
  assert_eq(
    writer_test_error(() => {
      ignore(encode([], checksum=false, max_output_bytes=28UL))
    }),
    "invalid",
  )
}

///|
test "empty piece array is rejected before the first sink write" {
  let mut writes = 0
  assert_eq(
    writer_test_error(() => write_sparse([], emit=_ => writes = writes + 1)),
    "invalid",
  )
  assert_eq(writes, 0)
}

///|
test "stream writer validates all pieces before emitting" {
  let mut writes = 0
  let error = writer_test_error(() => {
    write_sparse([Data(b"abcd"), Data(b"x")], block_size=4U, emit=_ => {
      writes = writes + 1
    })
  })
  assert_eq(error, "invalid")
  assert_eq(writes, 0)
}

///|
test "writer rejects invalid block sizes empty pieces and partial blocks" {
  for size in [0U, 2U, 6U] {
    assert_eq(
      writer_test_error(() => {
        ignore(encode([], block_size=size, max_output_bytes=64UL))
      }),
      "invalid",
    )
  }
  assert_eq(
    writer_test_error(() => ignore(encode([Data(b"")], max_output_bytes=64UL))),
    "invalid",
  )
  assert_eq(
    writer_test_error(() => ignore(encode([Hole(0U)], max_output_bytes=64UL))),
    "invalid",
  )
  assert_eq(
    writer_test_error(() => {
      ignore(encode([Fill(0U, 0U)], max_output_bytes=64UL))
    }),
    "invalid",
  )
  assert_eq(
    writer_test_error(() => {
      ignore(pack(b"abc", block_size=4U, max_output_bytes=64UL))
    }),
    "invalid",
  )
}

///|
test "writer rejects aggregate UInt32 block overflow before emitting" {
  let mut writes = 0
  assert_eq(
    writer_test_error(() => {
      write_sparse(
        [Hole(0xffffffffU), Hole(1U)],
        block_size=4U,
        checksum=false,
        emit=_ => writes = writes + 1,
      )
    }),
    "invalid",
  )
  assert_eq(writes, 0)
}

///|
test "writer applies independent output chunk expansion and checksum limits" {
  let pieces : Array[Piece] = [Fill(0U, 2U)]
  assert_eq(
    writer_test_error(() => {
      ignore(encode(pieces, block_size=4U, max_output_bytes=59UL))
    }),
    "limit",
  )
  assert_eq(
    writer_test_error(() => {
      ignore(
        encode(pieces, block_size=4U, max_output_bytes=60UL, limits={
          max_expanded_bytes: 7UL,
          max_crc_bytes: 8UL,
          max_chunks: 2U,
        }),
      )
    }),
    "limit",
  )
  assert_eq(
    writer_test_error(() => {
      ignore(
        encode(pieces, block_size=4U, max_output_bytes=60UL, limits={
          max_expanded_bytes: 8UL,
          max_crc_bytes: 7UL,
          max_chunks: 2U,
        }),
      )
    }),
    "limit",
  )
  assert_eq(
    writer_test_error(() => {
      ignore(
        encode(pieces, block_size=4U, max_output_bytes=60UL, limits={
          max_expanded_bytes: 8UL,
          max_crc_bytes: 8UL,
          max_chunks: 1U,
        }),
      )
    }),
    "limit",
  )
}

///|
test "huge logical hole stays compact when checksum is disabled" {
  let encoded = encode(
    [Hole(0xffffffffU)],
    block_size=4U,
    checksum=false,
    max_output_bytes=40UL,
  )
  assert_eq(encoded.length(), 40)
  assert_eq(read_u32(encoded, 16), 0xffffffffU)
  assert_eq(read_u16(encoded, 28), 0xcac3)
  assert_eq(
    writer_test_error(() => {
      ignore(encode([Hole(0xffffffffU)], block_size=4U, max_output_bytes=56UL))
    }),
    "limit",
  )
}

///|
test "stream writer bounds RAW sink chunks and propagates sink errors" {
  let raw = Bytes::make(131072, b'x')
  let mut largest = 0
  let mut delivered = 0
  write_sparse([Data(raw)], checksum=false, emit=fn(bytes) {
    delivered = delivered + bytes.length()
    if bytes.length() > largest {
      largest = bytes.length()
    }
  })
  assert_eq(delivered, 131112)
  assert_eq(largest, 65536)
  let mut calls = 0
  let propagated = try {
    write_sparse([Hole(1U)], block_size=4U, emit=_ => {
      calls = calls + 1
      raise SparseError::Invalid(777UL, "sink sentinel")
    })
    false
  } catch {
    SparseError::Invalid(777UL, "sink sentinel") => true
    _ => false
  }
  assert_true(propagated)
  assert_eq(calls, 1)
}

///|
test "pack enforces limits while grouping many different patterns" {
  let raw = b"abcdEFGHijkl"
  assert_eq(
    writer_test_error(() => {
      ignore(pack(raw, block_size=4U, checksum=false, max_output_bytes=59UL))
    }),
    "limit",
  )
  assert_eq(
    writer_test_error(() => {
      ignore(
        pack(raw, block_size=4U, checksum=false, max_output_bytes=100UL, limits={
          max_expanded_bytes: 12UL,
          max_crc_bytes: 12UL,
          max_chunks: 2U,
        }),
      )
    }),
    "limit",
  )
}
