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
  InvalidChunkRange(Int, Int) // (start, length) out of range / negative (S4)
  // ---- NPZ container layer (v0.3.0, read-only stored archives) ----
  NpzBadStructure(String) // malformed EOCD / central dir / local header / encrypted member
  NpzCompressedMember(String) // member uses a non-stored compression method (security boundary)
  NpzUnsafeMemberName(String) // path traversal or absolute path in member name (security boundary)
  NpzDuplicateMember(String) // duplicate member name (zip-shadowing attack surface)
  NpzZip64Unsupported // EOCD/CD fields carry zip64 sentinels; >4GB archives out of scope
  NpzMemberNotFound(String) // NpzArchive::get() lookup miss (decode_npz never raises it)
} derive(Debug)
