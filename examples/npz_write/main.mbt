// examples/npz_write -- the N7 emit harness for the np.savez write direction.
// It reads 1..N .npy files given on the command line, decodes each with the
// Reader, packs them into an uncompressed NPZ archive with @npz.encode_npz,
// and writes the bytes to disk so an external NumPy process
// (interoperability/verify_npz_output.py) can np.load the result and compare
// every member against its source file -- the "MoonBit Generates NPZ" hard
// acceptance of N7. It is the write counterpart of examples/roundtrip: the
// same decode -> re-serialize -> emit-to-disk shape, one container up.
//
// Member keys: an argument of the form "<key>=<in.npy>" uses the explicit key
// (split at the FIRST '='); a bare path derives the key from the file stem
// (tests/fixtures/f4_2x3_c_le_v1.npy -> "f4_2x3_c_le_v1"), mirroring how
// np.savez names keyword members. Members keep argument order.
//
// Usage:  moon run examples/npz_write --target native -- <out.npz> [<key>=]<in1.npy> [[<key>=]<in2.npy> ...]
// e.g.    moon run examples/npz_write --target native -- out.npz weights=a.npy
// Per AGENTS.md §6, @env.args()[0] is the exe path; user args start at [1].
//
// Diagnostics stay generic on purpose: the harness only proves emit-to-disk
// works, while the authoritative verdict (np.load readability, per-member
// dtype/shape/array_equal, CRC + stored-method facts) comes from the NumPy
// Oracle. Fatal paths use abort (validated in tests/), which exits non-zero
// so the driver can detect and report the failing input.

///|
// The archive key derived from a bare path: the last path component with its
// ".npy" suffix removed (tests/fixtures/foo.npy -> "foo"). Byte-level on
// purpose; every sliced range lands on a UTF-8 boundary because '/' and '\'
// are ASCII.
fn stem_of(bytes : Bytes) -> String {
  let mut start = 0
  for i = 0; i < bytes.length(); i = i + 1 {
    if bytes[i] == b'/' || bytes[i] == b'\\' {
      start = i + 1
    }
  }
  let mut end = bytes.length()
  if end - start >= 4 {
    if bytes[end - 4] == b'.' &&
      bytes[end - 3] == b'n' &&
      bytes[end - 2] == b'p' &&
      bytes[end - 1] == b'y' {
      end = end - 4
    }
  }
  @utf8.decode(bytes.view(start~, end~)) catch {
    _ => abort("file name is not UTF-8")
  }
}

///|
// Split a CLI argument into (key, path). An argument containing '=' splits at
// the FIRST '='; otherwise the key is the file stem of the path. Slicing at
// the ASCII '=' offset keeps non-ASCII keys intact.
fn key_and_path(arg : String) -> (String, String) {
  let bytes = @utf8.encode(arg)
  let mut eq = -1
  for i = 0; i < bytes.length(); i = i + 1 {
    if eq < 0 && bytes[i] == b'=' {
      eq = i
    }
  }
  if eq < 0 {
    (stem_of(bytes), arg)
  } else if eq == 0 {
    abort("empty key in argument: \{arg}")
  } else {
    let key = @utf8.decode(bytes.view(end=eq)) catch {
      _ => abort("key is not UTF-8 in argument: \{arg}")
    }
    let path = @utf8.decode(bytes.view(start=eq + 1)) catch {
      _ => abort("path is not UTF-8 in argument: \{arg}")
    }
    (key, path)
  }
}

///|
fn main {
  let args = @env.args()
  if args.length() < 3 {
    abort(
      "usage: npz_write <out.npz> [<key>=]<in1.npy> [[<key>=]<in2.npy> ...]",
    )
  }
  let out_path = args[1]
  let members : Array[@npz.NpzMember] = []
  for i = 2; i < args.length(); i = i + 1 {
    let (key, in_path) = key_and_path(args[i])
    // 1. Read the source .npy. @fs raises IOError; bridge to Result
    //    (AGENTS.md §2) and abort with the path on failure.
    let read_res = try @fs.read_file_to_bytes(in_path) |> Ok catch {
      e => Err(e)
    }
    let input : Bytes = match read_res {
      Ok(b) => b
      Err(_) => abort("cannot read \{in_path}")
    }
    // 2. Decode -> validated NpyArray (Reader, §10.1). One bad member aborts
    //    the whole archive: encode_npz operates on decoded arrays only.
    let array = match @reader.decode(input) {
      Ok(a) => a
      Err(_) => abort("decode failed for \{in_path}")
    }
    members.push(@npz.NpzMember::{ name: key, array, })
  }
  // 3. Encode -> stored, np.load-readable NPZ bytes (the N7 "clean" profile);
  //    the reader-mirrored refusals (unsafe/duplicate key, zip64 surface)
  //    surface as Err here.
  let output = match @npz.encode_npz(members) {
    Ok(b) => b
    Err(_) =>
      abort("encode_npz refused the member list (unsafe or duplicate key?)")
  }
  // 4. Write to disk so NumPy can np.load it.
  let write_res = try @fs.write_bytes_to_file(out_path, output) |> Ok catch {
    e => Err(e)
  }
  match write_res {
    Ok(_) => ()
    Err(_) => abort("cannot write \{out_path}")
  }
  // 5. One-line summary; the NumPy Oracle does the authoritative checking.
  println(
    "npz_write OK: \{out_path} | \{members.length()} members | \{output.length()} bytes",
  )
}
