// NPZ container reader tests (v0.3.0, C1). Black-box: archives are
// hand-assembled below (same style as the hand-built NPY helpers in
// npy_test.mbt / edge_test.mbt), with the offsets needed to patch single
// fields for the refusal tests. Oracle byte-layout facts come from
// interoperability/probe_npz.py (numpy 2.3.4).

// ---- test-side helpers: NPY payloads and a minimal ZIP assembler ----

///|
// A v1.0 NPY byte image: header body + raw payload, header length uint16 LE
// at offset 8 (same hand-assembly style as npy_test.mbt v1_with_payload).
fn npy_v1(body : String, payload : Array[Byte]) -> Bytes {
  let bb = @utf8.encode(body)
  let hlen = bb.length()
  let arr : Array[Byte] = [
    b'\x93', b'N', b'U', b'M', b'P', b'Y', b'\x01', b'\x00',
  ]
  arr.push((hlen % 256).to_byte())
  arr.push((hlen / 256 % 256).to_byte())
  for i = 0; i < hlen; i = i + 1 {
    arr.push(bb[i])
  }
  for i = 0; i < payload.length(); i = i + 1 {
    arr.push(payload[i])
  }
  Bytes::from_array(arr)
}

///|
// Header body for a '<i4' (6,) C-order array (Oracle: np.arange(6)).
let i4_header : String = "{'descr': '<i4', 'fortran_order': False, 'shape': (6,), }"

///|
// Six int32 elements 0..5, little-endian.
fn i4_six() -> Array[Byte] {
  let arr : Array[Byte] = []
  for v = 0; v < 6; v = v + 1 {
    arr.push((v % 256).to_byte())
    arr.push(b'\x00')
    arr.push(b'\x00')
    arr.push(b'\x00')
  }
  arr
}

///|
// One stored-member entry for the ZIP assembler below. `method`/`gp_flags`
// default to a stored unencrypted member; tests override them to inject
// deflated / encrypted members without rebuilding the assembler.
struct ZipEntry {
  name : Bytes // raw member name, e.g. b"arr_0.npy"
  comp_method : Int
  gp_flags : Int
  payload : Bytes
}

///|
// The assembled image plus the offsets tests patch for refusal scenarios:
// the EOCD record start, each CD record start, each local header start.
struct ZipImage {
  bytes : Bytes
  eocd : Int
  cd : Array[Int]
  locals : Array[Int]
}

///|
fn put_u16(buf : Array[Byte], v : Int) -> Unit {
  buf.push((v % 256).to_byte())
  buf.push((v / 256 % 256).to_byte())
}

///|
fn put_u32(buf : Array[Byte], v : Int) -> Unit {
  buf.push((v % 256).to_byte())
  buf.push((v / 256 % 256).to_byte())
  buf.push((v / 65536 % 256).to_byte())
  buf.push((v / 16777216 % 256).to_byte())
}

///|
// Assemble a minimal ZIP archive from stored members: local headers (fixed
// 30 bytes, no extra fields) + payloads, then the central directory (46-byte
// records), then the EOCD. Sizes are the real payload lengths -- the reader
// must never depend on NumPy's streamed-placeholder layout, and this builder
// doubles as the "clean writer" half of that property.
fn build_zip(entries : Array[ZipEntry]) -> ZipImage {
  let buf : Array[Byte] = []
  let locals : Array[Int] = []
  let cd : Array[Int] = []
  // local headers + payloads
  for e in entries {
    locals.push(buf.length())
    for b in sig_local_test() {
      buf.push(b)
    }
    put_u16(buf, 20) // version needed
    put_u16(buf, e.gp_flags)
    put_u16(buf, e.comp_method)
    put_u16(buf, 0) // time
    put_u16(buf, 0) // date
    put_u32(buf, 0) // crc (never verified by the reader)
    put_u32(buf, e.payload.length()) // comp size
    put_u32(buf, e.payload.length()) // uncomp size
    put_u16(buf, e.name.length())
    put_u16(buf, 0) // extra len
    for i = 0; i < e.name.length(); i = i + 1 {
      buf.push(e.name[i])
    }
    for i = 0; i < e.payload.length(); i = i + 1 {
      buf.push(e.payload[i])
    }
  }
  // central directory
  let cd_offset = buf.length()
  for k = 0; k < entries.length(); k = k + 1 {
    let e = entries[k]
    cd.push(buf.length())
    for b in sig_central_test() {
      buf.push(b)
    }
    put_u16(buf, 20) // version made by
    put_u16(buf, 20) // version needed
    put_u16(buf, e.gp_flags)
    put_u16(buf, e.comp_method)
    put_u16(buf, 0) // time
    put_u16(buf, 0) // date
    put_u32(buf, 0) // crc
    put_u32(buf, e.payload.length()) // comp size
    put_u32(buf, e.payload.length()) // uncomp size
    put_u16(buf, e.name.length())
    put_u16(buf, 0) // extra len
    put_u16(buf, 0) // comment len
    put_u16(buf, 0) // disk start
    put_u16(buf, 0) // internal attrs
    put_u32(buf, 0) // external attrs
    put_u32(buf, locals[k]) // local header offset
    for i = 0; i < e.name.length(); i = i + 1 {
      buf.push(e.name[i])
    }
  }
  let cd_size = buf.length() - cd_offset
  // EOCD: sig(4) disk(2) cd_disk(2) disk_entries(2) total(2) cd_size(4)
  // cd_offset(4) comment_len(2) = 22 bytes.
  for b in sig_eocd_test() {
    buf.push(b)
  }
  put_u16(buf, 0) // disk number
  put_u16(buf, 0) // cd disk
  put_u16(buf, entries.length()) // disk entries
  put_u16(buf, entries.length()) // total entries
  put_u32(buf, cd_size)
  put_u32(buf, cd_offset)
  put_u16(buf, 0) // comment len
  ZipImage::{
    bytes: Bytes::from_array(buf),
    eocd: buf.length() - 22,
    cd,
    locals,
  }
}

///|
// ZIP record signatures for the test-side assembler.
fn sig_local_test() -> Array[Byte] {
  [b'P', b'K', b'\x03', b'\x04']
}

///|
fn sig_central_test() -> Array[Byte] {
  [b'P', b'K', b'\x01', b'\x02']
}

///|
fn sig_eocd_test() -> Array[Byte] {
  [b'P', b'K', b'\x05', b'\x06']
}

///|
// Replace `bs.length()` bytes of `data` at `offset` (test-side field patching
// for refusal scenarios the assembler cannot express).
fn patch_bytes(data : Bytes, offset : Int, bs : Array[Byte]) -> Bytes {
  let arr = data.to_array()
  for i = 0; i < bs.length(); i = i + 1 {
    arr[offset + i] = bs[i]
  }
  Bytes::from_array(arr)
}

///|
let ffff : Array[Byte] = [b'\xFF', b'\xFF']

///|
let ffffffff : Array[Byte] = [b'\xFF', b'\xFF', b'\xFF', b'\xFF']

///|
// A one-member archive (arr_0.npy = int32 0..5) used by most tests.
fn one_member_image() -> ZipImage {
  build_zip([
    {
      name: @utf8.encode("arr_0.npy"),
      comp_method: 0,
      gp_flags: 0,
      payload: npy_v1(i4_header, i4_six()),
    },
  ])
}

// ---- Task 1: EOCD location, zip64 sentinels, central-directory walk ----

///|
test "npz_reject_missing_eocd" {
  // Cut 10 bytes off the tail: the EOCD record no longer reaches the end of
  // the buffer, so no candidate position survives the exact-tail match.
  let img = one_member_image()
  let arr = img.bytes.to_array()
  let cut : Array[Byte] = []
  for i = 0; i < arr.length() - 10; i = i + 1 {
    cut.push(arr[i])
  }
  match @npz.decode_npz(Bytes::from_array(cut)) {
    Err(@error.NpzBadStructure(_)) => ()
    _ => assert_true(false)
  }
}

///|
test "npz_reject_too_short_for_eocd" {
  // Even a perfect EOCD image needs >= 22 bytes; anything shorter is
  // refused before scanning.
  let tiny = Bytes::from_array([b'\x00', b'\x00', b'\x00'])
  match @npz.decode_npz(tiny) {
    Err(@error.NpzBadStructure(_)) => ()
    _ => assert_true(false)
  }
}

///|
test "npz_reject_zip64_total_entries_sentinel" {
  // total_entries = 0xFFFF at EOCD+10 is the zip64 entry-count sentinel
  // (plan §2.2 step 2); refused before the central directory is touched.
  let img = one_member_image()
  let patched = patch_bytes(img.bytes, img.eocd + 10, ffff)
  match @npz.decode_npz(patched) {
    Err(@error.NpzZip64Unsupported) => ()
    _ => assert_true(false)
  }
}

///|
test "npz_reject_zip64_cd_size_sentinel" {
  let img = one_member_image()
  let patched = patch_bytes(img.bytes, img.eocd + 12, ffffffff)
  match @npz.decode_npz(patched) {
    Err(@error.NpzZip64Unsupported) => ()
    _ => assert_true(false)
  }
}

///|
test "npz_reject_zip64_cd_offset_sentinel" {
  let img = one_member_image()
  let patched = patch_bytes(img.bytes, img.eocd + 16, ffffffff)
  match @npz.decode_npz(patched) {
    Err(@error.NpzZip64Unsupported) => ()
    _ => assert_true(false)
  }
}

///|
test "npz_reject_central_directory_out_of_range" {
  // cd_offset claims 0x7FFFFFF0, far past the EOCD that describes it. The
  // Int64 comparison catches it without Int narrowing (§9.2 discipline).
  let img = one_member_image()
  let patched = patch_bytes(img.bytes, img.eocd + 16, [
    b'\xF0', b'\xFF', b'\xFF', b'\x7F',
  ])
  match @npz.decode_npz(patched) {
    Err(@error.NpzBadStructure(_)) => ()
    _ => assert_true(false)
  }
}

///|
test "npz_reject_bad_central_directory_signature" {
  // Point cd_offset at the member payload instead of the CD record.
  let img = one_member_image()
  let patched = patch_bytes(img.bytes, img.eocd + 16, [
    b'\x1E', b'\x00', b'\x00', b'\x00',
  ])
  match @npz.decode_npz(patched) {
    Err(@error.NpzBadStructure(_)) => ()
    _ => assert_true(false)
  }
}

///|
test "npz_single_member_decodes" {
  let img = one_member_image()
  match @npz.decode_npz(img.bytes) {
    Ok(arch) => {
      assert_eq(arch.members.length(), 1)
      // The key drops the ".npy" suffix np.savez adds.
      assert_eq(arch.members[0].name, "arr_0")
      assert_eq(arch.members[0].array.element_count, 6L)
      match arch.members[0].array.to_i32() {
        Ok(vs) => assert_eq(vs, [0, 1, 2, 3, 4, 5])
        _ => assert_true(false)
      }
    }
    Err(_) => assert_true(false)
  }
}

// ---- Task 1 (coverage): remaining walk branches and render surface ----

///|
test "npz_member_name_kept_without_npy_suffix" {
  // A member without the ".npy" suffix keeps its full name as the key.
  let img = build_zip([
    {
      name: @utf8.encode("plain"),
      comp_method: 0,
      gp_flags: 0,
      payload: npy_v1(i4_header, i4_six()),
    },
  ])
  match @npz.decode_npz(img.bytes) {
    Ok(arch) => assert_eq(arch.members[0].name, "plain")
    _ => assert_true(false)
  }
}

///|
test "npz_reject_member_name_not_utf8" {
  // 0xFF is never valid UTF-8: refused as BadStructure, never lossy-decoded
  // into a silently mangled key (Correctness first, mirroring the lexer).
  let img = one_member_image()
  let patched = patch_bytes(img.bytes, img.cd[0] + 46, [b'\xFF'])
  match @npz.decode_npz(patched) {
    Err(@error.NpzBadStructure(_)) => ()
    _ => assert_true(false)
  }
}

///|
test "npz_reject_bad_local_header_signature" {
  // The CD record points at a local header whose signature was clobbered.
  let img = one_member_image()
  let patched = patch_bytes(img.bytes, img.locals[0], [b'X'])
  match @npz.decode_npz(patched) {
    Err(@error.NpzBadStructure(_)) => ()
    _ => assert_true(false)
  }
}

///|
test "npz_reject_member_payload_out_of_range" {
  // comp_size inflated past the file end in the CD record: the payload
  // bounds check refuses before any slice is taken (§2.2 step 4b).
  let img = one_member_image()
  let patched = patch_bytes(img.bytes, img.cd[0] + 20, [
    b'\x00', b'\x00', b'\xF0', b'\x7F',
  ])
  match @npz.decode_npz(patched) {
    Err(@error.NpzBadStructure(_)) => ()
    _ => assert_true(false)
  }
}

///|
test "npz_reject_central_directory_entry_overrun" {
  // name_len inflated so the record's declared extent crosses the file end.
  let img = one_member_image()
  let patched = patch_bytes(img.bytes, img.cd[0] + 28, [b'\x00', b'\xF0'])
  match @npz.decode_npz(patched) {
    Err(@error.NpzBadStructure(_)) => ()
    _ => assert_true(false)
  }
}

///|
test "npz_member_npy_error_passes_through" {
  // A stored member whose NPY payload is broken (magic clobbered) fails with
  // the NPY-layer error unchanged -- the container adds no NPY semantics.
  let bad = npy_v1(i4_header, i4_six())
  let arr = bad.to_array()
  arr[0] = b'X'
  let img = build_zip([
    {
      name: @utf8.encode("arr_0.npy"),
      comp_method: 0,
      gp_flags: 0,
      payload: Bytes::from_array(arr),
    },
  ])
  match @npz.decode_npz(img.bytes) {
    Err(@error.InvalidMagic) => ()
    _ => assert_true(false)
  }
}

///|
test "npz_render_error_container_branches" {
  // v0.3.0 plan §3: every new NpyError variant has a render_error branch;
  // member names render verbatim, no sanitizing (UnsupportedDType policy).
  assert_eq(
    @cli.render_error(@error.NpzBadStructure("eocd not found")),
    "NpzBadStructure\nDetail: eocd not found",
  )
  assert_eq(
    @cli.render_error(@error.NpzCompressedMember("arr_0")),
    "NpzCompressedMember\nMember: arr_0",
  )
  assert_eq(
    @cli.render_error(@error.NpzUnsafeMemberName("../evil")),
    "NpzUnsafeMemberName\nMember: ../evil",
  )
  assert_eq(
    @cli.render_error(@error.NpzDuplicateMember("arr_0")),
    "NpzDuplicateMember\nMember: arr_0",
  )
  assert_eq(
    @cli.render_error(@error.NpzZip64Unsupported),
    "NpzZip64Unsupported",
  )
  assert_eq(
    @cli.render_error(@error.NpzMemberNotFound("nope")),
    "NpzMemberNotFound\nMember: nope",
  )
}
