// Writer: serialize a validated NpyArray back into NPY bytes that are
// byte-identical to what NumPy's np.save produces. Plan §4.2 (byte-exact),
// §10.1 (locked encode signature), §16 (byte-level round-trip), §7.4 (64-byte
// alignment), appendix A (descr codes + header dict form).
//
// Scope (M3): encode only re-serializes arrays that came from reader.decode.
// Two consequences shape the design:
//   * NpyArray.data already holds the raw payload bytes in file byte order
//     (sliced at data_offset, its length validated by reader.validate), so
//     encode copies them verbatim -- no per-element encoding is needed here.
//   * The header dict is REBUILT from dtype / byte_order / shape /
//     fortran_order in NumPy's exact textual form, and the padding is
//     recomputed to NumPy's minimal 64-byte alignment (§7.4), regardless of any
//     extra padding the source file carried. That is what makes decode->encode
//     byte-exact for every np.save fixture (Oracle: all 26 land at
//     data_offset == 128).
//
// descr policy (§4.4): the Writer only ever emits '<', '>' or '|'; it never
// emits '='. A ByteOrder::Native (decoded from '=') normalizes to '<', handled
// by dtype.endian_char.

///|
// NumPy's array-data alignment: the payload's byte offset (magic + version +
// header-length field + header body) is always a multiple of ARRAY_ALIGN.
// Verified against all 26 Oracle fixtures (data_offset == 128).
let array_align : Int = 64

///|
// Python's bool literal spelling, exactly as NumPy writes it in the header dict
// (capitalized), so the rebuilt dict matches np.save byte-for-byte.
fn py_bool(b : Bool) -> String {
  if b {
    "True"
  } else {
    "False"
  }
}

///|
// NumPy's shape tuple text: "()" for a 0-d scalar, "(n,)" for 1-d (Python keeps
// the trailing comma in a 1-tuple), and "(a, b, ...)" for n-d (comma + space, no
// trailing comma). Verified byte-exact against the Oracle fixtures: f8_scalar
// -> "()", b1_4 -> "(4,)", f4_2x3 -> "(2, 3)", i2_2x2x2 -> "(2, 2, 2)".
fn shape_tuple(shape : Array[UInt64]) -> String {
  let n = shape.length()
  if n == 0 {
    "()"
  } else if n == 1 {
    "(\{shape[0].to_string()},)"
  } else {
    let mut s = "("
    for i = 0; i < n; i = i + 1 {
      if i > 0 {
        s = "\{s}, "
      }
      s = "\{s}\{shape[i].to_string()}"
    }
    "\{s})"
  }
}

///|
// Inverse of format.version_of for the Writer: NpyVersion -> (major, minor).
// The minor is always 0 for the versions NumPy writes (1.0 / 2.0 / 3.0).
fn version_major_minor(v : @format.NpyVersion) -> (Int, Int) {
  match v {
    @format.V1_0 => (1, 0)
    @format.V2_0 => (2, 0)
    @format.V3_0 => (3, 0)
  }
}

///|
// Serialize an NpyArray into NPY bytes: magic, version, header-length field,
// the header dict + minimal 64-byte-aligned space padding + '\n', then the raw
// payload verbatim. The output is byte-identical to np.save for the same array.
//
// Precondition: `array` came from reader.decode (or reader.validate + slicing),
// so array.data.length() == element_count * itemsize and array.version is
// V1_0 / V2_0 / V3_0. encode never fails on such input; the Result error slot
// mirrors decode's contract (§10.1) and reserves room for future from-typed-
// array constructors that must validate element/shape consistency.
pub fn encode(array : @reader.NpyArray) -> Result[Bytes, @error.NpyError] {
  // 1. Rebuild the descr: endian marker + kind/size code (appendix A).
  let descr = "\{@dtype.endian_char(array.byte_order)}\{@dtype.descr_code(array.dtype)}"
  // 2. Rebuild the header dict in NumPy's exact textual form (§7.3): fixed key
  //    order descr -> fortran_order -> shape, single quotes, ': ' and ', '
  //    separators, Python True/False, and a trailing ', ' before '}'.
  let fortran = py_bool(array.header.fortran_order)
  let shape = shape_tuple(array.header.shape)
  let dict = "{'descr': '\{descr}', 'fortran_order': \{fortran}, 'shape': \{shape}, }"
  let dict_bytes = @utf8.encode(dict)
  let dict_len = dict_bytes.length()
  // 3. Version decides the preamble (magic 6 + version 2 + header-len field)
  //    and the header-length field width: v1 -> u16 (2), v2/v3 -> u32 (4).
  let is_v1 = array.version == @format.V1_0
  let preamble = if is_v1 { 10 } else { 12 }
  // 4. Minimal space padding so preamble + dict + pad + '\n' is ARRAY_ALIGN-
  //    aligned (§7.4). header_len is the body length after the length field.
  let pad = (array_align - (preamble + dict_len + 1) % array_align) %
    array_align
  let header_len = dict_len + pad + 1
  // 5. Emit the file bytes into a growable buffer, then freeze to Bytes.
  let out : Array[Byte] = []
  // magic prefix \x93NUMPY
  out.push(b'\x93')
  out.push(b'N')
  out.push(b'U')
  out.push(b'M')
  out.push(b'P')
  out.push(b'Y')
  // version: major, minor
  let mm = version_major_minor(array.version)
  out.push(mm.0.to_byte())
  out.push(mm.1.to_byte())
  // header-length field, little-endian (§9.3 manual assembly): uint16 (2 bytes)
  // for v1, uint32 (4 bytes) for v2/v3. A decoded v1 array's header_len already
  // fit u16 (parse_prefix read it as u16) and our minimal re-padding is never
  // larger, so no v1 overflow is reachable here.
  if is_v1 {
    out.push((header_len % 256).to_byte())
    out.push((header_len / 256 % 256).to_byte())
  } else {
    out.push((header_len % 256).to_byte())
    out.push((header_len / 256 % 256).to_byte())
    out.push((header_len / 65536 % 256).to_byte())
    out.push((header_len / 16777216 % 256).to_byte())
  }
  // header dict body (ASCII; utf8.encode gave one byte per character)
  for i = 0; i < dict_len; i = i + 1 {
    out.push(dict_bytes[i])
  }
  // padding spaces (0x20) then the terminating newline (0x0a)
  for j = 0; j < pad; j = j + 1 {
    out.push(b' ')
  }
  out.push(b'\n')
  // raw payload, copied verbatim (already in file byte order)
  let data = array.data
  for i = 0; i < data.length(); i = i + 1 {
    out.push(data[i])
  }
  Ok(Bytes::from_array(out))
}
