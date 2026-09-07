// NpyHeader: the parsed NPY header dictionary (plan §9.1, M1 scope).
//
// M1 keeps `descr` as the raw dtype-descriptor String (e.g. "<f4"); the M2
// dtype layer parses it into a DType + ByteOrder. `shape` holds one UInt64 per
// dimension (§9.2: dims are UInt64, matching NumPy's npy_intp), empty for a 0-d
// scalar. `fortran_order` records the memory-layout flag; in M1 it is parsed and
// validated, while the Reader still hands back raw payload bytes (§9.1).

///|
pub struct NpyHeader {
  descr : String
  shape : Array[UInt64]
  fortran_order : Bool
}
