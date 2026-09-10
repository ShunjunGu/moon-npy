// Integration tests for the M1 NPY header pipeline (plan §11 layout, §14 tests).
//
// Blackbox tests against the public API of the error / format / header packages.
// Positive cases read the byte-exact NumPy Oracle fixtures under tests/fixtures/
// (produced by interoperability/generate_fixtures.py with numpy 2.3.4) and assert
// the offsets and fields recorded in tests/fixtures/expected.json. `moon test`
// runs with the module root as CWD, so fixtures are addressed as
// "tests/fixtures/<name>". Negative cases synthesize malformed inputs and assert
// the exact NpyError variant (§12 error model) rather than a bare Bool/String.

// Read a fixture's raw bytes. Aborts (failing the test) if the Oracle file is
// missing or unreadable, so a broken fixture path can never silently pass.

///|
fn load_fixture(name : String) -> Bytes {
  let path = "tests/fixtures/\{name}"
  let res = try @fs.read_file_to_bytes(path) |> Ok catch {
    e => Err(e)
  }
  res.unwrap()
}

// Build a minimal v1.0 NPY blob whose header body is exactly `body`, with no
// data section and no 64-byte alignment. header_len is written uint16 LE. Used
// to synthesize malformed headers for the negative tests without a fixture.

///|
fn v1_with_body(body : String) -> Bytes {
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
  Bytes::from_array(arr)
}

// Canonical names of the byte-exact NumPy Oracle fixtures (31, kept in sync
// with tests/fixtures/expected.json). Single source of truth for the fuzz
// mutations, the round-trip property test, and X2 -- adding a fixture here is
// enough; every test follows (v0.2.0 S1 added the 5 complex ones).

///|
fn oracle_fixture_names() -> Array[String] {
  [
    "b1_4_c_na_v1.npy", "c16_4_c_be_v1.npy", "c16_4_c_le_v1.npy", "c8_2x3_c_le_v1.npy",
    "c8_4_c_be_v1.npy", "c8_4_c_le_v1.npy", "f4_2x3_c_le_v1.npy", "f4_2x3_c_le_v2.npy",
    "f4_2x3_c_le_v3.npy", "f4_2x3_f_le_v1.npy", "f4_4_c_be_v1.npy", "f4_4_c_le_v1.npy",
    "f8_4_c_be_v1.npy", "f8_4_c_le_v1.npy", "f8_scalar_c_le_v1.npy", "i1_4_c_na_v1.npy",
    "i2_2x2x2_c_le_v1.npy", "i2_4_c_be_v1.npy", "i2_4_c_le_v1.npy", "i4_2x3_f_be_v1.npy",
    "i4_4_c_be_v1.npy", "i4_4_c_le_v1.npy", "i8_4_c_be_v1.npy", "i8_4_c_le_v1.npy",
    "u1_4_c_na_v1.npy", "u2_4_c_be_v1.npy", "u2_4_c_le_v1.npy", "u4_4_c_be_v1.npy",
    "u4_4_c_le_v1.npy", "u8_4_c_be_v1.npy", "u8_4_c_le_v1.npy",
  ]
}

// ---- format: manual little-endian assembly (§9.3, AGENTS.md §3 verified) ----

///|
test "read_u16_le" {
  let data = Bytes::from_array([b'\x01', b'\x02'])
  assert_eq(@format.read_u16_le(data, 0), 513) // 0x01 | (0x02 << 8)
}

///|
test "read_u32_le" {
  let data = Bytes::from_array([b'\x01', b'\x02', b'\x03', b'\x04'])
  assert_eq(@format.read_u32_le(data, 0), 67305985L) // 0x04030201
}

///|
test "has_magic" {
  let good = Bytes::from_array([
    b'\x93', b'N', b'U', b'M', b'P', b'Y', b'\x01', b'\x00',
  ])
  assert_true(@format.has_magic(good))
  let bad = Bytes::from_array([
    b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00',
  ])
  assert_false(@format.has_magic(bad))
  let short = Bytes::from_array([b'\x93', b'N'])
  assert_false(@format.has_magic(short))
}

// ---- format.parse_prefix: magic + version + header-length field (§7.2) ----

///|
test "parse_prefix_v1" {
  let p = @format.parse_prefix(load_fixture("f4_2x3_c_le_v1.npy")).unwrap()
  assert_eq(p.major, 1)
  assert_eq(p.minor, 0)
  assert_eq(p.header_len, 118L)
  assert_eq(p.header_start, 10)
  assert_eq(p.data_offset, 128L)
}

///|
test "parse_prefix_v2" {
  let p = @format.parse_prefix(load_fixture("f4_2x3_c_le_v2.npy")).unwrap()
  assert_eq(p.major, 2)
  assert_eq(p.minor, 0)
  assert_eq(p.header_len, 116L)
  assert_eq(p.header_start, 12)
  assert_eq(p.data_offset, 128L)
}

///|
test "parse_prefix_v3" {
  let p = @format.parse_prefix(load_fixture("f4_2x3_c_le_v3.npy")).unwrap()
  assert_eq(p.major, 3)
  assert_eq(p.minor, 0)
  assert_eq(p.header_len, 116L)
  assert_eq(p.header_start, 12)
  assert_eq(p.data_offset, 128L)
}

// ---- header.parse_header: restricted Python literal -> NpyHeader (§7.3) ----

///|
test "parse_header_v1" {
  let h = @header.parse_header(load_fixture("f4_2x3_c_le_v1.npy")).unwrap()
  assert_eq(h.descr, "<f4")
  assert_eq(h.shape, [2UL, 3UL])
  assert_eq(h.fortran_order, false)
}

///|
test "parse_header_v2" {
  let h = @header.parse_header(load_fixture("f4_2x3_c_le_v2.npy")).unwrap()
  assert_eq(h.descr, "<f4")
  assert_eq(h.shape, [2UL, 3UL])
  assert_eq(h.fortran_order, false)
}

///|
test "parse_header_v3" {
  let h = @header.parse_header(load_fixture("f4_2x3_c_le_v3.npy")).unwrap()
  assert_eq(h.descr, "<f4")
  assert_eq(h.shape, [2UL, 3UL])
  assert_eq(h.fortran_order, false)
}

// ---- negative: format prefix errors (§12) ----

///|
test "reject_invalid_magic" {
  let bad = Bytes::from_array([
    b'N', b'O', b'T', b'N', b'P', b'Y', b'\x01', b'\x00',
  ])
  match @format.parse_prefix(bad) {
    Err(@error.InvalidMagic) => ()
    _ => assert_true(false)
  }
}

///|
test "reject_truncated_prefix" {
  let tiny = Bytes::from_array([b'\x93', b'N']) // shorter than magic_len (8)
  match @format.parse_prefix(tiny) {
    Err(@error.TruncatedHeader) => ()
    _ => assert_true(false)
  }
}

///|
test "reject_unsupported_version" {
  let bad = Bytes::from_array([
    b'\x93', b'N', b'U', b'M', b'P', b'Y', b'\x09', b'\x00', // major = 9
  ])
  match @format.parse_prefix(bad) {
    Err(@error.UnsupportedVersion(_, _)) => ()
    _ => assert_true(false)
  }
}

// ---- negative: header body errors (§12) ----

///|
test "reject_header_invalid_syntax" {
  // '{' followed by a byte that cannot begin any token in the grammar
  let blob = v1_with_body("{!")
  match @header.parse_header(blob) {
    Err(@error.InvalidHeaderSyntax) => ()
    _ => assert_true(false)
  }
}

///|
test "reject_header_missing_field" {
  // well-formed literal but omits the 'shape' key (closed set, §12)
  let blob = v1_with_body("{'descr': '<f4', 'fortran_order': False}")
  match @header.parse_header(blob) {
    Err(@error.MissingHeaderField(_)) => ()
    _ => assert_true(false)
  }
}

///|
test "reject_header_unknown_key" {
  // an extra key beyond {descr, fortran_order, shape} is rejected, not ignored
  let blob = v1_with_body(
    "{'descr': '<f4', 'fortran_order': False, 'shape': (2, 3), 'extra': 1}",
  )
  match @header.parse_header(blob) {
    Err(@error.InvalidHeaderSyntax) => ()
    _ => assert_true(false)
  }
}
