///|
/// Errors carry the serialized input offset, or zero for an encoding error.
pub(all) suberror SparseError {
  Invalid(UInt64, String)
  LimitExceeded(UInt64, String)
} derive(Debug, Eq)

///|
/// Wire-format fields. Minor versions are accepted when the v1 layout is valid.
pub(all) struct Header {
  major_version : Int32
  minor_version : Int32
  file_header_size : Int32
  chunk_header_size : Int32
  block_size : UInt32
  total_blocks : UInt32
  total_chunks : UInt32
  image_checksum : UInt32
} derive(Debug, Eq)

///|
pub fn Header::expanded_size(self : Header) -> UInt64 {
  self.block_size.to_uint64() * self.total_blocks.to_uint64()
}

///|
pub(all) enum ChunkKind {
  Raw
  Fill
  Skip
  Crc32
} derive(Debug, Eq)

///|
pub(all) struct Chunk {
  index : UInt32
  kind : ChunkKind
  input_offset : UInt64
  output_offset : UInt64
  blocks : UInt32
  total_size : UInt32
} derive(Debug, Eq)

///|
/// RawData borrows its input. A sink that retains it must call to_owned().
pub(all) enum Event {
  FileHeader(Header)
  ChunkHeader(Chunk)
  RawData(BytesView)
  FillData(UInt32, UInt64)
  SkipData(UInt64)
  Checksum(UInt32)
} derive(Debug)

///|
/// Logical output, checksum work and chunk counts have separate limits.
pub(all) struct Limits {
  max_expanded_bytes : UInt64
  max_crc_bytes : UInt64
  max_chunks : UInt32
} derive(Debug, Eq)

///|
pub fn default_limits() -> Limits {
  {
    max_expanded_bytes: 68719476736UL,
    max_crc_bytes: 268435456UL,
    max_chunks: 1000000U,
  }
}

///|
/// Explicit holes are the only source of DONT_CARE chunks.
pub(all) enum Piece {
  Data(Bytes)
  Fill(UInt32, UInt32)
  Hole(UInt32)
} derive(Debug, Eq)

///|
/// Internal endian helpers require a caller-validated range.
fn read_u16(data : BytesView, at : Int32) -> Int32 {
  data[at].to_int() | (data[at + 1].to_int() << 8)
}

///|
fn read_u32(data : BytesView, at : Int32) -> UInt32 {
  data[at].to_uint() |
  (data[at + 1].to_uint() << 8) |
  (data[at + 2].to_uint() << 16) |
  (data[at + 3].to_uint() << 24)
}

///|
pub extend SparseError with Eq::{equal, not_equal}

///|
pub extend Header with Eq::{equal, not_equal}

///|
pub extend ChunkKind with Eq::{equal, not_equal}

///|
pub extend Chunk with Eq::{equal, not_equal}

///|
pub extend Limits with Eq::{equal, not_equal}

///|
pub extend Piece with Eq::{equal, not_equal}

///|
pub extend SparseError with @debug.Debug::{to_repr}

///|
pub extend Header with @debug.Debug::{to_repr}

///|
pub extend ChunkKind with @debug.Debug::{to_repr}

///|
pub extend Chunk with @debug.Debug::{to_repr}

///|
pub extend Event with @debug.Debug::{to_repr}

///|
pub extend Limits with @debug.Debug::{to_repr}

///|
pub extend Piece with @debug.Debug::{to_repr}
