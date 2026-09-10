// M5 fuzz / property tests (plan §18 safety invariant, §14 coverage). Driven by a
// deterministic splitmix PRNG (moonbitlang/core/quickcheck/splitmix) with fixed
// seeds, so any failure is exactly reproducible -- no flakiness, no wall-clock
// entropy, and the run is byte-identical across machines and CI.
//
// The single invariant under test is §18 totality: for ANY Bytes, decode() and
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
// pub(all) enum of exactly 11 decodable variants (object arrays are refused in
// parse_dtype), so this match is exhaustive and the chosen accessor always
// returns Ok -- the unwrap cannot abort here.
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
  // runs (lexer.mbt:135 wraps rather than traps, per the §21 UInt64 probe) all
  // flow through and must yield Ok or a structured NpyError.
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
