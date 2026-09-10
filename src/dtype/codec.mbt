// Element codec: read one primitive element from raw payload bytes at a byte
// offset, honoring byte order. Plan §9.3 (manual assembly), §9.2/B2 (widths).
// No cross-backend builtin reads a u16/u32/float by byte order (AGENTS.md §3),
// so every element is assembled by hand. These are per-element readers;
// reader.mbt assembles whole flat arrays and is the layer that validates the
// payload length up front.
//
// PRECONDITION (caller-enforced): off + itemsize <= Bytes::length(data).
// decode() (reader.mbt) checks element_count * itemsize == payload length
// before any element is read, so an accessor on a decoded NpyArray never
// indexes out of bounds. Bounds are checked once at the decode boundary, not
// per element (§18: no crash / no out-of-range trap on the validated path).

///|
// Read n bytes (1..=8) at `off` as an unsigned magnitude, honoring order.
// Little / NotApplicable / Native assemble little-endian (byte i has weight
// 8*i); Big reverses (first byte is most significant). UInt64 holds up to 8
// bytes without overflow; narrower reads simply leave the high bytes zero.
fn read_uint(data : Bytes, off : Int, n : Int, order : ByteOrder) -> UInt64 {
  let big = is_big(order)
  let mut acc = 0UL
  for i = 0; i < n; i = i + 1 {
    let b = data[off + i].to_uint64()
    if big {
      acc = (acc << 8) | b
    } else {
      acc = acc | (b << (8 * i))
    }
  }
  acc
}

///|
// Assemble 4 bytes into an Int holding the raw 32-bit pattern. Int is 32-bit
// signed with wraparound (AGENTS.md §4/B2), so the pattern is exact even when
// the top bit is set. Used for i32 (pattern == signed value) and f32 (pattern
// -> Float::reinterpret_from_int).
fn read_bits32(data : Bytes, off : Int, order : ByteOrder) -> Int {
  let b0 = data[off].to_int()
  let b1 = data[off + 1].to_int()
  let b2 = data[off + 2].to_int()
  let b3 = data[off + 3].to_int()
  if is_big(order) {
    (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
  } else {
    b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
  }
}

///|
// Two's-complement sign extension of the low `bits` (8 or 16) of u -> Int64.
// Precondition: u < 2^bits (bits <= 16), so u < 2^63 and reinterpret_as_int64
// yields the same non-negative value; the result then lies in the signed range
// and .to_int() (caller) is exact.
fn sext(u : UInt64, bits : Int) -> Int64 {
  let v = u.reinterpret_as_int64()
  let sign = 1L << (bits - 1)
  if (v & sign) != 0L {
    v - (1L << bits)
  } else {
    v
  }
}

///|
// bool: NumPy stores 0x00 / 0x01; any nonzero byte is True, matching NumPy's
// truthiness and the Oracle's flat_values. One byte, so order is irrelevant.
pub fn read_bool(data : Bytes, off : Int, order : ByteOrder) -> Bool {
  read_uint(data, off, 1, order) != 0UL
}

///|
// int8 -> Int (MoonBit has no Int8; Int is 32-bit, sign-extended). §9.2/B2.
pub fn read_i8(data : Bytes, off : Int, order : ByteOrder) -> Int {
  sext(read_uint(data, off, 1, order), 8).to_int()
}

///|
// uint8 -> Int (zero-extended, 0..255).
pub fn read_u8(data : Bytes, off : Int, order : ByteOrder) -> Int {
  read_uint(data, off, 1, order).to_int()
}

///|
// int16 -> Int (sign-extended).
pub fn read_i16(data : Bytes, off : Int, order : ByteOrder) -> Int {
  sext(read_uint(data, off, 2, order), 16).to_int()
}

///|
// uint16 -> Int (zero-extended, 0..65535, fits 32-bit Int).
pub fn read_u16(data : Bytes, off : Int, order : ByteOrder) -> Int {
  read_uint(data, off, 2, order).to_int()
}

///|
// int32 -> Int: the assembled 32-bit pattern IS the signed value (Int is
// 32-bit signed). §9.2/B2.
pub fn read_i32(data : Bytes, off : Int, order : ByteOrder) -> Int {
  read_bits32(data, off, order)
}

///|
// uint32 -> Int64: 0..2^32-1 does not fit a 32-bit Int, so widen (§9.2/B2).
// The magnitude is < 2^63, so reinterpret_as_int64 preserves the value.
pub fn read_u32(data : Bytes, off : Int, order : ByteOrder) -> Int64 {
  UInt64::reinterpret_as_int64(read_uint(data, off, 4, order))
}

///|
// int64 -> Int64: reinterpret the full 64-bit pattern as signed.
pub fn read_i64(data : Bytes, off : Int, order : ByteOrder) -> Int64 {
  UInt64::reinterpret_as_int64(read_uint(data, off, 8, order))
}

///|
// uint64 -> UInt64: the raw 64-bit magnitude (MoonBit has no wider unsigned).
pub fn read_u64(data : Bytes, off : Int, order : ByteOrder) -> UInt64 {
  read_uint(data, off, 8, order)
}

///|
// float32 -> Float: assemble the 32-bit pattern, then reinterpret (AGENTS §5).
pub fn read_f32(data : Bytes, off : Int, order : ByteOrder) -> Float {
  Float::reinterpret_from_int(read_bits32(data, off, order))
}

///|
// float64 -> Double: assemble the 64-bit pattern, then reinterpret (AGENTS §5).
pub fn read_f64(data : Bytes, off : Int, order : ByteOrder) -> Double {
  UInt64::reinterpret_as_double(read_uint(data, off, 8, order))
}

///|
// Read one complex64 element: real at [off, off+4), imag at [off+4, off+8),
// each an IEEE-754 f32 in `order`, widened losslessly to Double (S1).
// PRECONDITION: off + 8 <= Bytes::length(data).
pub fn read_c64(data : Bytes, off : Int, order : ByteOrder) -> Complex {
  Complex::{
    re: read_f32(data, off, order).to_double(),
    im: read_f32(data, off + 4, order).to_double(),
  }
}

///|
// Read one complex128 element: real f64 at [off, off+8), imag at [off+8, off+16).
// Both halves are already Double, so nothing is lost (S1).
// PRECONDITION: off + 16 <= Bytes::length(data).
pub fn read_c16(data : Bytes, off : Int, order : ByteOrder) -> Complex {
  Complex::{
    re: read_f64(data, off, order),
    im: read_f64(data, off + 8, order),
  }
}
