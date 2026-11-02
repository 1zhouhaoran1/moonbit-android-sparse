///|
/// Small host adapter. Format parsing and checksum work stay in the pure core.
priv struct Session {
  decoder : @sparse.Decoder
  chunks : Array[@sparse.Chunk]
  verify_crc : Bool
  keep_chunks : Bool
  output : ((Bytes) -> Unit)?
  mut complete : Bool
  mut saw_checksum : Bool
  mut error : Json?
}

///|
priv struct Registry {
  sessions : Map[Int32, Session]
  mut next_id : Int32
}

///|
let registry : Registry = { sessions: {}, next_id: 1, }

///|
fn error_json(error : Error) -> Json {
  let (offset, message) = match error {
    @sparse.Invalid(offset, message) => (offset.to_string(), message)
    @sparse.LimitExceeded(offset, message) => (offset.to_string(), message)
    _ => ("0", error.to_string())
  }
  { "ok": false, "error": { "offset": offset, "message": message } }
}

///|
fn missing_session() -> Json {
  { "ok": false, "error": { "offset": "0", "message": "Session is closed" } }
}

///|
fn register(
  verify_crc : Bool,
  keep_chunks : Bool,
  output : ((Bytes) -> Unit)?,
  max_output : UInt64,
) -> Int32 {
  if registry.sessions.length() >= 16 {
    return -1
  }
  let id = registry.next_id
  registry.next_id = if id == 2147483647 { 1 } else { id + 1 }
  let limits = @sparse.default_limits()
  registry.sessions[id] = {
    decoder: @sparse.Decoder::new(verify_crc~, limits={
      max_expanded_bytes: max_output,
      max_crc_bytes: limits.max_crc_bytes,
      max_chunks: if keep_chunks {
        10000U
      } else {
        limits.max_chunks
      },
    }),
    chunks: [],
    verify_crc,
    keep_chunks,
    output,
    complete: false,
    saw_checksum: false,
    error: None,
  }
  id
}

///|
#export_name("create_inspector")
pub fn create_inspector(verify_crc : Bool) -> Int32 {
  register(verify_crc, true, None, 68719476736UL)
}

///|
/// The synchronous host sink enables bounded streaming file expansion.
#export_name("create_expander")
pub fn create_expander(
  verify_crc : Bool,
  max_output_bytes : Double,
  output : (Bytes) -> Unit,
) -> Int32 {
  if !(max_output_bytes >= 0.0 && max_output_bytes <= 9007199254740991.0) {
    return -1
  }
  register(verify_crc, false, Some(output), max_output_bytes.to_uint64())
}

///|
extern "js" fn try_output(output : (Bytes) -> Unit, data : Bytes) -> String =
  #| (output, data) => { try { output(data); return ""; } catch (error) { return "Output sink failed: " + String(error); } }

///|
fn write_output(output : (Bytes) -> Unit, data : Bytes) -> Unit raise {
  let failure = try_output(output, data)
  if failure != "" {
    raise @sparse.Invalid(0UL, failure)
  }
}

///|
fn emit_pattern(
  output : (Bytes) -> Unit,
  pattern : UInt32,
  size : UInt64,
) -> Unit raise {
  let buffer = Bytes::makei(4, i => (pattern >> (i * 8)).to_byte()).repeat(
    16384,
  )
  let mut left = size
  while left > 0UL {
    let length = if left > 65536UL { 65536 } else { left.to_int() }
    if length == 65536 {
      write_output(output, buffer)
    } else {
      write_output(output, buffer[:length].to_owned())
    }
    left = left - length.to_uint64()
  }
}

///|
fn accept_event(session : Session, event : @sparse.Event) -> Unit raise {
  match event {
    @sparse.ChunkHeader(chunk) =>
      if session.keep_chunks {
        session.chunks.push(chunk)
      }
    @sparse.Checksum(_) => session.saw_checksum = true
    @sparse.RawData(data) =>
      match session.output {
        Some(output) => {
          let mut at = 0
          while at < data.length() {
            let end = at +
              (if data.length() - at > 65536 {
                65536
              } else {
                data.length() - at
              })
            write_output(output, data[at:end].to_owned())
            at = end
          }
        }
        None => ()
      }
    @sparse.FillData(pattern, size) =>
      match session.output {
        Some(output) => emit_pattern(output, pattern, size)
        None => ()
      }
    @sparse.SkipData(size) =>
      match session.output {
        Some(output) => emit_pattern(output, 0U, size)
        None => ()
      }
    _ => ()
  }
}

///|
#export_name("feed_inspector")
pub fn feed_inspector(id : Int32, data : Bytes) -> String {
  guard registry.sessions.get(id) is Some(session) else {
    return missing_session().stringify()
  }
  if session.error is Some(error) {
    return error.stringify()
  }
  try {
    session.decoder.feed(data[:], event => accept_event(session, event))
    "{\"ok\":true}"
  } catch {
    error => {
      let result = error_json(error)
      session.error = Some(result)
      result.stringify()
    }
  }
}

///|
fn header_json(header : @sparse.Header) -> Json {
  {
    "majorVersion": header.major_version,
    "minorVersion": header.minor_version,
    "blockSize": header.block_size.to_double(),
    "totalBlocks": header.total_blocks.to_double(),
    "totalChunks": header.total_chunks.to_double(),
    "expandedBytes": header.expanded_size().to_string(),
    "imageChecksum": header.image_checksum.to_string(radix=16),
  }
}

///|
fn chunk_json(chunk : @sparse.Chunk) -> Json {
  let kind = match chunk.kind {
    @sparse.Raw => "RAW"
    @sparse.Fill => "FILL"
    @sparse.Skip => "DONT_CARE"
    @sparse.Crc32 => "CRC32"
  }
  {
    "index": chunk.index.to_double(),
    "kind": kind,
    "inputOffset": chunk.input_offset.to_string(),
    "outputOffset": chunk.output_offset.to_string(),
    "blocks": chunk.blocks.to_double(),
    "totalSize": chunk.total_size.to_double(),
  }
}

///|
fn report(session : Session) -> Json {
  if session.error is Some(error) {
    return error
  }
  let header = session.decoder.header()
  let crc_status = if !session.verify_crc {
    "unchecked"
  } else if !session.complete {
    "checking"
  } else if session.saw_checksum ||
    (header is Some({ image_checksum, .. }) && image_checksum != 0U) {
    "verified"
  } else {
    "absent"
  }
  {
    "ok": true,
    "header": match header {
      Some(value) => header_json(value)
      None => Json::null()
    },
    "chunks": session.chunks.map(chunk_json),
    "inputBytes": session.decoder.input_offset().to_string(),
    "outputBytes": session.decoder.output_offset().to_string(),
    "chunksRead": session.decoder.chunks_read().to_double(),
    "crcStatus": crc_status,
    "complete": session.complete,
  }
}

///|
#export_name("inspector_report")
pub fn inspector_report(id : Int32) -> String {
  match registry.sessions.get(id) {
    Some(session) => report(session).stringify()
    None => missing_session().stringify()
  }
}

///|
#export_name("finish_inspector")
pub fn finish_inspector(id : Int32) -> String {
  guard registry.sessions.get(id) is Some(session) else {
    return missing_session().stringify()
  }
  if session.error is Some(error) {
    return error.stringify()
  }
  try {
    ignore(session.decoder.finish())
    session.complete = true
    report(session).stringify()
  } catch {
    error => {
      let result = error_json(error)
      session.error = Some(result)
      result.stringify()
    }
  }
}

///|
#export_name("dispose_inspector")
pub fn dispose_inspector(id : Int32) -> Unit {
  registry.sessions.remove(id)
}

///|
/// Synthetic data: one literal block, two repeated-pattern blocks, a hole.
#export_name("make_sample")
pub fn make_sample() -> Bytes {
  let raw = Bytes::makei(4096, i => ((i * 37 + i / 17) % 256).to_byte())
  let pieces : Array[@sparse.Piece] = [
    @sparse.Data(raw),
    @sparse.Fill(0x12345678U, 2U),
    @sparse.Hole(3U),
    @sparse.Fill(0U, 2U),
  ]
  @sparse.encode(pieces, max_output_bytes=65536UL) catch {
    _ => b""
  }
}

///|
extern "js" fn fail_host(message : String) -> Bytes =
  #| (message) => { throw new Error(message); }

///|
/// A bounded convenience API; the host checks the input cap before reading.
#export_name("pack_bytes")
pub fn pack_bytes(raw : Bytes, block_size : Int32) -> Bytes {
  if block_size <= 0 {
    return fail_host("Block size must be positive")
  }
  @sparse.pack(
    raw[:],
    block_size=block_size.reinterpret_as_uint(),
    max_output_bytes=67108864UL,
  ) catch {
    error => fail_host(error_json(error).stringify())
  }
}
