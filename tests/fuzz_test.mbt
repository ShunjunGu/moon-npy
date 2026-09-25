// M5 fuzz / property tests (plan §18 safety invariant, §14 coverage). Driven by a
// deterministic splitmix PRNG (moonbitlang/core/quickcheck/splitmix) with fixed
// seeds, so any failure is exactly reproducible -- no flakiness, no wall-clock
// entropy, and the run is byte-identical across machines and CI.
//
// The NPY invariant under test is §18 totality: for ANY Bytes, decode() and
// validate() must return Ok or a structured Err(NpyError) -- never a crash, hang,
// out-of-bounds read, or runaway allocation. A trap (abort) anywhere aborts the
// whole `moon test` run, so a GREEN fuzz run is itself the no-crash proof. The
// assertions add the two structural guarantees that a bare "did not trap" cannot
// show:
//   * decode and validate AGREE (decode == validate + a total slice, §10.1);
//   * on the Ok path the dtype-matched accessor returns exactly element_count
//     items, i.e. every element read stayed in bounds (§18 / §9.1).
//
// Three input distributions, cheapest to richest:
//   1. pure random bytes             -- magic / truncation guards
//   2. valid v1 prefix, random body  -- hammers the header lexer / parser
//   3. mutated Oracle fixtures       -- near-valid blobs that reach dtype parse,
//                                       shape overflow, payload reconciliation

///|
// Length of the flat accessor matching arr's own dtype. DType is a closed
// pub(all) enum of exactly 13 decodable variants (object arrays are refused in
// parse_dtype), so this match is exhaustive and the chosen accessor always
// returns Ok -- the unwrap cannot abort here. The complex arms use
// `element_count` directly: reader.to_c64/to_c16 (Task 3) return exactly
// `element_count` items on the Ok path, so the §18 invariant is just as strong.
fn accessor_length(arr : @reader.NpyArray) -> Int {
  match arr.dtype {
    @dtype.Bool => arr.to_bool().unwrap().length()
    @dtype.Int8 => arr.to_i8().unwrap().length()
    @dtype.Int16 => arr.to_i16().unwrap().length()
    @dtype.Int32 => arr.to_i32().unwrap().length()
    @dtype.Int64 => arr.to_i64().unwrap().length()
    @dtype.UInt8 => arr.to_u8().unwrap().length()
    @dtype.UInt16 => arr.to_u16().unwrap().length()
    @dtype.UInt32 => arr.to_u32().unwrap().length()
    @dtype.UInt64 => arr.to_u64().unwrap().length()
    @dtype.Float32 => arr.to_f32().unwrap().length()
    @dtype.Float64 => arr.to_f64().unwrap().length()
    @dtype.Complex64 | @dtype.Complex128 => arr.element_count.to_int()
  }
}

///|
// Assert the §18 invariant on one blob (the two structural guarantees are in the
// file header). Marked `raise` because assert_eq / assert_true raise on failure.
fn check_total(blob : Bytes) -> Unit raise {
  let d = @reader.decode(blob)
  let v = @reader.validate(blob)
  match (d, v) {
    (Ok(arr), Ok(_)) =>
      assert_eq(accessor_length(arr), arr.element_count.to_int())
    (Err(_), Err(_)) => ()
    _ => assert_true(false) // decode and validate disagreed -- §10.1 violated
  }
}

///|
// Corrupt a valid fixture blob for distribution (3): 0 = flip a random byte,
// 1 = truncate to a random prefix, 2 = append random tail bytes, 3 = flip a byte
// inside the 12-byte prefix (magic / version / header_len). Every next_uint64
// limit is >= 1, so mutate is itself total and cannot trap; only the reader's
// handling of its output is under test.
fn mutate(rng : @splitmix.RandomState, orig : Bytes) -> Bytes {
  let n = orig.length()
  let mode = rng.next_uint64(limit=4UL).to_int()
  let keep = if mode == 1 {
    rng.next_uint64(limit=(n + 1).to_uint64()).to_int() // [0, n]
  } else {
    n
  }
  let arr : Array[Byte] = []
  for i = 0; i < keep; i = i + 1 {
    arr.push(orig[i])
  }
  if mode == 2 {
    let extra = rng.next_uint64(limit=17UL).to_int() // [0, 16]
    for j = 0; j < extra; j = j + 1 {
      arr.push(rng.next_int().to_byte())
    }
  }
  if mode == 0 || mode == 3 {
    let len = arr.length()
    if len > 0 {
      let bound = if mode == 3 && len > 12 { 12 } else { len }
      let i = rng.next_uint64(limit=bound.to_uint64()).to_int()
      arr[i] = rng.next_int().to_byte()
    }
  }
  Bytes::from_array(arr)
}

///|
test "fuzz_random_bytes_totally_decodes" {
  // Distribution (1): arbitrary bytes of length 0..128. Most die at the magic
  // check, but truncations and stray '\x93NUMPY' prefixes also arise, so
  // parse_prefix's length guards are exercised too.
  let rng = @splitmix.new(seed=0x5EEDUL)
  for k = 0; k < 2000; k = k + 1 {
    let len = rng.next_uint64(limit=129UL).to_int() // [0, 128]
    let arr : Array[Byte] = []
    for i = 0; i < len; i = i + 1 {
      arr.push(rng.next_int().to_byte())
    }
    check_total(Bytes::from_array(arr))
  }
}

///|
test "fuzz_valid_prefix_random_body" {
  // Distribution (2): a well-formed v1.0 prefix (via v1_raw) framing 0..64 RANDOM
  // body bytes, so the header lexer / parser -- not just the magic check -- is
  // hammered: unbalanced quotes, invalid UTF-8, junk bare words, and long digit
  // runs (the lexer now overflow-guards digit accumulation and returns
  // ShapeOverflow; the §18 invariant reads "no trap AND no wrap") all flow
  // through and must yield Ok or a structured NpyError.
  let rng = @splitmix.new(seed=0xC0FFEEUL)
  for k = 0; k < 2000; k = k + 1 {
    let bodylen = rng.next_uint64(limit=65UL).to_int() // [0, 64]
    let body : Array[Byte] = []
    for i = 0; i < bodylen; i = i + 1 {
      body.push(rng.next_int().to_byte())
    }
    check_total(v1_raw(body))
  }
}

///|
test "fuzz_fixture_mutations" {
  // Distribution (3): corrupt each byte-exact Oracle fixture, taken from the
  // shared oracle_fixture_names() list so the fuzz and round-trip suites can
  // never drift apart. These near-valid blobs reach deep into validate (dtype
  // parse, shape overflow, payload-length reconciliation) and occasionally
  // still decode Ok, so the typed accessors run on mutated payloads too -- the
  // highest-yield §18 probe.
  let rng = @splitmix.new(seed=0xBADC0DEUL)
  let fixtures : Array[Bytes] = []
  for name in oracle_fixture_names() {
    fixtures.push(load_fixture(name))
  }
  for k = 0; k < 3000; k = k + 1 {
    let idx = rng.next_uint64(limit=fixtures.length().to_uint64()).to_int()
    check_total(mutate(rng, fixtures[idx]))
  }
}

// NPZ fuzz uses the same fixed-seed PRNG, but exercises the ZIP framing and
// central-directory walk before a member reaches the NPY reader. A trap in
// decode_npz or get aborts moon test. On every successful decode, the public
// names and lookup APIs must describe the same members in directory order.

///|
fn check_npz_total(blob : Bytes) -> Unit raise {
  match @npz.decode_npz(blob) {
    Err(_) => ()
    Ok(archive) => {
      let names = archive.names()
      assert_eq(names.length(), archive.members.length())
      for i = 0; i < names.length(); i = i + 1 {
        assert_eq(names[i], archive.members[i].name)
        match archive.get(names[i]) {
          Ok(found) => assert_eq(found.name, names[i])
          Err(_) => assert_true(false)
        }
        for j = 0; j < i; j = j + 1 {
          assert_true(names[j] != names[i])
        }
      }
    }
  }
}

///|
// Each mode changes a real Oracle archive in a guaranteed way. In particular,
// truncation removes at least one byte, bit flipping changes exactly one byte,
// and appending adds at least one byte.
fn mutate_npz(
  rng : @splitmix.RandomState,
  original : Bytes,
  mode : Int,
) -> Bytes {
  let n = original.length()
  if mode == 0 {
    let keep = rng.next_uint64(limit=n.to_uint64()).to_int() // [0, n-1]
    let prefix : Array[Byte] = []
    for i = 0; i < keep; i = i + 1 {
      prefix.push(original[i])
    }
    return Bytes::from_array(prefix)
  }
  let bytes = original.to_array()
  if mode == 1 {
    let i = rng.next_uint64(limit=n.to_uint64()).to_int()
    bytes[i] = (bytes[i].to_int() ^ 1).to_byte()
  } else {
    let extra = 1 + rng.next_uint64(limit=16UL).to_int()
    for j = 0; j < extra; j = j + 1 {
      bytes.push(rng.next_int().to_byte())
    }
  }
  Bytes::from_array(bytes)
}

///|
test "fuzz_npz_random_bytes_totally_decodes" {
  let rng = @splitmix.new(seed=0x4E505AUL)
  for k = 0; k < 2000; k = k + 1 {
    let length = k % 1025 // guarantee every length from 0 through 1024
    let bytes : Array[Byte] = []
    for i = 0; i < length; i = i + 1 {
      bytes.push(rng.next_int().to_byte())
    }
    check_npz_total(Bytes::from_array(bytes))
  }
}

///|
test "fuzz_npz_oracle_fixture_mutations" {
  let rng = @splitmix.new(seed=0xA11CE5UL)
  let fixtures = [
    load_fixture("npz_3arr_c_le_v1.npz"),
    load_fixture("npz_customkey_c_le_v1.npz"),
    load_fixture("npz_deflated_c_le_v1.npz"),
  ]
  for fixture in fixtures {
    check_npz_total(fixture)
    for k = 0; k < 300; k = k + 1 {
      check_npz_total(mutate_npz(rng, fixture, k % 3))
    }
  }
}

///|
fn patch_npz_eocd_u16(
  original : Bytes,
  eocd : Int,
  field : Int,
  value : Int,
) -> Bytes {
  let encoded : Array[Byte] = []
  put_u16(encoded, value)
  patch_bytes(original, eocd + field, encoded)
}

///|
fn patch_npz_eocd_u32(
  original : Bytes,
  eocd : Int,
  field : Int,
  value : Int,
) -> Bytes {
  let encoded : Array[Byte] = []
  put_u32(encoded, value)
  patch_bytes(original, eocd + field, encoded)
}

///|
test "fuzz_npz_eocd_offset_size_and_count" {
  let rng = @splitmix.new(seed=0xE0CD5EEDUL)
  let fixtures = [
    load_fixture("npz_3arr_c_le_v1.npz"),
    load_fixture("npz_customkey_c_le_v1.npz"),
  ]
  for fixture in fixtures {
    // Both pinned NumPy fixtures have no ZIP comment, so EOCD is the final 22
    // bytes. Assert that layout before patching any field.
    let eocd = fixture.length() - 22
    assert_eq(fixture[eocd], b'P')
    assert_eq(fixture[eocd + 1], b'K')
    assert_eq(fixture[eocd + 2], b'\x05')
    assert_eq(fixture[eocd + 3], b'\x06')
    assert_eq(@format.read_u16_le(fixture, eocd + 20), 0)
    for field in [12, 16] { // central-directory size and offset (u32)
      let current = @format.read_u32_le(fixture, eocd + field).to_int()
      for value in [0, current - 1, current + 1, eocd + 1, 0x7FFFFFFF] {
        check_npz_total(patch_npz_eocd_u32(fixture, eocd, field, value))
      }
      check_npz_total(patch_bytes(fixture, eocd + field, ffffffff))
      for k = 0; k < 100; k = k + 1 {
        let raw = [
          rng.next_int().to_byte(),
          rng.next_int().to_byte(),
          rng.next_int().to_byte(),
          rng.next_int().to_byte(),
        ]
        check_npz_total(patch_bytes(fixture, eocd + field, raw))
      }
    }
    for field in [8, 10] { // entries on disk and total entries (u16)
      let count = @format.read_u16_le(fixture, eocd + field)
      for value in [0, count - 1, count + 1, 0xFFFE] {
        check_npz_total(patch_npz_eocd_u16(fixture, eocd, field, value))
      }
      check_npz_total(patch_bytes(fixture, eocd + field, ffff))
      for k = 0; k < 100; k = k + 1 {
        let raw = [rng.next_int().to_byte(), rng.next_int().to_byte()]
        check_npz_total(patch_bytes(fixture, eocd + field, raw))
      }
    }
  }
}
