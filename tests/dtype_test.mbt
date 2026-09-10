// M2 dtype-layer tests (plan §9.2, §12, §14/§17). Blackbox against the public
// API of the dtype package. Positive cases cover the full descr matrix the
// Oracle fixtures exercise (every supported kind x little/big/na/native); the
// negative cases pin each §12 error category to its exact NpyError variant.

///|
// Assert parse_dtype(descr) yields exactly (want_dt, want_order).
fn expect_dtype(
  descr : String,
  want_dt : @dtype.DType,
  want_order : @dtype.ByteOrder,
) -> Unit raise {
  match @dtype.parse_dtype(descr) {
    Ok((dt, order)) => {
      assert_eq(dt, want_dt)
      assert_eq(order, want_order)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "parse_dtype_bool" {
  expect_dtype("|b1", @dtype.Bool, @dtype.NotApplicable)
}

///|
test "parse_dtype_signed_ints" {
  expect_dtype("|i1", @dtype.Int8, @dtype.NotApplicable)
  expect_dtype("<i2", @dtype.Int16, @dtype.Little)
  expect_dtype(">i2", @dtype.Int16, @dtype.Big)
  expect_dtype("<i4", @dtype.Int32, @dtype.Little)
  expect_dtype(">i4", @dtype.Int32, @dtype.Big)
  expect_dtype("<i8", @dtype.Int64, @dtype.Little)
  expect_dtype(">i8", @dtype.Int64, @dtype.Big)
}

///|
test "parse_dtype_unsigned_ints" {
  expect_dtype("|u1", @dtype.UInt8, @dtype.NotApplicable)
  expect_dtype("<u2", @dtype.UInt16, @dtype.Little)
  expect_dtype(">u2", @dtype.UInt16, @dtype.Big)
  expect_dtype("<u4", @dtype.UInt32, @dtype.Little)
  expect_dtype(">u4", @dtype.UInt32, @dtype.Big)
  expect_dtype("<u8", @dtype.UInt64, @dtype.Little)
  expect_dtype(">u8", @dtype.UInt64, @dtype.Big)
}

///|
test "parse_dtype_floats" {
  expect_dtype("<f4", @dtype.Float32, @dtype.Little)
  expect_dtype(">f4", @dtype.Float32, @dtype.Big)
  expect_dtype("<f8", @dtype.Float64, @dtype.Little)
  expect_dtype(">f8", @dtype.Float64, @dtype.Big)
}

///|
test "parse_dtype_native_order" {
  // '=' (native) is accepted and read as little-endian on every backend.
  expect_dtype("=f4", @dtype.Float32, @dtype.Native)
  expect_dtype("=i8", @dtype.Int64, @dtype.Native)
}

///|
test "dtype_tables" {
  assert_eq(@dtype.itemsize(@dtype.Bool), 1)
  assert_eq(@dtype.itemsize(@dtype.Int8), 1)
  assert_eq(@dtype.itemsize(@dtype.UInt16), 2)
  assert_eq(@dtype.itemsize(@dtype.Int32), 4)
  assert_eq(@dtype.itemsize(@dtype.Float32), 4)
  assert_eq(@dtype.itemsize(@dtype.Int64), 8)
  assert_eq(@dtype.itemsize(@dtype.UInt64), 8)
  assert_eq(@dtype.itemsize(@dtype.Float64), 8)
  assert_eq(@dtype.name(@dtype.Float32), "float32")
  assert_eq(@dtype.name(@dtype.Int64), "int64")
  assert_eq(@dtype.name(@dtype.Bool), "bool")
  assert_eq(@dtype.descr_code(@dtype.Bool), "b1")
  assert_eq(@dtype.descr_code(@dtype.UInt32), "u4")
  assert_eq(@dtype.descr_code(@dtype.Float64), "f8")
}

// ---- negative categories (§12) ----

///|
test "parse_dtype_reject_object" {
  // '|O' has no itemsize; refused before size parsing (security boundary, §5).
  match @dtype.parse_dtype("|O") {
    Err(@error.UnsupportedObjectArray) => ()
    _ => assert_true(false)
  }
}

///|
test "parse_dtype_reject_unsupported" {
  // Well-formed descrs of kinds/widths we deliberately do not decode. `<c8` /
  // `<c16` left this list with S1 (they are supported now); the complex *kind*
  // stays rejected at other widths, and complex256 (`C16`) is still out of scope.
  for
    descr in [
      "<c4", "<c2", "<C16", "<S3", "<U4", "<V8", "<M8", "<m4", "<g16", "|a1", "<e2",
      "<f2", "<i3", "<u5",
    ] {
    match @dtype.parse_dtype(descr) {
      Err(@error.UnsupportedDType(_)) => ()
      _ => assert_true(false)
    }
  }
}

///|
test "parse_dtype_reject_invalid" {
  // Malformed descrs: too short, missing/non-digit size, unknown kind, bad bool.
  for descr in ["", "<", "<f", "<fx", "<x4", "|b2", "<i"] {
    match @dtype.parse_dtype(descr) {
      Err(@error.InvalidDType(_)) => ()
      _ => assert_true(false)
    }
  }
}

///|
test "parse_dtype_reject_bad_endian" {
  // A leading character that is not one of < > | = is an invalid byte order.
  for descr in ["f4", "Xf4", "1i2", "-i4"] {
    match @dtype.parse_dtype(descr) {
      Err(@error.InvalidByteOrder(_)) => ()
      _ => assert_true(false)
    }
  }
}

///|
test "parse_dtype_complex" {
  // S1: complex64 (2 x f32) and complex128 (2 x f64), both endian forms.
  expect_dtype("<c8", @dtype.Complex64, @dtype.Little)
  expect_dtype(">c8", @dtype.Complex64, @dtype.Big)
  expect_dtype("<c16", @dtype.Complex128, @dtype.Little)
  expect_dtype(">c16", @dtype.Complex128, @dtype.Big)
}

///|
test "complex_dtype_facts" {
  assert_eq(@dtype.itemsize(@dtype.Complex64), 8)
  assert_eq(@dtype.itemsize(@dtype.Complex128), 16)
  assert_eq(@dtype.name(@dtype.Complex64), "complex64")
  assert_eq(@dtype.name(@dtype.Complex128), "complex128")
  assert_eq(@dtype.descr_code(@dtype.Complex64), "c8")
  assert_eq(@dtype.descr_code(@dtype.Complex128), "c16")
}

///|
test "complex_struct_eq" {
  let z = @dtype.Complex::{ re: 1.0, im: 2.0, }
  assert_eq(z, @dtype.Complex::{ re: 1.0, im: 2.0, })
  assert_true(z != @dtype.Complex::{ re: 2.0, im: 1.0, }) // re/im are not swappable
}

///|
test "read_c64_endianness" {
  // LE: re=1.0 (00 00 80 3F), im=2.0 (00 00 00 40)
  let le = Bytes::from_array([
    b'\x00', b'\x00', b'\x80', b'\x3F', b'\x00', b'\x00', b'\x00', b'\x40',
  ])
  assert_eq(@dtype.read_c64(le, 0, @dtype.Little), @dtype.Complex::{
    re: 1.0,
    im: 2.0,
  })
  // BE: re=1.0 (3F 80 00 00), im=2.0 (40 00 00 00)
  let be = Bytes::from_array([
    b'\x3F', b'\x80', b'\x00', b'\x00', b'\x40', b'\x00', b'\x00', b'\x00',
  ])
  assert_eq(@dtype.read_c64(be, 0, @dtype.Big), @dtype.Complex::{
    re: 1.0,
    im: 2.0,
  })
}

///|
test "read_c16_endianness" {
  // LE: re=1.0 (00 00 00 00 00 00 F0 3F), im=2.0 (... 00 00 00 40)
  let le : Array[Byte] = [
    b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\xF0', b'\x3F', b'\x00',
    b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x40',
  ]
  assert_eq(@dtype.read_c16(Bytes::from_array(le), 0, @dtype.Little), @dtype.Complex::{
    re: 1.0,
    im: 2.0,
  })
  let be : Array[Byte] = [
    b'\x3F', b'\xF0', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x40',
    b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00',
  ]
  assert_eq(@dtype.read_c16(Bytes::from_array(be), 0, @dtype.Big), @dtype.Complex::{
    re: 1.0,
    im: 2.0,
  })
}

///|
test "read_c16_keeps_full_double_precision" {
  // The element struct stores Double, not Float: narrowing a complex128 half to
  // f32 would silently turn 0.1 into 0.10000000149011612. 0.1 = 3F B9 ... 9A and
  // -0.2 = BF C9 ... 9A are exact float64 patterns, so equality here proves the
  // 64-bit mantissa survived the read (S1).
  let be : Array[Byte] = [
    b'\x3F', b'\xB9', b'\x99', b'\x99', b'\x99', b'\x99', b'\x99', b'\x9A', b'\xBF',
    b'\xC9', b'\x99', b'\x99', b'\x99', b'\x99', b'\x99', b'\x9A',
  ]
  let z = @dtype.read_c16(Bytes::from_array(be), 0, @dtype.Big)
  assert_eq(z.re, 0.1)
  assert_eq(z.im, -0.2)
}
