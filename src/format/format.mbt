// Low-level NPY byte structure: magic, version, header-length field.
// Plan §7.1-§7.2 (offsets), §9.3 (manual LE assembly), §9.2/B2 (Int64 discipline).
// Pure Bytes -> structure; no filesystem / CLI dependency (§10.2).

///|
// MAGIC_LEN == 8: magic(6) + version(2). The header-length field always starts
// at byte offset 8 (§7.2).
pub let magic_len : Int = 8

///|
// True iff `data` begins with the 6-byte magic prefix \x93NUMPY.
pub fn has_magic(data : Bytes) -> Bool {
  data.length() >= 6 &&
  data[0].to_int() == 147 && // 0x93
  data[1].to_int() == 78 && // 'N'
  data[2].to_int() == 85 && // 'U'
  data[3].to_int() == 77 && // 'M'
  data[4].to_int() == 80 && // 'P'
  data[5].to_int() == 89 // 'Y'
}

///|
pub(all) enum NpyVersion {
  V1_0
  V2_0
  V3_0
} derive(Debug, Eq)

///|
// Resolve (major, minor) to a supported version. Only `major` decides the
// header-length field width (v1 -> u16, v2/v3 -> u32); minor is informational.
pub fn version_of(
  major : Int,
  minor : Int,
) -> Result[NpyVersion, @error.NpyError] {
  match major {
    1 => Ok(V1_0)
    2 => Ok(V2_0)
    3 => Ok(V3_0)
    _ => Err(@error.UnsupportedVersion(major, minor))
  }
}

///|
// uint16 little-endian at byte offset `o` (manual assembly; no builtin, §9.3).
pub fn read_u16_le(data : Bytes, o : Int) -> Int {
  data[o].to_int() | (data[o + 1].to_int() << 8)
}

///|
// uint32 little-endian at byte offset `o`, widened to Int64 (§9.2 discipline).
pub fn read_u32_le(data : Bytes, o : Int) -> Int64 {
  data[o].to_int64() |
  (data[o + 1].to_int64() << 8) |
  (data[o + 2].to_int64() << 16) |
  (data[o + 3].to_int64() << 24)
}

///|
// Everything M1 needs from the fixed-size prefix, before the header body.
pub struct NpyPrefix {
  version : NpyVersion
  major : Int
  minor : Int
  header_len : Int64 // body length in bytes, after the length field
  header_start : Int // byte offset of the header body (10 for v1, 12 for v2/v3)
  data_offset : Int64 // header_start + header_len; where raw array data begins
}

///|
// Parse magic + version + header-length field and locate the header body span.
// Reader must NOT assume 64-byte alignment (§7.4): only header_len is trusted,
// so any padding the writer used is tolerated.
pub fn parse_prefix(data : Bytes) -> Result[NpyPrefix, @error.NpyError] {
  let total = data.length().to_int64()
  if total < 8L {
    Err(@error.TruncatedHeader)
  } else if has_magic(data) {
    let major = data[6].to_int()
    let minor = data[7].to_int()
    match version_of(major, minor) {
      Err(_) => Err(@error.UnsupportedVersion(major, minor))
      Ok(version) => {
        let header_start = if major == 1 { 10 } else { 12 }
        if total < header_start.to_int64() {
          Err(@error.TruncatedHeader)
        } else {
          let header_len = if major == 1 {
            read_u16_le(data, 8).to_int64()
          } else {
            read_u32_le(data, 8)
          }
          let data_offset = header_start.to_int64() + header_len
          if total < data_offset {
            Err(@error.TruncatedHeader)
          } else {
            Ok(NpyPrefix::{
              version,
              major,
              minor,
              header_len,
              header_start,
              data_offset,
            })
          }
        }
      }
    }
  } else {
    Err(@error.InvalidMagic)
  }
}
