// NPZ writer tests (v0.3.0, N7). The write direction is validated through
// the pinned reader: every encode_npz output is fed back through decode_npz
// and compared member-by-member (self-read closure -- NpyArray has no public
// constructor, so the reader is the only interpreter of encoded archives).
// Python-side byte acceptance (zipfile / np.load) is the examples/npz_write
// Oracle (N7-4); the byte-layout facts it pins are interoperability/
// probe_npz.py outputs (numpy 2.3.4).

// ---- helpers ----

///|
// Decode an NPY image into an NpyArray for use as encode_npz input. Aborts
// (failing the test) when the reader refuses -- NpyArray is only reachable
// through @reader.decode.
fn npy_array_or_abort(data : Bytes, what : String) -> @reader.NpyArray {
  match @reader.decode(data) {
    Ok(a) => a
    Err(_) => abort("\{what}: decode failed")
  }
}

///|
// A key of `n` ASCII 'a's, for the stored-name length boundary tests.
fn ascii_key(n : Int) -> String {
  let bs : Array[Byte] = []
  for i = 0; i < n; i = i + 1 {
    bs.push(b'a')
  }
  let data = Bytes::from_array(bs)
  @utf8.decode(data.view(end=n)) catch {
    _ => abort("ascii_key construction failed")
  }
}

///|
// Recollect an archive's members as encode_npz input (the members field is
// private; get() is the accessor).
fn members_of(arch : @npz.NpzArchive) -> Array[@npz.NpzMember] {
  let out : Array[@npz.NpzMember] = []
  for k in arch.names() {
    match arch.get(k) {
      Ok(m) => out.push(m)
      Err(_) => abort("\{k}: member vanished")
    }
  }
  out
}

// ---- N7-3: encode_npz -- self-read closure, determinism, refusals ----

///|
test "npz_write_selfread_roundtrip" {
  // Three members across dtypes and source paths (committed fixture,
  // hand-assembled image): order preserved, header and data all equal.
  let a0 = npy_array_or_abort(load_fixture("f4_2x3_c_le_v1.npy"), "f4_2x3")
  let a1 = npy_array_or_abort(npy_v1(i4_header, i4_six()), "i4_six")
  let a2 = npy_array_or_abort(load_fixture("b1_4_c_na_v1.npy"), "b1_4")
  let keys = ["alpha", "beta", "gamma"]
  let inputs = [a0, a1, a2]
  let members : Array[@npz.NpzMember] = [
    @npz.NpzMember::{ name: "alpha", array: a0, },
    @npz.NpzMember::{ name: "beta", array: a1, },
    @npz.NpzMember::{ name: "gamma", array: a2, },
  ]
  let bytes = match @npz.encode_npz(members) {
    Ok(b) => b
    Err(_) => abort("encode_npz refused legal members")
  }
  match @npz.decode_npz(bytes) {
    Ok(arch) => {
      assert_eq(arch.names(), keys)
      for k = 0; k < keys.length(); k = k + 1 {
        match arch.get(keys[k]) {
          Ok(m) => {
            assert_eq(m.array.header.descr, inputs[k].header.descr)
            assert_eq(m.array.header.shape, inputs[k].header.shape)
            assert_eq(
              m.array.header.fortran_order,
              inputs[k].header.fortran_order,
            )
            assert_eq(m.array.element_count, inputs[k].element_count)
            assert_eq(m.array.data, inputs[k].data)
          }
          _ => abort("\{keys[k]}: member missing after self-read")
        }
      }
    }
    Err(_) => abort("decode_npz refused encode_npz output")
  }
}

///|
test "npz_write_roundtrip_is_byte_stable" {
  // Determinism: equal inputs -> byte-identical archives (fixed timestamp,
  // no compression). Fixed point: decode then re-encode reproduces the same
  // bytes, so a reader roundtrip loses nothing the writer would rewrite.
  let a0 = npy_array_or_abort(npy_v1(i4_header, i4_six()), "i4_six")
  let members : Array[@npz.NpzMember] = [
    @npz.NpzMember::{ name: "arr_0", array: a0, },
  ]
  let b1 = match @npz.encode_npz(members) {
    Ok(b) => b
    Err(_) => abort("encode_npz refused a legal member")
  }
  let b2 = match @npz.encode_npz(members) {
    Ok(b) => b
    Err(_) => abort("encode_npz refused a legal member")
  }
  assert_eq(b1, b2)
  let arch = match @npz.decode_npz(b1) {
    Ok(a) => a
    Err(_) => abort("decode_npz refused encode_npz output")
  }
  let b3 = match @npz.encode_npz(members_of(arch)) {
    Ok(b) => b
    Err(_) => abort("re-encode of decoded members failed")
  }
  assert_eq(b3, b1)
}

///|
test "npz_write_empty_archive" {
  // A zero-member archive is a legal stored-profile ZIP (EOCD only); it
  // must round-trip to an empty archive, not an error.
  let none : Array[@npz.NpzMember] = []
  let bytes = match @npz.encode_npz(none) {
    Ok(b) => b
    Err(_) => abort("encode_npz refused an empty archive")
  }
  match @npz.decode_npz(bytes) {
    Ok(arch) => assert_eq(arch.names(), [])
    Err(_) => abort("decode_npz refused an empty archive")
  }
}

///|
test "npz_write_reject_unsafe_name" {
  // Same refusal surface as the reader: path separators, a bare "..", and a
  // Windows drive-letter root are rejected with the offending key.
  let a0 = npy_array_or_abort(npy_v1(i4_header, i4_six()), "i4_six")
  match @npz.encode_npz([@npz.NpzMember::{ name: "a/b", array: a0, }]) {
    Err(@error.NpzUnsafeMemberName("a/b")) => ()
    _ => assert_true(false)
  }
  match @npz.encode_npz([@npz.NpzMember::{ name: "..", array: a0, }]) {
    Err(@error.NpzUnsafeMemberName("..")) => ()
    _ => assert_true(false)
  }
  match @npz.encode_npz([@npz.NpzMember::{ name: "C:data", array: a0, }]) {
    Err(@error.NpzUnsafeMemberName("C:data")) => ()
    _ => assert_true(false)
  }
  match @npz.encode_npz([@npz.NpzMember::{ name: "", array: a0, }]) {
    Err(@error.NpzUnsafeMemberName("")) => ()
    _ => assert_true(false)
  }
}

///|
test "npz_write_reject_duplicate_key" {
  let a0 = npy_array_or_abort(npy_v1(i4_header, i4_six()), "i4_six")
  match
    @npz.encode_npz([
      @npz.NpzMember::{ name: "arr_0", array: a0, },
      @npz.NpzMember::{ name: "arr_0", array: a0, },
    ]) {
    Err(@error.NpzDuplicateMember("arr_0")) => ()
    _ => assert_true(false)
  }
}

///|
test "npz_write_utf8_name_flag" {
  // Non-ASCII stored name: GP bit 11 set (LH bytes 6-7 = 0x00 0x08), so
  // Python's zipfile decodes the name as UTF-8 rather than cp437 mojibake.
  let a0 = npy_array_or_abort(npy_v1(i4_header, i4_six()), "i4_six")
  let zh = match
    @npz.encode_npz([@npz.NpzMember::{ name: "数据", array: a0, }]) {
    Ok(b) => b
    Err(_) => abort("encode_npz refused a UTF-8 key")
  }
  assert_eq(zh[6], b'\x00')
  assert_eq(zh[7], b'\x08')
  match @npz.decode_npz(zh) {
    Ok(arch) => {
      assert_eq(arch.names(), ["数据"])
      match arch.get("数据") {
        Ok(m) => assert_eq(m.array.data, a0.data)
        _ => abort("UTF-8 key missing after roundtrip")
      }
    }
    Err(_) => abort("decode_npz refused a UTF-8 key archive")
  }
  // Pure ASCII stored name: GP bit 11 clear.
  let ascii = match
    @npz.encode_npz([@npz.NpzMember::{ name: "plain", array: a0, }]) {
    Ok(b) => b
    Err(_) => abort("encode_npz refused an ASCII key")
  }
  assert_eq(ascii[6], b'\x00')
  assert_eq(ascii[7], b'\x00')
}

///|
test "npz_write_name_length_boundary" {
  // The stored name is "<key>.npy" (+4 bytes). 65535 bytes fit the u16
  // name_len field; 65536 would need zip64 and is refused up front.
  let a0 = npy_array_or_abort(npy_v1(i4_header, i4_six()), "i4_six")
  let fit = ascii_key(65531) // 65531 + 4 = 65535, the u16 ceiling
  let bytes = match
    @npz.encode_npz([@npz.NpzMember::{ name: fit, array: a0, }]) {
    Ok(b) => b
    Err(_) => abort("encode_npz refused a 65535-byte stored name")
  }
  match @npz.decode_npz(bytes) {
    Ok(arch) => {
      let names = arch.names()
      assert_eq(names.length(), 1)
      assert_eq(names[0].length(), 65531)
    }
    Err(_) => abort("decode_npz refused a 65535-byte stored name")
  }
  let over = ascii_key(65532) // 65532 + 4 = 65536 > 65535
  match @npz.encode_npz([@npz.NpzMember::{ name: over, array: a0, }]) {
    Err(@error.NpzZip64Unsupported) => ()
    _ => assert_true(false)
  }
}

///|
test "npz_write_repackage_oracle_fixture" {
  // Read a real NumPy archive, write its members back out, read again: the
  // semantic content is identical (byte layout intentionally differs -- the
  // clean profile drops NumPy's streamed placeholders and zip64 extra).
  let original = match @npz.decode_npz(load_fixture("npz_3arr_c_le_v1.npz")) {
    Ok(a) => a
    Err(_) => abort("decode of npz_3arr_c_le_v1.npz failed")
  }
  let bytes = match @npz.encode_npz(members_of(original)) {
    Ok(b) => b
    Err(_) => abort("re-encode of NumPy members failed")
  }
  match @npz.decode_npz(bytes) {
    Ok(arch) => {
      assert_eq(arch.names(), original.names())
      for k in original.names() {
        let want = match original.get(k) {
          Ok(m) => m
          Err(_) => abort("\{k}: original member missing")
        }
        let got = match arch.get(k) {
          Ok(m) => m
          Err(_) => abort("\{k}: repacked member missing")
        }
        assert_eq(got.array.header.descr, want.array.header.descr)
        assert_eq(got.array.header.shape, want.array.header.shape)
        assert_eq(got.array.element_count, want.array.element_count)
        assert_eq(got.array.data, want.array.data)
      }
    }
    Err(_) => abort("decode of repacked archive failed")
  }
}
