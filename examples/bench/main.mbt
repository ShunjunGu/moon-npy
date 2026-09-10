// examples/bench — the reproducible performance bench. One run on the §29
// shape (100x768 float32, 307328 bytes on disk) measures four paths through
// the library:
//
//   [1] fs read     @fs.read_file_to_bytes of the on-disk file (warm cache)
//   [2] decode      validate() + payload slice -- no element materialisation
//   [3] decode+to_f32  decode() then to_f32(), the full-load path (76800 floats
//                   out, no pre-allocation in flat_range — this is the measured
//                   status quo — this bench measures, it does not optimise)
//   [4] row pass    100 x to_f32_chunk(k*768, 768) on a pre-decoded array --
//                   the S4 bounded-allocation path (768 floats out per row)
//
// The input file is synthesized in-process (128-byte v1.0 header + 307200-byte
// payload) so a run never depends on fixture files. The payload is all zeros:
// the byte loops under measurement (slice_payload's copy, read_f32) are
// straight-line and data-independent, so zero bytes do not flatter the numbers.
//
// Honest scope: single-machine microbenchmarks, machine-specific -- these are
// NOT cross-library comparisons and must not be quoted as such.
//
// Usage (from the repo root):
//   moon run examples/bench --target native --release
//
// Stats come from core/bench's single_bench (auto batch sizing to ~100ms per
// batch, winsorised 5% tails, microsecond unit), imported as @core_bench because
// this example's own package is named `bench`. Summary is an opaque type, so
// fields are read back through its ToJson representation -- the designed
// public exit.

///|
// NPY v1.0 bytes for the §29 shape, built from the format layout itself rather
// than from a fixture: magic \x93NUMPY + version (1,0) + little-endian uint16
// dict length + dict padded so the magic..dict-end prefix lands on the 64-byte
// boundary (10 + 118 = 128 here). Mirrors the published N2 smoke construction.
fn synthetic_npy_100x768_f32() -> Bytes {
  let mut dict = "{'descr': '<f4', 'fortran_order': False, 'shape': (100, 768), }"
  while (10 + dict.length() + 1) % 64 != 0 {
    dict += " "
  }
  dict += "\n"
  let hb = @utf8.encode(dict)
  let total = 10 + hb.length() + 100 * 768 * 4
  let arr : Array[Byte] = Array::make(total, b'\x00')
  let magic : Array[Byte] = [
    b'\x93', b'N', b'U', b'M', b'P', b'Y', b'\x01', b'\x00',
  ]
  for i = 0; i < 8; i = i + 1 {
    arr[i] = magic[i]
  }
  arr[8] = (hb.length() % 256).to_byte()
  arr[9] = (hb.length() / 256 % 256).to_byte()
  for i = 0; i < hb.length(); i = i + 1 {
    arr[10 + i] = hb[i]
  }
  Bytes::from_array(arr)
}

///|
// @fs raises IOError; bridge to Result (AGENTS.md §2) and abort with the path.
fn read_or_abort(path : String) -> Bytes {
  let res = try @fs.read_file_to_bytes(path) |> Ok catch {
    e => Err(e)
  }
  match res {
    Ok(b) => b
    Err(_) => abort("cannot read \{path} -- run from the repo root")
  }
}

///|
// Pull one numeric field out of a Summary's JSON form. JSON variants are
// matched unqualified because Json lives in builtin (in scope everywhere);
// same form as core's own json README checks.
fn num_field(j : Json, key : String) -> Double {
  let obj = match j {
    Object(m) => m
    _ => abort("summary json is not an object")
  }
  match obj.get(key) {
    Some(Number(n, ..)) => n
    _ => abort("summary json has no numeric field \{key}")
  }
}

///|
// One human-readable line plus one machine-readable JSON line per scenario.
// MB/s = bytes / mean_us (the 1e6 factors of "bytes / 1e6 / (mean_us / 1e6)"
// cancel, so the decimal-MB arithmetic is a straight division).
fn report(name : String, bytes : Int, s : @core_bench.Summary) -> Unit {
  let j = @json.to_json(s)
  let mean = num_field(j, "mean")
  let median = num_field(j, "median")
  let min_us = num_field(j, "min")
  let sd_pct = num_field(j, "std_dev_pct")
  let batch = num_field(j, "batch_size")
  let runs = num_field(j, "runs")
  println(
    "[n3] \{name} | mean \{mean}us | median \{median}us | min \{min_us}us | sd \{sd_pct}% | runs \{runs} x batch \{batch} | \{bytes.to_double() / mean} MB/s",
  )
  println("[n3-json] \{j.stringify()}")
}

///|
fn main {
  println(
    "[n3] moon-npy performance bench -- single-machine microbenchmark, no cross-library claims",
  )
  println("[n3] reproduce: moon run examples/bench --target native --release")
  let path = "_build/bench_100x768_f32.npy"
  let input = synthetic_npy_100x768_f32()
  println(
    "[n3] synthetic input: 100x768 float32 | \{input.length()} bytes (128B header + 307200B payload)",
  )
  let write_res = try @fs.write_bytes_to_file(path, input) |> Ok catch {
    e => Err(e)
  }
  match write_res {
    Ok(_) => ()
    Err(_) => abort("cannot write \{path} -- run from the repo root")
  }
  // Warm the page cache and sanity-check every measured path once before timing.
  let file_bytes = read_or_abort(path)
  if file_bytes.length() != input.length() {
    abort("file size changed between write and read")
  }
  let meta = match @reader.validate(file_bytes) {
    Ok(m) => m
    Err(_) => abort("sanity validate failed")
  }
  if meta.data_offset.to_int() != 128 ||
    meta.payload_len.to_int() != 100 * 768 * 4 {
    abort("unexpected header geometry")
  }
  let arr = match @reader.decode(file_bytes) {
    Ok(a) => a
    Err(_) => abort("sanity decode failed")
  }
  if arr.element_count.to_int() != 100 * 768 {
    abort("unexpected element_count")
  }
  let flat = match arr.to_f32() {
    Ok(v) => v
    Err(_) => abort("sanity to_f32 failed")
  }
  if flat.length() != 100 * 768 {
    abort("unexpected to_f32 length")
  }
  let row0 = match arr.to_f32_chunk(0, 768) {
    Ok(r) => r
    Err(_) => abort("sanity chunk failed")
  }
  let row99 = match arr.to_f32_chunk(99 * 768, 768) {
    Ok(r) => r
    Err(_) => abort("sanity chunk (last row) failed")
  }
  if row0.length() != 768 || row99.length() != 768 {
    abort("unexpected chunk length")
  }
  println(
    "[n3] sanity: validate/decode/to_f32/chunk OK (offset 128, elements 76800, rows 768)",
  )
  // Sinks keep consumed values live across the optimizer (the anti-DCE `keep`
  // pattern from core/bench). The printed values are meaningless sums, not
  // checks — the sanity block above is the correctness gate.
  let mut bytes_sink = 0
  let mut elements_sink : Int64 = 0
  let mut value_sink : Float = 0.0
  let s1 = @core_bench.single_bench(name="fs read", fn() {
    bytes_sink = bytes_sink + read_or_abort(path).length()
  })
  report("fs read (warm cache, 307328B)", file_bytes.length(), s1)
  let s2 = @core_bench.single_bench(name="decode", fn() {
    let a = match @reader.decode(file_bytes) {
      Ok(a) => a
      Err(_) => abort("decode failed in bench")
    }
    elements_sink = elements_sink + a.element_count
  })
  report("decode (validate + slice_payload)", file_bytes.length(), s2)
  let s3 = @core_bench.single_bench(name="decode+to_f32", fn() {
    let a = match @reader.decode(file_bytes) {
      Ok(a) => a
      Err(_) => abort("decode failed in bench")
    }
    let v = match a.to_f32() {
      Ok(v) => v
      Err(_) => abort("to_f32 failed in bench")
    }
    value_sink = value_sink + v[0]
  })
  report("decode + to_f32 (76800 floats out)", file_bytes.length(), s3)
  let s4 = @core_bench.single_bench(name="row pass", fn() {
    for k = 0; k < 100; k = k + 1 {
      let r = match arr.to_f32_chunk(k * 768, 768) {
        Ok(r) => r
        Err(_) => abort("chunk failed in bench")
      }
      value_sink = value_sink + r[0]
    }
  })
  report(
    "row pass 100 x to_f32_chunk(768) (768 floats out/row)",
    100 * 768 * 4,
    s4,
  )
  println(
    "[n3] sinks: \{bytes_sink} | \{elements_sink} | \{value_sink} (anti-DCE, not checks)",
  )
  println("[n3] done")
}
