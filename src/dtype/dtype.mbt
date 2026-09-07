// DType: the element type of an NPY array, parsed from the header descr.
// Plan §9.2 (DType enum + itemsize + descr code, appendix A).
//
// M1 kept the descr as a raw String (NpyHeader.descr, unchanged). This layer
// parses it into a (DType, ByteOrder) pair and enforces the object-array
// security boundary (§5). NpyArray (reader.mbt) carries the parsed DType and
// ByteOrder, while NpyHeader keeps the original descr verbatim for byte-exact
// round-trip in the M3 Writer. This is the user-approved Q1 layout ("NpyHeader
// unchanged + independent dtype layer"): it deliberately departs from the
// §9.1 concept sketch, which drew dtype/byte_order inside the header.

///|
pub(all) enum DType {
  Bool
  Int8
  Int16
  Int32
  Int64
  UInt8
  UInt16
  UInt32
  UInt64
  Float32
  Float64
} derive(Debug, Eq)

///|
// Bytes per element (NumPy itemsize, appendix A). Drives the expected payload
// length (element_count * itemsize) and the codec stride.
pub fn itemsize(dt : DType) -> Int {
  match dt {
    Bool => 1
    Int8 => 1
    UInt8 => 1
    Int16 => 2
    UInt16 => 2
    Int32 => 4
    UInt32 => 4
    Float32 => 4
    Int64 => 8
    UInt64 => 8
    Float64 => 8
  }
}

///|
// NumPy type name (e.g. "float32"), for display and diagnostics.
pub fn name(dt : DType) -> String {
  match dt {
    Bool => "bool"
    Int8 => "int8"
    Int16 => "int16"
    Int32 => "int32"
    Int64 => "int64"
    UInt8 => "uint8"
    UInt16 => "uint16"
    UInt32 => "uint32"
    UInt64 => "uint64"
    Float32 => "float32"
    Float64 => "float64"
  }
}

///|
// The endian-independent kind+size descr code (e.g. Float32 -> "f4",
// Bool -> "b1"). A full descr is endian_char + descr_code; the M3 Writer
// rebuilds it, or reuses NpyHeader.descr verbatim for byte-exact round-trip.
pub fn descr_code(dt : DType) -> String {
  match dt {
    Bool => "b1"
    Int8 => "i1"
    Int16 => "i2"
    Int32 => "i4"
    Int64 => "i8"
    UInt8 => "u1"
    UInt16 => "u2"
    UInt32 => "u4"
    UInt64 => "u8"
    Float32 => "f4"
    Float64 => "f8"
  }
}

///|
// NumPy dtype kinds that are well-formed but deliberately not decoded here
// (complex / bytes / str / void / datetime / timedelta / longdouble /
// platform-long). Recognizing them lets parse_dtype report UnsupportedDType
// (a valid dtype we skip) rather than InvalidDType (a malformed descr), per §12.
fn is_known_unsupported_kind(kind : Char) -> Bool {
  kind == 'c' ||
  kind == 'C' ||
  kind == 'S' ||
  kind == 'a' ||
  kind == 'U' ||
  kind == 'V' ||
  kind == 'M' ||
  kind == 'm' ||
  kind == 'g' ||
  kind == 'G' ||
  kind == 'e' ||
  kind == 'l' ||
  kind == 'L' ||
  kind == 'p' ||
  kind == 'P'
}

///|
// Map (kind char, itemsize) to a supported DType. All branches yield a
// Result so no early return is needed in expression position.
fn kind_size_to_dtype(
  kind : Char,
  size : Int,
  descr : String,
) -> Result[DType, @error.NpyError] {
  if kind == 'b' {
    // 'b' is bool in NumPy 2.x, always itemsize 1 ("|b1")
    if size == 1 {
      Ok(Bool)
    } else {
      Err(@error.InvalidDType(descr))
    }
  } else if kind == 'i' {
    match size {
      1 => Ok(Int8)
      2 => Ok(Int16)
      4 => Ok(Int32)
      8 => Ok(Int64)
      _ => Err(@error.UnsupportedDType(descr))
    }
  } else if kind == 'u' {
    match size {
      1 => Ok(UInt8)
      2 => Ok(UInt16)
      4 => Ok(UInt32)
      8 => Ok(UInt64)
      _ => Err(@error.UnsupportedDType(descr))
    }
  } else if kind == 'f' {
    match size {
      4 => Ok(Float32)
      8 => Ok(Float64)
      // half (2) / longdouble (12, 16): valid NumPy widths, not supported here
      _ => Err(@error.UnsupportedDType(descr))
    }
  } else if is_known_unsupported_kind(kind) {
    Err(@error.UnsupportedDType(descr))
  } else {
    // not a dtype kind character at all -> malformed descr
    Err(@error.InvalidDType(descr))
  }
}

///|
// Parse a dtype descr such as "<f4", "|b1", ">i8" into (DType, ByteOrder).
// Form: <endian><kind><size>, all ASCII. String::get_char is bounds-safe (it
// returns None past the end), so a short or malformed descr reports InvalidDType
// instead of trapping on an out-of-range index (§18 fuzz invariant).
//
// Error policy (§12 / §17):
//   - '|O' (object)                          -> UnsupportedObjectArray (§5)
//   - recognized kind, width/type unsupported -> UnsupportedDType
//   - malformed (bad length, non-digit size,
//     unknown kind char)                      -> InvalidDType
//   - invalid endian marker                   -> InvalidByteOrder
pub fn parse_dtype(
  descr : String,
) -> Result[(DType, ByteOrder), @error.NpyError] {
  let n = descr.length()
  if n < 2 {
    return Err(@error.InvalidDType(descr)) // need at least <endian><kind>
  }
  let endian = match descr.get_char(0) {
    Some(c) => c
    None => return Err(@error.InvalidDType(descr))
  }
  let order = match parse_byte_order(endian) {
    Ok(o) => o
    Err(e) => return Err(e)
  }
  let kind = match descr.get_char(1) {
    Some(c) => c
    None => return Err(@error.InvalidDType(descr))
  }
  // object arrays carry no itemsize ("|O"); refuse before size parsing (§5)
  if kind == 'O' {
    return Err(@error.UnsupportedObjectArray)
  }
  if n < 3 {
    return Err(@error.InvalidDType(descr)) // kind but no size digits
  }
  // size = descr[2..]; must be one or more ASCII digits
  let mut size = 0
  let mut i = 2
  while i < n {
    let c = match descr.get_char(i) {
      Some(c) => c
      None => return Err(@error.InvalidDType(descr))
    }
    let code = c.to_int()
    if code >= 48 && code <= 57 {
      size = size * 10 + (code - 48)
    } else {
      return Err(@error.InvalidDType(descr))
    }
    i = i + 1
  }
  match kind_size_to_dtype(kind, size, descr) {
    Ok(dt) => Ok((dt, order))
    Err(e) => Err(e)
  }
}
