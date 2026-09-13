// NPZ container (v0.3.0, C1 read / N7 write): uncompressed `np.savez`
// archives. Each member is a complete NPY byte stream, so member extraction
// delegates to `@reader.decode` and reuses every validation of the
// single-file reader, including the object-dtype refusal -- the container
// adds no NPY semantics of its own, and NPY-layer errors pass through
// unchanged. The write direction (encode_npz, N7) emits the "clean"
// counterpart of the pinned facts below: real CRCs and sizes (no streamed
// placeholders, no zip64 extra field), version-2.0 records, stored method,
// and the fixed 1980-01-01 timestamp probe_npz.py measured on NumPy itself
// (Python's zipfile default) -- deterministic byte-for-byte, and accepted by
// `np.load`.
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

// ---- write direction (N7): a "clean" stored np.savez encoder ----

///|
// Push a non-negative Int below 65536 as two little-endian bytes. The
// writer's only u16 fields are versions, flags, fixed dates, and the two
// lengths already checked against 65535, so callers prove the bound.
fn push_u16(out : Array[Byte], v : Int) -> Unit {
  out.push((v % 256).to_byte())
  out.push((v / 256 % 256).to_byte())
}

///|
// Emit a non-negative Int as four little-endian bytes. Int is 32-bit, so a
// value can never reach the 0xFFFFFFFF zip64 sentinel this writer never
// writes (Bytes lengths are bounded by Int's positive range).
fn push_u32(out : Array[Byte], v : Int) -> Unit {
  out.push((v % 256).to_byte())
  out.push((v / 256 % 256).to_byte())
  out.push((v / 65536 % 256).to_byte())
  out.push((v / 16777216 % 256).to_byte())
}

///|
// Emit a CRC-32 as four little-endian bytes. Each byte is masked to 0..255
// BEFORE the UInt -> Int reinterpretation: a direct UInt-to-Int conversion
// would turn any CRC >= 2^31 negative and produce garbage bytes.
fn push_crc32(out : Array[Byte], crc : UInt) -> Unit {
  out.push((crc & 0xFFU).reinterpret_as_int().to_byte())
  out.push(((crc >> 8) & 0xFFU).reinterpret_as_int().to_byte())
  out.push(((crc >> 16) & 0xFFU).reinterpret_as_int().to_byte())
  out.push(((crc >> 24) & 0xFFU).reinterpret_as_int().to_byte())
}

///|
// True when the stored name holds a byte >= 0x80, i.e. the name is not pure
// ASCII. Such names set the UTF-8 name flag (GP bit 11) so Python's zipfile
// decodes them as UTF-8 instead of cp437 -- the same pairing Python's own
// zipfile emits when it stores a non-ASCII name.
fn member_name_non_ascii(name : Bytes) -> Bool {
  for i = 0; i < name.length(); i = i + 1 {
    if name[i].to_uint() > 0x7FU {
      return true
    }
  }
  false
}

///|
// Encode an uncompressed np.savez archive (the N7 write direction): one
// stored member "<key>.npy" per input member, in input order, so
// decode_npz(encode_npz(x)) round-trips exactly the inputs the reader
// accepts. Refusals mirror the reader one-for-one -- unsafe key ->
// NpzUnsafeMemberName, duplicate key -> NpzDuplicateMember, an archive
// needing zip64 -> NpzZip64Unsupported (more than 65535 members, or a
// stored name over 65535 bytes); NPY-layer errors from @writer.encode pass
// through unchanged. The output is the "clean" counterpart of the pinned
// byte-layout facts: real CRCs and sizes (no streamed placeholders, no
// zip64 extra), version-2.0 header fields, stored method, and the fixed
// 1980-01-01 timestamp -- deterministic byte-for-byte, and accepted by
// Python's zipfile / np.load. Non-ASCII keys set the UTF-8 name flag
// (GP bit 11), so they never decode as cp437 mojibake.
pub fn encode_npz(members : Array[NpzMember]) -> Result[Bytes, @error.NpyError] {
  // Zip64 surface at write time: only the member count and the stored name
  // length can reach a u16 field's range (sizes and offsets live in Int and
  // Bytes, both strictly below any u32 sentinel).
  if members.length() > 65535 {
    return Err(@error.NpzZip64Unsupported)
  }
  let out : Array[Byte] = []
  let stored_names : Array[Bytes] = []
  let sizes : Array[Int] = []
  let crcs : Array[UInt] = []
  let gp_flags : Array[Int] = []
  let local_offsets : Array[Int] = []
  let seen : Array[String] = []
  for m in members {
    if unsafe_member_name(m.name) {
      return Err(@error.NpzUnsafeMemberName(m.name))
    }
    for prior in seen {
      if prior == m.name {
        return Err(@error.NpzDuplicateMember(m.name))
      }
    }
    seen.push(m.name)
    let payload = match @writer.encode(m.array) {
      Ok(p) => p
      Err(e) => return Err(e) // NPY-layer errors pass through unchanged
    }
    let stored = @utf8.encode("\{m.name}.npy")
    if stored.length() > 65535 {
      return Err(@error.NpzZip64Unsupported)
    }
    let crc = crc32(payload)
    let gp = if member_name_non_ascii(stored) { 0x0800 } else { 0 }
    // Local file header: 30 fixed bytes + name + stored payload. The crc and
    // size fields are the REAL values (the clean profile's point -- the
    // reader ignores the local size fields anyway, probe fact).
    local_offsets.push(out.length())
    for b in sig_local {
      out.push(b)
    }
    push_u16(out, 20) // version needed to extract: 2.0
    push_u16(out, gp)
    push_u16(out, 0) // compression method: stored
    push_u16(out, 0) // last mod time: 0x0000 (fixed, 1980-01-01)
    push_u16(out, 0x0021) // last mod date: 0x0021 (fixed, 1980-01-01)
    push_crc32(out, crc)
    push_u32(out, payload.length()) // compressed size (stored: equal)
    push_u32(out, payload.length()) // uncompressed size
    push_u16(out, stored.length()) // file name length
    push_u16(out, 0) // extra field length (no zip64 extra in the clean form)
    for i = 0; i < stored.length(); i = i + 1 {
      out.push(stored[i])
    }
    for i = 0; i < payload.length(); i = i + 1 {
      out.push(payload[i])
    }
    stored_names.push(stored)
    sizes.push(payload.length())
    crcs.push(crc)
    gp_flags.push(gp)
  }
  // Central directory: 46 fixed bytes + name per member; the authoritative
  // size/offset source decode_npz reads, holding the real values written
  // above.
  let cd_offset = out.length()
  for k = 0; k < members.length(); k = k + 1 {
    let stored = stored_names[k]
    for b in sig_central {
      out.push(b)
    }
    push_u16(out, 20) // version made by: 2.0
    push_u16(out, 20) // version needed to extract: 2.0
    push_u16(out, gp_flags[k])
    push_u16(out, 0) // compression method: stored
    push_u16(out, 0) // time
    push_u16(out, 0x0021) // date
    push_crc32(out, crcs[k])
    push_u32(out, sizes[k]) // compressed size
    push_u32(out, sizes[k]) // uncompressed size
    push_u16(out, stored.length()) // name length
    push_u16(out, 0) // extra length
    push_u16(out, 0) // comment length
    push_u16(out, 0) // disk number start
    push_u16(out, 0) // internal attributes
    push_u32(out, 0) // external attributes
    push_u32(out, local_offsets[k]) // relative offset of the local header
    for i = 0; i < stored.length(); i = i + 1 {
      out.push(stored[i])
    }
  }
  // End of central directory: 22 fixed bytes. Counts fit 65535 (checked
  // above); no comment, no zip64 records.
  let cd_size = out.length() - cd_offset
  for b in sig_eocd {
    out.push(b)
  }
  push_u16(out, 0) // number of this disk
  push_u16(out, 0) // disk with the central directory
  push_u16(out, members.length()) // entries on this disk
  push_u16(out, members.length()) // total entries
  push_u32(out, cd_size)
  push_u32(out, cd_offset)
  push_u16(out, 0) // comment length
  Ok(Bytes::from_array(out))
}
