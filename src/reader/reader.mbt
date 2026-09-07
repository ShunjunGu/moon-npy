// Reader: turn raw NPY bytes into a validated NpyArray, plus typed flat
// (storage-order) accessors. Plan §9.1 concept model, §10.1 validate/decode
// signatures, §12 Int64 length discipline, §18 fuzz invariant (any Bytes ->
// Ok or a structured NpyError; never a crash / out-of-range trap).
//
// Q1 layout note: NpyArray carries the parsed DType + ByteOrder alongside the
// *unchanged* NpyHeader (whose `descr` stays verbatim for byte-exact M3
// round-trip). NpyHeader is a `pub struct` in the header package, so this
// package can read its fields and store the value parse_header returns, but
// must not construct it -- decode threads that value straight through.

///|
let int64_max : Int64 = 0x7FFFFFFFFFFFFFFFL

///|
let uint64_max : UInt64 = 0xFFFFFFFFFFFFFFFFUL

///|
let int64_max_as_uint : UInt64 = 0x7FFFFFFFFFFFFFFFUL

///|
// Validated NPY metadata without the element payload. validate() produces this
// after checking magic/version/header/dtype and reconciling the payload length;
// decode() reuses the same checks then slices the payload into an NpyArray.
pub struct NpyMeta {
  version : @format.NpyVersion
  header : @header.NpyHeader // stored value from parse_header (descr verbatim)
  dtype : @dtype.DType
  byte_order : @dtype.ByteOrder
  element_count : Int64 // product(shape), overflow-checked (§12)
  data_offset : Int64 // byte offset where the payload begins
  payload_len : Int64 // bytes actually present after data_offset
}

///|
// A decoded NPY array: validated metadata plus the raw payload bytes. Element
// decoding is lazy (accessors below, §9.1). `data` holds only the payload
// (already sliced at data_offset), so element i lives at byte i * itemsize.
pub struct NpyArray {
  version : @format.NpyVersion
  header : @header.NpyHeader
  dtype : @dtype.DType
  byte_order : @dtype.ByteOrder
  element_count : Int64
  data : Bytes
}

///|
// Multiply the shape dims into an element count. The running product is held in
// UInt64 and guarded against wraparound at each step, then checked to fit Int64
// (element_count's type). Any overflow reports ShapeOverflow (§12 / B2) rather
// than silently truncating. Empty shape -> 1 (a 0-d scalar).
fn shape_element_count(shape : Array[UInt64]) -> Result[Int64, @error.NpyError] {
  let mut count = 1UL
  for i = 0; i < shape.length(); i = i + 1 {
    let dim = shape[i]
    if dim != 0UL && count > uint64_max / dim {
      return Err(@error.ShapeOverflow)
    }
    count = count * dim
  }
  if count > int64_max_as_uint {
    Err(@error.ShapeOverflow)
  } else {
    Ok(UInt64::reinterpret_as_int64(count))
  }
}

///|
// Copy `len` bytes of `data` starting at `base` into a fresh Bytes. Bytes is
// immutable with no zero-copy sub-slice returning Bytes (only BytesView), so
// the payload is copied once here; element decoding stays lazy afterwards.
fn slice_payload(data : Bytes, base : Int, len : Int) -> Bytes {
  let arr = Array::make(len, b'\x00')
  for i = 0; i < len; i = i + 1 {
    arr[i] = data[base + i]
  }
  Bytes::from_array(arr)
}

///|
// Validate an NPY byte buffer without decoding elements: magic, version, header
// dictionary, dtype descr (incl. the object-array refusal), shape overflow, and
// the payload-length reconciliation. On success returns NpyMeta (§10.1/§12).
pub fn validate(data : Bytes) -> Result[NpyMeta, @error.NpyError] {
  let prefix = match @format.parse_prefix(data) {
    Ok(p) => p
    Err(e) => return Err(e)
  }
  let header = match @header.parse_header(data) {
    Ok(h) => h
    Err(e) => return Err(e)
  }
  let parsed = match @dtype.parse_dtype(header.descr) {
    Ok(x) => x
    Err(e) => return Err(e)
  }
  let (dtype, byte_order) = parsed
  let element_count = match shape_element_count(header.shape) {
    Ok(c) => c
    Err(e) => return Err(e)
  }
  let itemsize = @dtype.itemsize(dtype).to_int64()
  // itemsize >= 1, so this division is safe; guard the count*itemsize product.
  if element_count > int64_max / itemsize {
    return Err(@error.ShapeOverflow)
  }
  let expected = element_count * itemsize
  // parse_prefix already ensured total >= data_offset, so payload_len >= 0.
  let payload_len = data.length().to_int64() - prefix.data_offset
  if payload_len != expected {
    return Err(@error.DataLengthMismatch(expected, payload_len))
  }
  Ok(NpyMeta::{
    version: prefix.version,
    header,
    dtype,
    byte_order,
    element_count,
    data_offset: prefix.data_offset,
    payload_len,
  })
}

///|
// Decode an NPY byte buffer into an NpyArray: run validate(), then slice the raw
// payload out for lazy element access. data_offset / payload_len are bounded by
// data.length() (an Int), so their .to_int() conversions are exact (§12/B2).
pub fn decode(data : Bytes) -> Result[NpyArray, @error.NpyError] {
  let meta = match validate(data) {
    Ok(m) => m
    Err(e) => return Err(e)
  }
  let payload = slice_payload(
    data,
    meta.data_offset.to_int(),
    meta.payload_len.to_int(),
  )
  Ok(NpyArray::{
    version: meta.version,
    header: meta.header,
    dtype: meta.dtype,
    byte_order: meta.byte_order,
    element_count: meta.element_count,
    data: payload,
  })
}

///|
// Shared accessor body: refuse unless the array's dtype is `want`, then decode
// every element in storage order into a fresh Array[T]. Element i sits at byte
// i * itemsize of the (already length-validated) payload, so reads never go out
// of bounds (§18). The result is flat; shape + fortran_order stay as metadata
// for the consumer to reshape (Q2).
fn[T] flat(
  arr : NpyArray,
  want : @dtype.DType,
  read : (Bytes, Int, @dtype.ByteOrder) -> T,
) -> Result[Array[T], @error.NpyError] {
  if arr.dtype != want {
    return Err(@error.UnsupportedDType(arr.header.descr))
  }
  let isz = @dtype.itemsize(arr.dtype)
  let n = arr.element_count.to_int()
  let out : Array[T] = []
  for i = 0; i < n; i = i + 1 {
    out.push(read(arr.data, i * isz, arr.byte_order))
  }
  Ok(out)
}

///|
// bool -> Array[Bool] (NumPy stores 0x00/0x01; any nonzero byte is true).
pub fn NpyArray::to_bool(
  self : NpyArray,
) -> Result[Array[Bool], @error.NpyError] {
  flat(self, @dtype.Bool, @dtype.read_bool)
}

///|
// int8 -> Array[Int] (MoonBit has no Int8; Int is 32-bit, sign-extended).
pub fn NpyArray::to_i8(self : NpyArray) -> Result[Array[Int], @error.NpyError] {
  flat(self, @dtype.Int8, @dtype.read_i8)
}

///|
// int16 -> Array[Int] (sign-extended).
pub fn NpyArray::to_i16(self : NpyArray) -> Result[Array[Int], @error.NpyError] {
  flat(self, @dtype.Int16, @dtype.read_i16)
}

///|
// int32 -> Array[Int] (the 32-bit pattern is the signed value).
pub fn NpyArray::to_i32(self : NpyArray) -> Result[Array[Int], @error.NpyError] {
  flat(self, @dtype.Int32, @dtype.read_i32)
}

///|
// int64 -> Array[Int64].
pub fn NpyArray::to_i64(
  self : NpyArray,
) -> Result[Array[Int64], @error.NpyError] {
  flat(self, @dtype.Int64, @dtype.read_i64)
}

///|
// uint8 -> Array[Int] (zero-extended, 0..255).
pub fn NpyArray::to_u8(self : NpyArray) -> Result[Array[Int], @error.NpyError] {
  flat(self, @dtype.UInt8, @dtype.read_u8)
}

///|
// uint16 -> Array[Int] (zero-extended, 0..65535).
pub fn NpyArray::to_u16(self : NpyArray) -> Result[Array[Int], @error.NpyError] {
  flat(self, @dtype.UInt16, @dtype.read_u16)
}

///|
// uint32 -> Array[Int64] (0..2^32-1 does not fit a 32-bit Int; widened).
pub fn NpyArray::to_u32(
  self : NpyArray,
) -> Result[Array[Int64], @error.NpyError] {
  flat(self, @dtype.UInt32, @dtype.read_u32)
}

///|
// uint64 -> Array[UInt64].
pub fn NpyArray::to_u64(
  self : NpyArray,
) -> Result[Array[UInt64], @error.NpyError] {
  flat(self, @dtype.UInt64, @dtype.read_u64)
}

///|
// float32 -> Array[Float].
pub fn NpyArray::to_f32(
  self : NpyArray,
) -> Result[Array[Float], @error.NpyError] {
  flat(self, @dtype.Float32, @dtype.read_f32)
}

///|
// float64 -> Array[Double].
pub fn NpyArray::to_f64(
  self : NpyArray,
) -> Result[Array[Double], @error.NpyError] {
  flat(self, @dtype.Float64, @dtype.read_f64)
}
