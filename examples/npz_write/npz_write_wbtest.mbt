// White-box tests for the npz_write harness helpers (key derivation and
// [key=]path argument parsing). The end-to-end path -- real files in, a real
// .npz out, np.load verdict -- is pinned by examples/npz_write +
// interoperability/verify_npz_output.py in CI (§19); these tests lock the
// pure string logic the harness derives member keys from, including the
// UTF-8 key and first-'=' split rules the CI step relies on.

///|
test "npz_write_stem_of_derives_keys" {
  // Full fixture-style path: last component, ".npy" stripped.
  assert_eq(
    stem_of(@utf8.encode("tests/fixtures/f4_2x3_c_le_v1.npy")),
    "f4_2x3_c_le_v1",
  )
  // Backslash separators are component boundaries too (Windows paths).
  assert_eq(stem_of(@utf8.encode("src\\data\\x.npy")), "x")
  // No suffix / no separator: unchanged.
  assert_eq(stem_of(@utf8.encode("no_ext")), "no_ext")
  // Only the TRAILING ".npy" is stripped; interior dots are kept.
  assert_eq(stem_of(@utf8.encode("a.b.npy")), "a.b")
  // A ".npy" suffix shorter than the whole name is still stripped to empty
  // (encode_npz's refusal surface owns the emptiness question, not stem_of).
  assert_eq(stem_of(@utf8.encode(".npy")), "")
}

///|
test "npz_write_key_and_path_argument_forms" {
  // Bare path: key = file stem, path = the argument itself.
  let (bare_key, bare_path) = key_and_path("tests/fixtures/i4_4_c_le_v1.npy")
  assert_eq(bare_key, "i4_4_c_le_v1")
  assert_eq(bare_path, "tests/fixtures/i4_4_c_le_v1.npy")
  // Explicit ASCII key.
  let (exp_key, exp_path) = key_and_path("weights=arr.npy")
  assert_eq(exp_key, "weights")
  assert_eq(exp_path, "arr.npy")
  // Explicit UTF-8 key (the CI utf8.npz step's exact input): the ASCII '='
  // split must not corrupt the multi-byte key.
  let (u8_key, u8_path) = key_and_path(
    "数据=tests/fixtures/f4_2x3_c_le_v1.npy",
  )
  assert_eq(u8_key, "数据")
  assert_eq(u8_path, "tests/fixtures/f4_2x3_c_le_v1.npy")
  // Splits at the FIRST '='; a later '=' belongs to the path.
  let (first_key, first_path) = key_and_path("a=b=c.npy")
  assert_eq(first_key, "a")
  assert_eq(first_path, "b=c.npy")
}
