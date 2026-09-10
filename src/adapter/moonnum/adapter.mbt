// Read-direction adapter (S6): a decoded moon-npy NpyArray -> a moonNum NdArray,
// float32 / float64 only. The write direction (NdArray -> .npy bytes) is
// deliberately deferred to v0.3 -- see docs/s6-api-card.md §3.5 for the contract
// this file implements, §3.6 for why big-endian is refused up front, and §3.7 for
// the fact that moonNum has its own npy reader (this adapter hands over arrays
// moon-npy parsed, it does not replace anything).
//
// No element is decoded here: moonNum's `from_buffer` takes the payload bytes
// plus a shape and a storage order, which is exactly the model NpyArray already
// carries (`data` = payload sliced at data_offset, `header.shape`,
// `header.fortran_order`). That is why the conversion is total and cheap instead
// of a reshape loop.

///|
// Largest value an `Int` (32-bit, AGENTS.md §4) can hold, as the UInt64 the
// header shape dims are stored in. Used to refuse, never truncate, a dimension.
let int_max_as_uint : UInt64 = 0x7FFFFFFFUL

///|
// A conversion-layer failure. Deliberately NOT a new @error.NpyError variant:
// adding one to that `pub(all) enum` breaks the exhaustive match in
// src/cli/render_error (S4 hit exactly this, see CHANGELOG), and none of these
// cases is a complaint about the .npy file -- the bytes are already a valid NPY
// array, the adapter simply cannot express them in moonNum's model.
pub(all) enum AdapterError {
  UnsupportedDType(String) // descr is not a float32 / float64 code
  BigEndianNotSupported(String) // moonNum's buffer model is little-endian only
  ShapeDimensionTooLarge(UInt64) // a shape dim does not fit an Int
} derive(Debug, Eq)

///|
// One-line rendering for callers that surface the failure (CLI, README, tests).
pub fn AdapterError::message(self : AdapterError) -> String {
  match self {
    UnsupportedDType(descr) =>
      "moonNum adapter supports float32/float64 only, got descr '\{descr}'"
    BigEndianNotSupported(descr) =>
      "moonNum stores elements little-endian only, refusing big-endian descr '\{descr}'"
    ShapeDimensionTooLarge(dim) =>
      "shape dimension \{dim} exceeds the Int range, refusing to truncate"
  }
}

///|
// header.shape (Array[UInt64]) -> the Array[Int] moonNum wants. Every dimension
// is checked against Int's range before conversion, so a hostile header reports
// ShapeDimensionTooLarge instead of silently wrapping (§12 discipline).
// A 0-d scalar has an empty shape and maps to an empty array, which moonNum
// documents as its 0-D representation (card §3.5 step 2) -- same semantics both
// sides, so no special case.
fn shape_as_ints(shape : Array[UInt64]) -> Result[Array[Int], AdapterError] {
  let out : Array[Int] = []
  for i = 0; i < shape.length(); i = i + 1 {
    let dim = shape[i]
    if dim > int_max_as_uint {
      return Err(ShapeDimensionTooLarge(dim))
    }
    out.push(dim.to_int())
  }
  Ok(out)
}

///|
// Shared body of the two public conversions: assert the caller asked for the
// dtype the array actually holds, refuse what moonNum cannot represent, then
// hand the payload over. `want` / `nn_dtype` stay separate arguments rather
// than one branch on arr.dtype so each public entry point states its own
// precondition (the same shape as the reader's typed accessors).
fn convert(
  arr : @reader.NpyArray,
  want : @dtype.DType,
  nn_dtype : @dtypes.Dtype,
) -> Result[@core.NdArray, AdapterError] {
  if arr.dtype != want {
    return Err(UnsupportedDType(arr.header.descr))
  }
  match arr.byte_order {
    @dtype.Big => Err(BigEndianNotSupported(arr.header.descr))
    // Little and Native are little-endian on every target this repo tests.
    // NotApplicable cannot occur for a multi-byte dtype; where it does appear
    // (single-byte types) src/dtype/endian.mbt already reads it little-endian,
    // and the adapter follows that same rule rather than inventing a third one.
    @dtype.Little | @dtype.Native | @dtype.NotApplicable => {
      let shape = match shape_as_ints(arr.header.shape) {
        Err(e) => return Err(e)
        Ok(s) => s
      }
      let order : @core.Order = if arr.header.fortran_order {
        @core.Order::F
      } else {
        @core.Order::C
      }
      // Bytes::to_array is the single element-wise copy in the whole pipeline;
      // from_buffer itself shares the buffer and only computes byte strides.
      Ok(
        @core.NdArray::from_buffer(arr.data.to_array(), nn_dtype, shape, order),
      )
    }
  }
}

///|
// float32 array -> moonNum NdArray (Dtype::Float32), shape and storage order
// preserved. moonNum's `get_f32` reads an element back as Double (already
// widened), so consumers do not have to widen again.
pub fn to_moonnum_f32(
  arr : @reader.NpyArray,
) -> Result[@core.NdArray, AdapterError] {
  convert(arr, @dtype.Float32, @dtypes.Dtype::Float32)
}

///|
// float64 array -> moonNum NdArray (Dtype::Float64), same contract as
// to_moonnum_f32.
pub fn to_moonnum_f64(
  arr : @reader.NpyArray,
) -> Result[@core.NdArray, AdapterError] {
  convert(arr, @dtype.Float64, @dtypes.Dtype::Float64)
}
