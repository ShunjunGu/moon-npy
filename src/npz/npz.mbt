// NPZ container reader (v0.3.0, C1): read-only, uncompressed `np.savez`
// archives. Each member is a complete NPY byte stream, so member extraction
// delegates to `@reader.decode` and reuses every validation of the
// single-file reader, including the object-dtype refusal -- the container
// adds no NPY semantics of its own, and NPY-layer errors pass through
// unchanged.
//
// Security posture (plan v0.3.0 §1/§2.2): the container is never inflated and
// no member byte is ever executed; anything outside the read-only stored
// profile is refused as a structured NpyError before the payload is touched
// -- compressed members, zip64 archives, path-traversal names, duplicate
// names (zip shadowing), encrypted members, malformed containers. Total
// invariant (§18 style): for any Bytes input, decode_npz returns
// Ok(NpzArchive) or Err(NpyError) -- never a panic, never an inflate, never
// an execution of container bytes.
//
// Byte-layout facts pinned by interoperability/probe_npz.py (numpy 2.3.4):
//   * the local header's crc/size fields are 0xFFFFFFFF placeholders for
//     streamed members, so the member length is taken from the central
//     directory's comp_size while the data start is computed from the LOCAL
//     header's own name_len/extra_len (30 + name_len + extra_len); the local
//     size fields are never trusted;
//   * a zip64 extra field (id 0x0001) may appear in the local header even
//     when the sizes fit 32 bits -- its presence is NOT a zip64 archive; the
//     zip64 criteria are the EOCD / central-directory field sentinels
//     0xFFFF / 0xFFFFFFFF (comment_len excluded: a 65535-byte comment is a
//     legal non-zip64 tail, not a size sentinel).
// Offsets are compared in Int64 (u32 fields widen) and narrowed to Int only
// after being proven <= file length (§9.2/B2 discipline, flat_range
// precedent): a u32 offset can exceed Int's positive range, so .to_int()
// happens strictly after the bound check.

///|
// ZIP record signatures (local file header / central directory / EOCD).
let sig_local : Array[Byte] = [b'P', b'K', b'\x03', b'\x04']

///|
let sig_central : Array[Byte] = [b'P', b'K', b'\x01', b'\x02']

///|
let sig_eocd : Array[Byte] = [b'P', b'K', b'\x05', b'\x06']

///|
// A decoded member of an NPZ archive. `name` is the archive key WITHOUT the
// trailing ".npy" (np.savez stores "<key>.npy"); `array` is the fully decoded
// NPY payload.
pub(all) struct NpzMember {
  name : String
  array : @reader.NpyArray
}

///|
// A decoded NPZ archive. Members keep central-directory order (deterministic;
// probe note: np.savez writes keyword members before positional ones).
// Duplicates and unsafe names never reach this type -- they error out
// earlier. No Debug derive: NpyArray has none, and the archive is asserted
// through its members, not its repr.
pub struct NpzArchive {
  members : Array[NpzMember]
}

///|
// Look up a member by its archive key (without ".npy"). A miss is
// NpzMemberNotFound -- get() is the only producer of that variant
// (plan §3: a lookup failure, not a container defect, semantically kin to
// MissingHeaderField).
pub fn NpzArchive::get(
  self : NpzArchive,
  key : String,
) -> Result[NpzMember, @error.NpyError] {
  for m in self.members {
    if m.name == key {
      return Ok(m)
    }
  }
  Err(@error.NpzMemberNotFound(key))
}

///|
// Member keys in central-directory order (deterministic; probe note:
// np.savez writes keyword members before positional ones).
pub fn NpzArchive::names(self : NpzArchive) -> Array[String] {
  let out : Array[String] = []
  for m in self.members {
    out.push(m.name)
  }
  out
}

///|
// Byte-exact signature match at `base` (bounds-checked; never traps).
fn match_sig(data : Bytes, base : Int, sig : Array[Byte]) -> Bool {
  if base < 0 || base + sig.length() > data.length() {
    return false
  }
  for i = 0; i < sig.length(); i = i + 1 {
    if data[base + i] != sig[i] {
      return false
    }
  }
  true
}

///|
// Copy `len` bytes of `data` starting at `base` into a fresh Bytes. Mirrors
// reader.slice_payload (reader.mbt): Bytes is immutable with no zero-copy
// sub-slice returning Bytes, and the npz package cannot reach the reader's
// private helper -- the duplication is the accepted cost of keeping the
// reader package unaware of containers (no cyclic dependency).
fn slice_bytes(data : Bytes, base : Int, len : Int) -> Bytes {
  let arr = Array::make(len, b'\x00')
  for i = 0; i < len; i = i + 1 {
    arr[i] = data[base + i]
  }
  Bytes::from_array(arr)
}

///|
// Locate the end-of-central-directory record: scan backwards from the last
// possible position (a trailing comment can extend the record's tail, so at
// most 22 + 65535 bytes back), accepting the highest offset whose declared
// comment length reaches exactly the end of the buffer. No candidate means
// the container is malformed -- or not an archive at all.
fn find_eocd(data : Bytes) -> Result[Int, @error.NpyError] {
  let file_len = data.length()
  if file_len < 22 {
    return Err(@error.NpzBadStructure("eocd not found"))
  }
  let scan_start = if file_len - 22 > 65535 { file_len - 22 - 65535 } else { 0 }
  let mut pos = file_len - 22
  while pos >= scan_start {
    if match_sig(data, pos, sig_eocd) {
      let comment_len = @format.read_u16_le(data, pos + 20)
      if pos + 22 + comment_len == file_len {
        return Ok(pos)
      }
    }
    pos = pos - 1
  }
  Err(@error.NpzBadStructure("eocd not found"))
}

///|
// Decode a member name as UTF-8 and strip the ".npy" suffix np.savez adds.
// A name that is not valid UTF-8 is a malformed container (BadStructure),
// never a silently mangled key (decode, not decode_lossy -- Correctness
// first, mirroring the NPY header lexer). A member without the suffix keeps
// its full name as the archive key.
fn resolve_member_name(raw : Bytes) -> Result[String, @error.NpyError] {
  let decoded = try @utf8.decode(raw.view(end=raw.length())) |> Ok catch {
    _ => Err(@error.NpzBadStructure("member name not utf-8"))
  }
  let name = match decoded {
    Ok(n) => n
    Err(e) => return Err(e)
  }
  let n = name.length()
  if n >= 4 && name[n - 4:] == ".npy" {
    Ok(name[:n - 4].to_owned())
  } else {
    Ok(name)
  }
}

///|
// Decode an uncompressed np.savez archive. Refuses (structured NpyError,
// never panic): compressed members (NpzCompressedMember), zip64 archives
// (NpzZip64Unsupported), path-traversal names (NpzUnsafeMemberName),
// duplicate names (NpzDuplicateMember), encrypted or malformed containers
// (NpzBadStructure). NPY-level errors from member payloads pass through
// unchanged.
pub fn decode_npz(data : Bytes) -> Result[NpzArchive, @error.NpyError] {
  let file_len = data.length()
  let eocd = match find_eocd(data) {
    Ok(p) => p
    Err(e) => return Err(e)
  }
  // EOCD fields (little-endian, plan §2.3). The sentinel checks run before
  // any offset math so a zip64 archive is refused before its oversized
  // offsets can even be interpreted.
  if @format.read_u16_le(data, eocd + 4) == 0xFFFF ||
    @format.read_u16_le(data, eocd + 6) == 0xFFFF ||
    @format.read_u16_le(data, eocd + 8) == 0xFFFF ||
    @format.read_u16_le(data, eocd + 10) == 0xFFFF {
    return Err(@error.NpzZip64Unsupported)
  }
  let cd_offset = @format.read_u32_le(data, eocd + 16)
  let cd_size = @format.read_u32_le(data, eocd + 12)
  if cd_offset == 0xFFFFFFFFL || cd_size == 0xFFFFFFFFL {
    return Err(@error.NpzZip64Unsupported)
  }
  let total_entries = @format.read_u16_le(data, eocd + 10)
  // The central directory must sit entirely before the EOCD that describes
  // it (Int64 compare -- a u32 offset can exceed Int's positive range).
  if cd_offset + cd_size > eocd.to_int64() {
    return Err(@error.NpzBadStructure("central directory out of range"))
  }
  let members : Array[NpzMember] = []
  let seen : Array[String] = []
  let mut pos = cd_offset.to_int()
  for i = 0; i < total_entries; i = i + 1 {
    // Central-directory record: 46 fixed bytes + name + extra + comment.
    if pos + 46 > file_len || !match_sig(data, pos, sig_central) {
      return Err(@error.NpzBadStructure("central directory entry \{i}"))
    }
    let name_len = @format.read_u16_le(data, pos + 28)
    let extra_len = @format.read_u16_le(data, pos + 30)
    let comment_len = @format.read_u16_le(data, pos + 32)
    let next = pos + 46 + name_len + extra_len + comment_len
    if next > file_len {
      return Err(@error.NpzBadStructure("central directory entry \{i}"))
    }
    let comp_method = @format.read_u16_le(data, pos + 10)
    let gp_flags = @format.read_u16_le(data, pos + 8)
    let comp_size = @format.read_u32_le(data, pos + 20)
    let local_offset = @format.read_u32_le(data, pos + 42)
    let name = match
      resolve_member_name(slice_bytes(data, pos + 46, name_len)) {
      Ok(n) => n
      Err(e) => return Err(e)
    }
    // Security refusals (v0.3.0 plan §2.2 step 4). Order: compression first
    // (nothing about a deflated member is safe to reason about), then the
    // name surface, then duplicates, then encryption.
    if comp_method != 0 {
      return Err(@error.NpzCompressedMember(name))
    }
    if unsafe_member_name(name) {
      return Err(@error.NpzUnsafeMemberName(name))
    }
    for prior in seen {
      if prior == name {
        return Err(@error.NpzDuplicateMember(name))
      }
    }
    seen.push(name)
    if (gp_flags & 0x0001) != 0 {
      return Err(@error.NpzBadStructure("encrypted member: \{name}"))
    }
    // Locate the member payload: the local header's own name/extra lengths
    // decide where the data starts (probe fact); the length comes from the
    // central directory (the local size fields are 0xFFFFFFFF placeholders).
    if local_offset + 30 > file_len.to_int64() ||
      !match_sig(data, local_offset.to_int(), sig_local) {
      return Err(@error.NpzBadStructure("local header: \{name}"))
    }
    let lo = local_offset.to_int()
    let lname_len = @format.read_u16_le(data, lo + 26)
    let lextra_len = @format.read_u16_le(data, lo + 28)
    let data_start = local_offset +
      30 +
      lname_len.to_int64() +
      lextra_len.to_int64()
    if data_start + comp_size > file_len.to_int64() {
      return Err(@error.NpzBadStructure("member payload out of range: \{name}"))
    }
    let payload = slice_bytes(data, data_start.to_int(), comp_size.to_int())
    let array = match @reader.decode(payload) {
      Ok(a) => a
      Err(e) => return Err(e) // NPY-layer errors pass through unchanged
    }
    members.push(NpzMember::{ name, array, })
    pos = next
  }
  Ok(NpzArchive::{ members, })
}

///|
// True when a member name must never become a filesystem-style key:
// any path separator (a single '/' or '\' already covers traversal,
// absolute paths and multi-segment names), a bare ".." segment, or a
// Windows drive-letter root ("C:..."). Refused before extraction, so the
// name never reaches a consumer.
fn unsafe_member_name(name : String) -> Bool {
  for c in name {
    if c == '/' || c == '\\' {
      return true
    }
  }
  if name == ".." {
    return true
  }
  name.length() >= 2 && name.get_char(1) == Some(':')
}
