// Byte order (endianness) of an NPY dtype, from the descr's leading character.
// Plan §9.2 (ByteOrder enum). The descr endian char is one of '<' (little),
// '>' (big), '|' (not applicable, used for single-byte / bool types), '='
// (native). Native is read as little-endian: every MoonBit backend
// (native/wasm/js/wasm-gc) is little-endian. That is a documented platform
// assumption about our own runtimes, not a claim about the NPY spec (§21).

///|
pub(all) enum ByteOrder {
  Little // '<'
  Big // '>'
  NotApplicable // '|' : single-byte (or bool) types, order irrelevant
  Native // '=' : the writer's native order
} derive(Debug, Eq)

///|
// True iff multi-byte elements are stored big-endian and so must have their
// bytes reversed when assembled. Little / NotApplicable / Native all read
// little-endian. Package-private: consumed by codec.mbt (same package).
fn is_big(order : ByteOrder) -> Bool {
  match order {
    Big => true
    _ => false
  }
}

///|
// Map the descr's leading endian character to a ByteOrder. Any other character
// is not a valid byte-order marker -> InvalidByteOrder carrying the raw byte
// (§12). Package-private: only parse_dtype (dtype.mbt) consumes it.
fn parse_byte_order(c : Char) -> Result[ByteOrder, @error.NpyError] {
  if c == '<' {
    Ok(Little)
  } else if c == '>' {
    Ok(Big)
  } else if c == '|' {
    Ok(NotApplicable)
  } else if c == '=' {
    Ok(Native)
  } else {
    Err(@error.InvalidByteOrder(c.to_int().to_byte()))
  }
}

///|
// Inverse of parse_byte_order, for the M3 Writer: the descr's leading endian
// marker as a String, ready to concatenate with dtype.descr_code (appendix A).
// The Writer only ever emits '<', '>' or '|' (§4.4); it never emits '='. A
// Native order (decoded from '=') is normalized to '<' (little-endian),
// matching every MoonBit backend's byte order -- a documented platform
// assumption about our own runtimes, not a claim about the NPY spec (§21).
// Returns a String (not a Char) so the descr is rebuilt by plain concatenation.
pub fn endian_char(order : ByteOrder) -> String {
  match order {
    Little => "<"
    Big => ">"
    NotApplicable => "|"
    Native => "<" // '=' is never written; native normalizes to little-endian
  }
}
