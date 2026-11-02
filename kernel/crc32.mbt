///|
/// IEEE CRC-32 (the reflected polynomial used by zlib and Android libsparse).
let sparse_crc_table : FixedArray[UInt32] = FixedArray::makei(256, fn(i) {
  let mut value = i.reinterpret_as_uint()
  for bit = 0; bit < 8; bit = bit + 1 {
    value = if (value & 1U) != 0U {
      (value >> 1) ^ 0xedb88320U
    } else {
      value >> 1
    }
  }
  value
})

///|
/// Update an externally finalized CRC. Start a new checksum with zero.
pub fn crc32_update(crc : UInt32, data : BytesView) -> UInt32 {
  let mut value = crc ^ 0xffffffffU
  for byte in data {
    value = (value >> 8) ^
      sparse_crc_table[((value ^ byte.to_uint()) & 255U).reinterpret_as_int()]
  }
  value ^ 0xffffffffU
}

///|
/// Checksum repeated little-endian pattern bytes without expanding them.
/// The caller must enforce its CRC-work limit before calling this function.
pub fn crc32_repeat(crc : UInt32, pattern : UInt32, len : UInt64) -> UInt32 {
  let mut value = crc ^ 0xffffffffU
  let mut remaining = len
  let mut shift = 0
  while remaining > 0UL {
    let byte = (pattern >> shift) & 255U
    value = (value >> 8) ^
      sparse_crc_table[((value ^ byte) & 255U).reinterpret_as_int()]
    shift = (shift + 8) & 31
    remaining = remaining - 1UL
  }
  value ^ 0xffffffffU
}
