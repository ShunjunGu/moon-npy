// Writer tests (M3): byte-level round-trip against the NumPy Oracle fixtures
// plus focused white-box checks. Plan §16 (decode -> encode byte-exact, the
// first-phase milestone gate NumPy -> MoonBit -> NumPy), §4.4 (the Writer never
// emits '='), §7.4 (64-byte alignment).
//
// `load_fixture` (npy_test.mbt, same package) reads tests/fixtures/<name>. The
// round-trip asserts encode(decode(f)) reproduces f exactly, which transitively
// proves the header dict form, descr rebuild, shape-tuple spelling, version
// field width, minimal padding, and verbatim payload copy for every dtype /
// layout / version combination NumPy 2.3.4 produced.

///|
// All 26 Oracle fixtures (numpy 2.3.4 np.save products, data_offset == 128).
// Round-tripping every one byte-exactly is the M3 acceptance gate.
fn fixture_names() -> Array[String] {
  [
    "b1_4_c_na_v1.npy", "f4_2x3_c_le_v1.npy", "f4_2x3_c_le_v2.npy", "f4_2x3_c_le_v3.npy",
    "f4_2x3_f_le_v1.npy", "f4_4_c_be_v1.npy", "f4_4_c_le_v1.npy", "f8_4_c_be_v1.npy",
    "f8_4_c_le_v1.npy", "f8_scalar_c_le_v1.npy", "i1_4_c_na_v1.npy", "i2_2x2x2_c_le_v1.npy",
    "i2_4_c_be_v1.npy", "i2_4_c_le_v1.npy", "i4_2x3_f_be_v1.npy", "i4_4_c_be_v1.npy",
    "i4_4_c_le_v1.npy", "i8_4_c_be_v1.npy", "i8_4_c_le_v1.npy", "u1_4_c_na_v1.npy",
    "u2_4_c_be_v1.npy", "u2_4_c_le_v1.npy", "u4_4_c_be_v1.npy", "u4_4_c_le_v1.npy",
    "u8_4_c_be_v1.npy", "u8_4_c_le_v1.npy",
  ]
}

///|
// decode a fixture then re-encode it; used by the focused white-box checks.
fn roundtrip(fixture : String) -> Bytes {
  let original = load_fixture(fixture)
  let decoded = @reader.decode(original).unwrap()
  @writer.encode(decoded).unwrap()
}

///|
// Assert encode re-emits `expected_dict` verbatim at the header-body offset.
fn check_dict(fixture : String, expected_dict : String) -> Unit {
  let encoded = roundtrip(fixture)
  let start = @format.parse_prefix(encoded).unwrap().header_start
  let want = @utf8.encode(expected_dict)
  for i = 0; i < want.length(); i = i + 1 {
    if encoded[start + i] != want[i] {
      abort("\{fixture}: header dict byte \{i} differs from the Oracle")
    }
  }
}

///|
// Assert the re-encoded prefix: version (major.minor), header-start (10 for v1,
// 12 for v2/v3), and a 64-byte-aligned data_offset (§7.4). Uses abort (not
// assert_eq) because assertions with an error effect are only allowed directly
// inside a `test` block, not in a plain helper fn.
fn check_prefix(fixture : String, major : Int, header_start : Int) -> Unit {
  let p = @format.parse_prefix(roundtrip(fixture)).unwrap()
  if p.major != major || p.minor != 0 || p.header_start != header_start {
    abort(
      "\{fixture}: version/header-start mismatch (major \{p.major}, start \{p.header_start})",
    )
  }
  if p.data_offset != 128L || p.data_offset % 64L != 0L {
    abort("\{fixture}: data_offset \{p.data_offset} not 64-aligned at 128")
  }
}

///|
// The M3 gate: for every Oracle fixture, decode -> encode is byte-identical.
// On mismatch, report the fixture name, the length delta, and the first byte
// offset that differs so a regression localizes immediately.
test "writer_roundtrip_byte_exact_all_fixtures" {
  let names = fixture_names()
  for k = 0; k < names.length(); k = k + 1 {
    let name = names[k]
    let original = load_fixture(name)
    let decoded = match @reader.decode(original) {
      Ok(a) => a
      Err(_) => abort("decode failed for \{name}")
    }
    let encoded = match @writer.encode(decoded) {
      Ok(b) => b
      Err(_) => abort("encode failed for \{name}")
    }
    if encoded.length() != original.length() {
      abort("\{name}: length \{encoded.length()} != \{original.length()}")
    }
    if encoded != original {
      let mut diff = -1
      for i = 0; i < original.length(); i = i + 1 {
        if diff < 0 && encoded[i] != original[i] {
          diff = i
        }
      }
      abort("\{name}: bytes differ at offset \{diff}")
    }
  }
}

///|
// §4.4: endian_char maps the four orders to '<' / '>' / '|', and Native ('=')
// normalizes to '<' -- the Writer never emits '='.
test "endian_char_never_emits_native" {
  assert_eq(@dtype.endian_char(@dtype.Little), "<")
  assert_eq(@dtype.endian_char(@dtype.Big), ">")
  assert_eq(@dtype.endian_char(@dtype.NotApplicable), "|")
  assert_eq(@dtype.endian_char(@dtype.Native), "<")
}

///|
// Version field width + 64-byte alignment: v1 uses a 2-byte header-len field
// (preamble 10), v2/v3 a 4-byte field (preamble 12); all payloads start at 128.
test "encode_version_field_and_alignment" {
  check_prefix("f4_2x3_c_le_v1.npy", 1, 10)
  check_prefix("f4_2x3_c_le_v2.npy", 2, 12)
  check_prefix("f4_2x3_c_le_v3.npy", 3, 12)
}

///|
// Header dict exact textual form (spelled-out Oracle strings): fixed key order
// descr -> fortran_order -> shape, single quotes, ': ' / ', ' separators, the
// trailing ', }', Python True/False, all four shape-tuple forms (0-d "()",
// 1-d "(4,)", 2-d "(2, 3)", 3-d "(2, 2, 2)"), '|'- and '>'-prefixed descrs.
test "encode_header_dict_exact_form" {
  check_dict(
    "f8_scalar_c_le_v1.npy", "{'descr': '<f8', 'fortran_order': False, 'shape': (), }",
  )
  check_dict(
    "b1_4_c_na_v1.npy", "{'descr': '|b1', 'fortran_order': False, 'shape': (4,), }",
  )
  check_dict(
    "f4_2x3_c_le_v1.npy", "{'descr': '<f4', 'fortran_order': False, 'shape': (2, 3), }",
  )
  check_dict(
    "i2_2x2x2_c_le_v1.npy", "{'descr': '<i2', 'fortran_order': False, 'shape': (2, 2, 2), }",
  )
  check_dict(
    "f4_4_c_be_v1.npy", "{'descr': '>f4', 'fortran_order': False, 'shape': (4,), }",
  )
  check_dict(
    "i4_2x3_f_be_v1.npy", "{'descr': '>i4', 'fortran_order': True, 'shape': (2, 3), }",
  )
}
