// White-box tests for the package-private CRC-32 implementation (N7-1).
// Truth values are zlib.crc32 outputs recorded by interoperability/
// probe_npz.py (numpy 2.3.4 / Python 3.14): "逐值核对" against the exact
// routine that decides whether Python's zipfile / np.load accepts a written
// archive.

///|
test "crc32_zlib_vectors" {
  let empty : Array[Byte] = []
  assert_eq(crc32(Bytes::from_array(empty)), 0x00000000U)
  assert_eq(crc32(@utf8.encode("a")), 0xE8B7BE43U)
  assert_eq(crc32(@utf8.encode("hello")), 0x3610A686U)
  assert_eq(crc32(@utf8.encode("123456789")), 0xCBF43926U)
  // bytes(range(256)): every byte value exactly once.
  let all : Array[Byte] = []
  for i = 0; i < 256; i = i + 1 {
    all.push((i % 256).to_byte())
  }
  assert_eq(crc32(Bytes::from_array(all)), 0x29058C73U)
  assert_eq(crc32(Bytes::from_array(Array::make(32, b'\x00'))), 0x190A55ADU)
  assert_eq(crc32(Bytes::from_array(Array::make(8, b'\xFF'))), 0x2144DF1CU)
  let magic : Array[Byte] = [
    b'\x93', b'N', b'U', b'M', b'P', b'Y', b'\x01', b'\x00',
  ]
  assert_eq(crc32(Bytes::from_array(magic)), 0x9D424C3FU)
}
