// Structured error model for moon-npy (plan §12).
// Core layers (format/header/dtype/reader/writer) return Result[T, NpyError];
// failure is never expressed as a Bool or a bare String.

///|
pub(all) enum NpyError {
  InvalidMagic
  UnsupportedVersion(Int, Int)
  TruncatedHeader // file ends before header_len bytes are present
  InvalidHeaderLength // header_len inconsistent / out of range
  InvalidHeaderSyntax // restricted Python-literal parse failure
  MissingHeaderField(String) // descr / fortran_order / shape absent
  InvalidDType(String)
  UnsupportedDType(String) // structured / void etc.
  ShapeOverflow // element count or byte count exceeds bounds (§9.2 / B2)
  DataLengthMismatch(Int64, Int64) // (expected, actual)
  UnsupportedObjectArray // descr contains '|O' -> refused (security boundary, §5)
  InvalidByteOrder(Byte)
} derive(Debug)
