// M5 edge-case tests (plan §4.4/§4.5 edge cases, §12 error model, §17 tests,
// §18 no-crash invariant, §14 coverage). Blackbox against the public API of the
// format / header / dtype / reader packages.
//
// Per the M5 decision these cases are SYNTHESIZED in-code (no new fixtures): the
// 26 byte-exact NumPy Oracle fixtures cover the happy-path matrix, while the
// branches below are the malformed / boundary / defensive paths a real writer
// never emits. Every negative case asserts the exact NpyError variant (§12) so a
// branch that "fails for the wrong reason" cannot pass. Positive cases cover the
// few legitimate paths the fixtures miss: '=' native order, a 0-element array,
// and negative integers that drive the codec's sign-extension branch.
//
// Synthesized blobs are deliberately NOT 64-byte aligned (data_offset = 10 +
// header_len), which the reader must tolerate by trusting only header_len
// (§7.4) -- an edge the aligned Oracle fixtures do not probe.

///|
// Build a v1.0 blob whose header body is the raw bytes `body` (no UTF-8
// encoding), with no data section. This lets a test inject bytes that are not
// valid UTF-8 -- impossible through a String body -- to exercise the lexer's
// decode_span rejection (lexer.mbt:65). header_len is written uint16 LE.
fn v1_raw(body : Array[Byte]) -> Bytes {
  let hlen = body.length()
  let arr : Array[Byte] = [
    b'\x93', b'N', b'U', b'M', b'P', b'Y', b'\x01', b'\x00',
  ]
  arr.push((hlen % 256).to_byte())
  arr.push((hlen / 256 % 256).to_byte())
  for i = 0; i < hlen; i = i + 1 {
    arr.push(body[i])
  }
  Bytes::from_array(arr)
}

///|
// Build a complete v1.0 blob: header body (UTF-8) immediately followed by the
// raw payload bytes, with no alignment padding (§7.4 tolerance). Used for the
// positive decode cases the fixtures do not cover: '=' native order, a
// 0-element array, and negative integers exercising codec sign extension.
fn v1_with_payload(body : String, payload : Array[Byte]) -> Bytes {
  let bb = @utf8.encode(body)
  let hlen = bb.length()
  let arr : Array[Byte] = [
    b'\x93', b'N', b'U', b'M', b'P', b'Y', b'\x01', b'\x00',
  ]
  arr.push((hlen % 256).to_byte())
  arr.push((hlen / 256 % 256).to_byte())
  for i = 0; i < hlen; i = i + 1 {
    arr.push(bb[i])
  }
  for i = 0; i < payload.length(); i = i + 1 {
    arr.push(payload[i])
  }
  Bytes::from_array(arr)
}

// ---- format.parse_prefix: truncation boundaries (§7.2, format.mbt:86/95) ----

///|
test "edge_prefix_truncated_before_header_start" {
  // Exactly 8 bytes: magic + version present, but the v1 header-length field
  // (offset 8..10) is absent, so total < header_start (format.mbt:86).
  let blob = Bytes::from_array([
    b'\x93', b'N', b'U', b'M', b'P', b'Y', b'\x01', b'\x00',
  ])
  match @format.parse_prefix(blob) {
    Err(@error.TruncatedHeader) => ()
    _ => assert_true(false)
  }
}

///|
test "edge_prefix_truncated_before_data" {
  // header_len claims 0xFFFF body bytes that are not present, so the file ends
  // before data_offset (format.mbt:95). Folds into TruncatedHeader, never
  // InvalidHeaderLength, and never allocates the claimed buffer (§18).
  let blob = Bytes::from_array([
    b'\x93', b'N', b'U', b'M', b'P', b'Y', b'\x01', b'\x00', b'\xFF', b'\xFF',
  ])
  match @format.parse_prefix(blob) {
    Err(@error.TruncatedHeader) => ()
    _ => assert_true(false)
  }
}

// ---- header.parse_header: prefix propagation + structural syntax (§7.3) ----

///|
test "edge_parse_header_prefix_error" {
  // A prefix failure is propagated verbatim by parse_header (parser.mbt:22):
  // here the magic's first byte is wrong.
  let bad = Bytes::from_array([
    b'X', b'N', b'U', b'M', b'P', b'Y', b'\x01', b'\x00',
  ])
  match @header.parse_header(bad) {
    Err(@error.InvalidMagic) => ()
    _ => assert_true(false)
  }
}

///|
test "edge_parse_header_structural_syntax" {
  // Each body lexes cleanly but violates the grammar at a distinct point, so
  // each reaches a different InvalidHeaderSyntax branch of parse_tokens.
  for
    body in [
      "()", // not '{' at start (parser.mbt:53)
       "{'descr' '<f4>'}", // key not followed by ':' (parser.mbt:72)
       "{'descr': 5, 'fortran_order': False, 'shape': ()}", // descr value not a string (:81)
       "{'descr': '<f4', 'fortran_order': 5, 'shape': ()}", // fortran value not a bool (:95)
       "{'descr': '<f4', 'fortran_order': False, 'shape': 5}", // shape not a tuple (:100)
       "{'descr': '<f4', 'fortran_order': False, 'shape': ('x')}", // tuple element not int/) (:118)
       "{'descr': '<f4' 'fortran_order': False, 'shape': ()}", // value not followed by ,/} (:129)
       "{'descr': '<f4',", // Eof with no closing '}' (parser.mbt:132)
       "{'descr': '<f4', 'fortran_order': False, 'shape': ()} 5", // trailing junk after '}' (:137)
    ] {
    match @header.parse_header(v1_with_body(body)) {
      Err(@error.InvalidHeaderSyntax) => ()
      _ => assert_true(false)
    }
  }
}

///|
test "edge_parse_header_missing_fields" {
  // Well-formed literals that omit one required key each; the closed-set check
  // reports exactly which field is absent (parser.mbt:140/143).
  match
    @header.parse_header(v1_with_body("{'fortran_order': False, 'shape': ()}")) {
    Err(@error.MissingHeaderField(f)) => assert_eq(f, "descr")
    _ => assert_true(false)
  }
  match @header.parse_header(v1_with_body("{'descr': '<f4', 'shape': ()}")) {
    Err(@error.MissingHeaderField(f)) => assert_eq(f, "fortran_order")
    _ => assert_true(false)
  }
}

// ---- header lexer: byte-level rejections (§7.3, lexer.mbt) ----

///|
test "edge_lexer_unterminated_string" {
  // A quoted literal whose closing quote never appears within the span
  // (lexer.mbt:123).
  match @header.parse_header(v1_with_body("{'descr': '<f4")) {
    Err(@error.InvalidHeaderSyntax) => ()
    _ => assert_true(false)
  }
}

///|
test "edge_lexer_bad_bare_word" {
  // A bare word that is neither True nor False (lexer.mbt:155); only the two
  // booleans are valid unquoted tokens in the header grammar.
  let body = "{'descr': '<f4', 'fortran_order': Nope, 'shape': ()}"
  match @header.parse_header(v1_with_body(body)) {
    Err(@error.InvalidHeaderSyntax) => ()
    _ => assert_true(false)
  }
}

///|
test "edge_lexer_invalid_utf8_in_string" {
  // A raw 0xFF byte inside a quoted span cannot decode as UTF-8, so decode_span
  // rejects it (lexer.mbt:65) and lex propagates (lexer.mbt:126). v1_raw injects
  // the byte directly -- a String body could not carry an invalid UTF-8 byte.
  let body : Array[Byte] = [b'{', b'\x27', b'\xFF', b'\x27', b'}']
  match @header.parse_header(v1_raw(body)) {
    Err(@error.InvalidHeaderSyntax) => ()
    _ => assert_true(false)
  }
}

// ---- reader.validate: error propagation + arithmetic overflow (§12, §18) ----

///|
test "edge_validate_propagates_header_error" {
  // validate() threads a parse_header failure straight through (reader.mbt:92).
  match @reader.validate(v1_with_body("{!")) {
    Err(@error.InvalidHeaderSyntax) => ()
    _ => assert_true(false)
  }
}

///|
test "edge_validate_propagates_object_array" {
  // validate() threads parse_dtype's object-array refusal through (reader.mbt:96);
  // the '|O' descr is rejected before any payload arithmetic (§5 boundary).
  let body = "{'descr': '|O', 'fortran_order': False, 'shape': ()}"
  match @reader.validate(v1_with_body(body)) {
    Err(@error.UnsupportedObjectArray) => ()
    _ => assert_true(false)
  }
}

///|
test "edge_shape_overflow_uint64" {
  // 1e10 * 1e10 = 1e20 wraps UInt64; each dim fits, the running product does
  // not, so the per-step guard fires (reader.mbt:58) and validate propagates it
  // (reader.mbt:101). Dims are 11 digits -- below the lexer's UInt64 headroom.
  let body = "{'descr': '<f4', 'fortran_order': False, 'shape': (10000000000, 10000000000)}"
  match @reader.validate(v1_with_body(body)) {
    Err(@error.ShapeOverflow) => ()
    _ => assert_true(false)
  }
}

///|
test "edge_shape_overflow_int64" {
  // 4e9 * 4e9 = 1.6e19 fits UInt64 but exceeds Int64 (element_count's type), so
  // the post-loop bound fires (reader.mbt:63) and validate propagates it (:101).
  let body = "{'descr': '<f4', 'fortran_order': False, 'shape': (4000000000, 4000000000)}"
  match @reader.validate(v1_with_body(body)) {
    Err(@error.ShapeOverflow) => ()
    _ => assert_true(false)
  }
}

///|
test "edge_byte_count_overflow" {
  // element_count (2e18) fits Int64, but count * itemsize(f8 = 8) overflows it,
  // so the byte-count guard fires before any allocation (reader.mbt:106, §18).
  let body = "{'descr': '<f8', 'fortran_order': False, 'shape': (2000000000000000000,)}"
  match @reader.validate(v1_with_body(body)) {
    Err(@error.ShapeOverflow) => ()
    _ => assert_true(false)
  }
}

// ---- positive edge paths the fixtures do not cover (§4.4/§4.5) ----

///|
test "edge_decode_empty_array" {
  // shape (0,) -> element_count 0 and an empty payload; the flat accessor
  // returns [] without indexing (a 0-element array, distinct from a 0-d scalar).
  let body = "{'descr': '<f4', 'fortran_order': False, 'shape': (0,)}"
  let a = @reader.decode(v1_with_payload(body, [])).unwrap()
  assert_eq(a.element_count, 0L)
  assert_eq(a.to_f32().unwrap().length(), 0)
}

///|
test "edge_decode_native_order" {
  // '=' native byte order decodes as little-endian on every MoonBit backend
  // (endian.mbt is_big(Native) = false); no Oracle fixture writes '=', so this
  // exercises the native decode path end to end. 1.0f = 0x3F800000, 2.0f =
  // 0x40000000, little-endian byte order.
  let payload : Array[Byte] = [
    b'\x00', b'\x00', b'\x80', b'\x3F', b'\x00', b'\x00', b'\x00', b'\x40',
  ]
  let body = "{'descr': '=f4', 'fortran_order': False, 'shape': (2,)}"
  let a = @reader.decode(v1_with_payload(body, payload)).unwrap()
  assert_eq(a.byte_order, @dtype.Native)
  assert_eq(f32_as_doubles(a), [1.0, 2.0])
}

///|
test "edge_decode_negative_ints" {
  // Negative int8 / int16 drive the codec's two's-complement sign-extension
  // branch (codec.mbt:59), which the all-nonnegative fixtures never reach. Only
  // i1/i2 go through sext (i32 uses read_bits32, i64 reinterpret_as_int64).
  // |i1: 0xFF -> -1, 0x01 -> 1.  <i2: 0xFFFF -> -1, 0x0001 -> 1.
  let i1 = @reader.decode(
    v1_with_payload("{'descr': '|i1', 'fortran_order': False, 'shape': (2,)}", [
      b'\xFF', b'\x01',
    ]),
  ).unwrap()
  assert_eq(i1.to_i8().unwrap(), [-1, 1])
  let i2 = @reader.decode(
    v1_with_payload("{'descr': '<i2', 'fortran_order': False, 'shape': (2,)}", [
      b'\xFF', b'\xFF', b'\x01', b'\x00',
    ]),
  ).unwrap()
  assert_eq(i2.to_i16().unwrap(), [-1, 1])
}

// ---- dtype.name: the full DType -> NumPy-name table (§9.2, appendix A) ----

///|
test "edge_dtype_names" {
  // Pin every arm of name(); the diagnostic/CLI label depends on this mapping
  // and only three arms were covered before M5.
  assert_eq(@dtype.name(@dtype.Bool), "bool")
  assert_eq(@dtype.name(@dtype.Int8), "int8")
  assert_eq(@dtype.name(@dtype.Int16), "int16")
  assert_eq(@dtype.name(@dtype.Int32), "int32")
  assert_eq(@dtype.name(@dtype.Int64), "int64")
  assert_eq(@dtype.name(@dtype.UInt8), "uint8")
  assert_eq(@dtype.name(@dtype.UInt16), "uint16")
  assert_eq(@dtype.name(@dtype.UInt32), "uint32")
  assert_eq(@dtype.name(@dtype.UInt64), "uint64")
  assert_eq(@dtype.name(@dtype.Float32), "float32")
  assert_eq(@dtype.name(@dtype.Float64), "float64")
}
