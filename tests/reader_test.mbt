// M2 reader tests (plan §9.1, §10.1, §14/§17). Blackbox against the public API
// of the reader package, with every positive value pinned to the byte-exact
// NumPy 2.3.4 Oracle in tests/fixtures/expected.json (flat_values = storage
// order). Big-endian fixtures carry the same flat_values as their little-endian
// twins, so a wrong byte reversal (e.g. reading 0x0001 as 0x0100 = 256) fails
// the assertion -- the endianness path is genuinely exercised, not assumed.

///|
// decode() a fixture and unwrap; aborts the test on an unexpected Err.
fn decode_fixture(name : String) -> @reader.NpyArray {
  @reader.decode(load_fixture(name)).unwrap()
}

///|
// Widen a decoded float32 array to Double so it can be compared against Double
// literals without a Float-literal ambiguity (values are exact small integers).
fn f32_as_doubles(arr : @reader.NpyArray) -> Array[Double] {
  arr.to_f32().unwrap().map(fn(x) { x.to_double() })
}

///|
test "decode_f4_2x3_v1" {
  let a = decode_fixture("f4_2x3_c_le_v1.npy")
  assert_eq(a.version, @format.V1_0)
  assert_eq(a.dtype, @dtype.Float32)
  assert_eq(a.byte_order, @dtype.Little)
  assert_eq(a.element_count, 6L)
  assert_eq(a.header.descr, "<f4")
  assert_false(a.header.fortran_order)
  assert_eq(a.header.shape, [2UL, 3UL])
  assert_eq(f32_as_doubles(a), [0.0, 1.0, 2.0, 3.0, 4.0, 5.0])
}

///|
test "decode_f4_2x3_v2_v3" {
  let v2 = decode_fixture("f4_2x3_c_le_v2.npy")
  assert_eq(v2.version, @format.V2_0)
  assert_eq(f32_as_doubles(v2), [0.0, 1.0, 2.0, 3.0, 4.0, 5.0])
  let v3 = decode_fixture("f4_2x3_c_le_v3.npy")
  assert_eq(v3.version, @format.V3_0)
  assert_eq(f32_as_doubles(v3), [0.0, 1.0, 2.0, 3.0, 4.0, 5.0])
}

///|
test "decode_bool" {
  let a = decode_fixture("b1_4_c_na_v1.npy")
  assert_eq(a.dtype, @dtype.Bool)
  assert_eq(a.element_count, 4L)
  assert_eq(a.to_bool().unwrap(), [true, false, true, false])
}

///|
test "decode_signed_ints" {
  let i1 = decode_fixture("i1_4_c_na_v1.npy")
  assert_eq(i1.dtype, @dtype.Int8)
  assert_eq(i1.to_i8().unwrap(), [0, 1, 2, 3])
  for name in ["i2_4_c_le_v1.npy", "i2_4_c_be_v1.npy"] {
    let x = decode_fixture(name)
    assert_eq(x.dtype, @dtype.Int16)
    assert_eq(x.to_i16().unwrap(), [0, 1, 2, 3])
  }
  for name in ["i4_4_c_le_v1.npy", "i4_4_c_be_v1.npy"] {
    let x = decode_fixture(name)
    assert_eq(x.dtype, @dtype.Int32)
    assert_eq(x.to_i32().unwrap(), [0, 1, 2, 3])
  }
  for name in ["i8_4_c_le_v1.npy", "i8_4_c_be_v1.npy"] {
    let x = decode_fixture(name)
    assert_eq(x.dtype, @dtype.Int64)
    assert_eq(x.to_i64().unwrap(), [0L, 1L, 2L, 3L])
  }
}

///|
test "decode_unsigned_ints" {
  let u1 = decode_fixture("u1_4_c_na_v1.npy")
  assert_eq(u1.dtype, @dtype.UInt8)
  assert_eq(u1.to_u8().unwrap(), [0, 1, 2, 3])
  for name in ["u2_4_c_le_v1.npy", "u2_4_c_be_v1.npy"] {
    let x = decode_fixture(name)
    assert_eq(x.to_u16().unwrap(), [0, 1, 2, 3])
  }
  for name in ["u4_4_c_le_v1.npy", "u4_4_c_be_v1.npy"] {
    let x = decode_fixture(name)
    assert_eq(x.dtype, @dtype.UInt32)
    assert_eq(x.to_u32().unwrap(), [0L, 1L, 2L, 3L])
  }
  for name in ["u8_4_c_le_v1.npy", "u8_4_c_be_v1.npy"] {
    let x = decode_fixture(name)
    assert_eq(x.dtype, @dtype.UInt64)
    assert_eq(x.to_u64().unwrap(), [0UL, 1UL, 2UL, 3UL])
  }
}

///|
test "decode_floats_1d" {
  for name in ["f4_4_c_le_v1.npy", "f4_4_c_be_v1.npy"] {
    let x = decode_fixture(name)
    assert_eq(x.dtype, @dtype.Float32)
    assert_eq(f32_as_doubles(x), [0.0, 1.0, 2.0, 3.0])
  }
  for name in ["f8_4_c_le_v1.npy", "f8_4_c_be_v1.npy"] {
    let x = decode_fixture(name)
    assert_eq(x.dtype, @dtype.Float64)
    assert_eq(x.to_f64().unwrap(), [0.0, 1.0, 2.0, 3.0])
  }
}

///|
test "decode_byte_order" {
  assert_eq(decode_fixture("i2_4_c_le_v1.npy").byte_order, @dtype.Little)
  assert_eq(decode_fixture("i2_4_c_be_v1.npy").byte_order, @dtype.Big)
  assert_eq(decode_fixture("b1_4_c_na_v1.npy").byte_order, @dtype.NotApplicable)
}

///|
test "decode_scalar_0d" {
  let a = decode_fixture("f8_scalar_c_le_v1.npy")
  assert_eq(a.header.shape, [])
  assert_eq(a.element_count, 1L)
  assert_eq(a.to_f64().unwrap(), [0.0])
}

///|
test "decode_3d_shape" {
  let a = decode_fixture("i2_2x2x2_c_le_v1.npy")
  assert_eq(a.header.shape, [2UL, 2UL, 2UL])
  assert_eq(a.element_count, 8L)
  assert_eq(a.to_i16().unwrap(), [0, 1, 2, 3, 4, 5, 6, 7])
}

///|
test "decode_fortran_order_flat_storage" {
  // fortran_order is metadata for the consumer; the flat accessor still returns
  // storage order, matching the Oracle's flat_values (column-major bytes).
  let f = decode_fixture("f4_2x3_f_le_v1.npy")
  assert_true(f.header.fortran_order)
  assert_eq(f.byte_order, @dtype.Little)
  assert_eq(f32_as_doubles(f), [0.0, 1.0, 2.0, 3.0, 4.0, 5.0])
  let g = decode_fixture("i4_2x3_f_be_v1.npy")
  assert_true(g.header.fortran_order)
  assert_eq(g.byte_order, @dtype.Big)
  assert_eq(g.to_i32().unwrap(), [0, 1, 2, 3, 4, 5])
}

///|
test "validate_metadata" {
  let m = @reader.validate(load_fixture("f4_2x3_c_le_v1.npy")).unwrap()
  assert_eq(m.version, @format.V1_0)
  assert_eq(m.dtype, @dtype.Float32)
  assert_eq(m.element_count, 6L)
  assert_eq(m.data_offset, 128L)
  assert_eq(m.payload_len, 24L)
}

///|
test "decode_complex64" {
  // Both byte orders must yield the same logical elements. Oracle (S1):
  // im = 2 * re, so a swapped real/imag read fails immediately.
  for name in ["c8_4_c_le_v1.npy", "c8_4_c_be_v1.npy"] {
    let x = decode_fixture(name)
    assert_eq(x.dtype, @dtype.Complex64)
    assert_eq(x.element_count, 4L)
    assert_eq(x.to_c64().unwrap(), [
      @dtype.Complex::{ re: 0.0, im: 0.0, },
      @dtype.Complex::{ re: 1.0, im: 2.0, },
      @dtype.Complex::{ re: 2.0, im: 4.0, },
      @dtype.Complex::{ re: 3.0, im: 6.0, },
    ])
  }
}

///|
test "decode_complex128" {
  for name in ["c16_4_c_le_v1.npy", "c16_4_c_be_v1.npy"] {
    let x = decode_fixture(name)
    assert_eq(x.dtype, @dtype.Complex128)
    assert_eq(x.element_count, 4L)
    assert_eq(x.to_c16().unwrap(), [
      @dtype.Complex::{ re: 0.0, im: 0.0, },
      @dtype.Complex::{ re: 1.0, im: 2.0, },
      @dtype.Complex::{ re: 2.0, im: 4.0, },
      @dtype.Complex::{ re: 3.0, im: 6.0, },
    ])
  }
}

///|
test "decode_complex_2d" {
  // Q2: accessors are flat/storage-order; shape stays metadata.
  let x = decode_fixture("c8_2x3_c_le_v1.npy")
  assert_eq(x.header.shape, [2UL, 3UL])
  assert_eq(x.element_count, 6L)
  assert_eq(x.to_c64().unwrap().length(), 6)
  assert_eq(x.to_c64().unwrap()[5], @dtype.Complex::{ re: 5.0, im: 10.0, })
}

// ---- negative cases (§12 / §18) ----

///|
test "accessor_rejects_wrong_dtype" {
  let a = decode_fixture("f4_2x3_c_le_v1.npy")
  match a.to_i32() {
    Err(@error.UnsupportedDType(_)) => ()
    _ => assert_true(false)
  }
  match a.to_f64() {
    Err(@error.UnsupportedDType(_)) => ()
    _ => assert_true(false)
  }
}

///|
test "complex_accessor_rejects_wrong_dtype" {
  let a = decode_fixture("f4_2x3_c_le_v1.npy")
  match a.to_c64() {
    Err(@error.UnsupportedDType(_)) => ()
    _ => assert_true(false)
  }
  match a.to_c16() {
    Err(@error.UnsupportedDType(_)) => ()
    _ => assert_true(false)
  }
}

///|
test "decode_rejects_length_mismatch" {
  // header declares shape (2, 3) of <f4 => 24 payload bytes, blob has none.
  let blob = v1_with_body(
    "{'descr': '<f4', 'fortran_order': False, 'shape': (2, 3)}",
  )
  match @reader.decode(blob) {
    Err(@error.DataLengthMismatch(24L, 0L)) => ()
    _ => assert_true(false)
  }
}

///|
test "decode_rejects_garbage" {
  let junk = Bytes::from_array([b'n', b'o', b't', b'n', b'p', b'y', b'!', b'!'])
  match @reader.decode(junk) {
    Err(@error.InvalidMagic) => ()
    _ => assert_true(false)
  }
}

///|
test "decode_rejects_empty" {
  let empty : Array[Byte] = []
  match @reader.decode(Bytes::from_array(empty)) {
    Err(@error.TruncatedHeader) => ()
    _ => assert_true(false)
  }
}
