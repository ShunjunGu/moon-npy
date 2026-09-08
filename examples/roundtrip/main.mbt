// examples/roundtrip — the M4 emit harness for §16 (MoonBit → NumPy +
// byte-level round-trip) and the §29 Demo. It reads a .npy, decodes it with the
// Reader, re-encodes it with the Writer, and writes the bytes back to disk so an
// external NumPy process (interoperability/verify_moonbit_output.py) can load the
// result and byte-compare it against the Oracle fixture. This is the "MoonBit
// Generates NPY" step of the §19 CI pipeline.
//
// Scope note: the harness deliberately re-serializes a decoded array
// (decode -> encode -> write), which is exactly the path §29 Demo exercises
// ("MoonBit 读取并重新输出"). It does NOT construct arrays from typed data --
// writer.mbt reserves that for future from-typed-array constructors.
//
// Usage:  moon run examples/roundtrip --target native -- <in.npy> <out.npy>
// Per AGENTS.md §6, @env.args()[0] is the exe path; user args start at [1].
//
// Diagnostics stay generic on purpose: the harness only proves emit-to-disk
// works, while the authoritative value/shape/dtype/byte-exact verdict comes from
// the NumPy Oracle. Fatal paths use abort (validated in tests/), which exits
// non-zero so the driver can detect and report the failing fixture.

///|
fn main {
  let args = @env.args()
  if args.length() < 3 {
    abort("usage: roundtrip <in.npy> <out.npy>")
  }
  let in_path = args[1]
  let out_path = args[2]
  // 1. Read the Oracle fixture bytes. @fs raises IOError; bridge to Result
  //    (AGENTS.md §2) and abort with the path on failure.
  let read_res = try @fs.read_file_to_bytes(in_path) |> Ok catch {
    e => Err(e)
  }
  let input : Bytes = match read_res {
    Ok(b) => b
    Err(_) => abort("cannot read \{in_path}")
  }
  // 2. Decode -> validated NpyArray (Reader, §10.1).
  let decoded = match @reader.decode(input) {
    Ok(a) => a
    Err(_) => abort("decode failed for \{in_path}")
  }
  // 3. Encode -> NPY bytes, byte-identical to np.save for this array (Writer,
  //    §7.4 64-byte alignment).
  let output = match @writer.encode(decoded) {
    Ok(b) => b
    Err(_) => abort("encode failed for \{in_path}")
  }
  // 4. Write to disk so NumPy can load it.
  let write_res = try @fs.write_bytes_to_file(out_path, output) |> Ok catch {
    e => Err(e)
  }
  match write_res {
    Ok(_) => ()
    Err(_) => abort("cannot write \{out_path}")
  }
  // 5. One-line summary (element_count is Int64, output.length() is Int; both
  //    interpolate directly).
  println(
    "roundtrip OK: \{in_path} -> \{out_path} | \{output.length()} bytes | \{decoded.element_count} elements",
  )
}
