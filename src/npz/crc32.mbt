// CRC-32 (ZIP polynomial 0xEDB88320) for the NPZ writer's member checksums.
// Self-implemented, package-private: the core packages stay free of third-
// party dependencies (N7 decision -- a mooncakes search found no core /
// moonbitlang-x routine; amor2025/moonNum has one but is out of scope for
// src/npz), and the values are verified value-by-value against zlib.crc32 --
// the exact routine Python's zipfile uses to decide whether `np.load`
// accepts an archive. The frozen vectors live in crc32_wbtest.mbt and were
// recorded by interoperability/probe_npz.py (numpy 2.3.4 / Python 3.14).
//
// The reader never verifies a checksum (the container is not trusted and no
// member byte is ever inflated -- plan §1), so nothing outside the writer
// uses this table.

///|
// CRC-32 lookup table: entry i is the reflected-polynomial remainder of the
// single byte i, built once at module load (256 entries, 0xEDB88320).
let crc32_table : Array[UInt] = {
  let table = Array::make(256, 0U)
  for i = 0; i < 256; i = i + 1 {
    let mut c = i.reinterpret_as_uint()
    for k = 0; k < 8; k = k + 1 {
      if (c & 1U) != 0U {
        c = (c >> 1) ^ 0xEDB88320U
      } else {
        c = c >> 1
      }
    }
    table[i] = c
  }
  table
}

///|
// CRC-32 (IEEE 802.3 / zlib) over `data`: init 0xFFFFFFFF, byte-at-a-time
// table lookup, final XOR 0xFFFFFFFF. Value-identical to zlib.crc32.
fn crc32(data : Bytes) -> UInt {
  let mut crc : UInt = 0xFFFFFFFFU
  for i = 0; i < data.length(); i = i + 1 {
    let idx = ((crc ^ data[i].to_uint()) & 0xFFU).reinterpret_as_int()
    crc = (crc >> 8) ^ crc32_table[idx]
  }
  crc ^ 0xFFFFFFFFU
}
