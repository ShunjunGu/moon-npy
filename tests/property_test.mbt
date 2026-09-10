// Round-trip property (innovation pack Task B1): for every byte-exact Oracle
// fixture, decode -> encode reproduces the original bytes, and re-decoding the
// re-encoded bytes yields an array with identical dtype, shape and element
// count. This pins the writer's byte-exact guarantee inside `moon test` --
// Python-free, complementing (not replacing) the Python roundtrip harness
// interoperability/roundtrip.py which guards the full NumPy-side verify.

///|
fn bytes_equal(a : Bytes, b : Bytes) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for i = 0; i < a.length(); i = i + 1 {
    if a[i] != b[i] {
      return false
    }
  }
  true
}

///|
test "decode_encode_roundtrip_is_byte_exact" {
  for name in oracle_fixture_names() {
    let data = load_fixture(name)
    let arr = @reader.decode(data).unwrap()
    let out = @writer.encode(arr).unwrap()
    assert_true(bytes_equal(out, data)) // byte-exact: np.save compat
    let arr2 = @reader.decode(out).unwrap()
    assert_eq(arr2.dtype, arr.dtype)
    assert_eq(arr2.header.shape, arr.header.shape)
    assert_eq(arr2.element_count, arr.element_count)
  }
}
