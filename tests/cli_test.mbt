// CLI logic tests (plan §13, §10.2). Blackbox against the public API of the
// src/cli package: parse_args, run_inspect, run_validate, human_size and
// render_error. Every rendering assertion is pinned to the exact §13 output --
// label column 14, thousands-separated byte counts, the ✓/✗ verdict markers and
// the two distinct non-zero exit codes -- so a drift in the table layout or the
// ExitCode mapping fails here rather than at the 9/21 demo. The byte fixtures
// and the v1_with_body synthesizer are shared with npy_test.mbt (same package).

// ---- parse_args: C-style argv -> (subcommand, path) (§13, AGENTS.md §6) ----

///|
test "parse_args_inspect" {
  match @cli.parse_args(["moon-npy", "inspect", "a.npy"]) {
    Ok((sub, path)) => {
      assert_eq(sub, @cli.Inspect)
      assert_eq(path, "a.npy")
    }
    Err(_) => assert_true(false)
  }
}

///|
test "parse_args_validate" {
  match @cli.parse_args(["moon-npy", "validate", "a.npy"]) {
    Ok((sub, path)) => {
      assert_eq(sub, @cli.Validate)
      assert_eq(path, "a.npy")
    }
    Err(_) => assert_true(false)
  }
}

///|
test "parse_args_missing_args_is_usage_error" {
  // argv[0] is the exe, so a well-formed call needs >= 3 entries; fewer -> Err.
  match @cli.parse_args(["moon-npy"]) {
    Err(msg) => assert_true(msg.contains("usage:"))
    Ok(_) => assert_true(false)
  }
  match @cli.parse_args(["moon-npy", "inspect"]) {
    Err(msg) => assert_true(msg.contains("usage:"))
    Ok(_) => assert_true(false)
  }
}

///|
test "parse_args_unknown_subcommand" {
  match @cli.parse_args(["moon-npy", "bogus", "a.npy"]) {
    Err(msg) => {
      assert_true(msg.contains("unknown subcommand: bogus"))
      assert_true(msg.contains("usage:"))
    }
    Ok(_) => assert_true(false)
  }
}

// ---- ExitCode / operational outcome (§13 退出码纪律) ----

///|
test "exit_code_to_int" {
  assert_eq(@cli.Success.to_int(), 0)
  assert_eq(@cli.Invalid.to_int(), 1)
  assert_eq(@cli.Operational.to_int(), 2)
}

///|
test "operational_outcome" {
  let out = @cli.operational("moon-npy: cannot open 'x.npy': no such file")
  assert_eq(out.code, @cli.Operational)
  assert_true(out.output.contains("no such file"))
}

// ---- run_inspect: the metadata table (§13), pinned row by row ----

///|
test "inspect_v1_table" {
  let out = @cli.run_inspect(
    "f4_2x3_c_le_v1.npy",
    load_fixture("f4_2x3_c_le_v1.npy"),
  )
  assert_eq(out.code, @cli.Success)
  assert_true(out.output.has_prefix("NPY Array\n"))
  // label column is 14 wide (§13): "Memory order" (12) + 2 spaces is the guide.
  assert_true(out.output.contains("Format        NPY 1.0"))
  assert_true(out.output.contains("DType         float32"))
  assert_true(out.output.contains("Byte order    little-endian"))
  assert_true(out.output.contains("Shape         [2, 3]"))
  assert_true(out.output.contains("Dimensions    2"))
  assert_true(out.output.contains("Elements      6"))
  assert_true(out.output.contains("Memory order  C"))
  assert_true(out.output.contains("Data size     24 B"))
  assert_true(out.output.contains("Status        valid"))
}

///|
test "inspect_version_labels" {
  let v2 = @cli.run_inspect("v2.npy", load_fixture("f4_2x3_c_le_v2.npy"))
  assert_eq(v2.code, @cli.Success)
  assert_true(v2.output.contains("NPY 2.0"))
  let v3 = @cli.run_inspect("v3.npy", load_fixture("f4_2x3_c_le_v3.npy"))
  assert_eq(v3.code, @cli.Success)
  assert_true(v3.output.contains("NPY 3.0"))
}

///|
test "inspect_big_endian" {
  let out = @cli.run_inspect("be.npy", load_fixture("f4_4_c_be_v1.npy"))
  assert_eq(out.code, @cli.Success)
  assert_true(out.output.contains("Byte order    big-endian"))
}

///|
test "inspect_bool_not_applicable" {
  // |b1: single-byte bool, byte order irrelevant -> "not applicable" (§9.2)
  let out = @cli.run_inspect("b.npy", load_fixture("b1_4_c_na_v1.npy"))
  assert_eq(out.code, @cli.Success)
  assert_true(out.output.contains("DType         bool"))
  assert_true(out.output.contains("Byte order    not applicable"))
  assert_true(out.output.contains("Shape         [4]"))
}

///|
test "inspect_fortran_order" {
  let out = @cli.run_inspect("f.npy", load_fixture("f4_2x3_f_le_v1.npy"))
  assert_eq(out.code, @cli.Success)
  assert_true(out.output.contains("Memory order  Fortran"))
  assert_true(out.output.contains("Byte order    little-endian"))
}

///|
test "inspect_scalar_0d" {
  // a 0-d array: shape renders "[]", Dimensions 0, Elements 1 (§13)
  let out = @cli.run_inspect("s.npy", load_fixture("f8_scalar_c_le_v1.npy"))
  assert_eq(out.code, @cli.Success)
  assert_true(out.output.contains("DType         float64"))
  assert_true(out.output.contains("Shape         []"))
  assert_true(out.output.contains("Dimensions    0"))
  assert_true(out.output.contains("Elements      1"))
  assert_true(out.output.contains("Data size     8 B"))
}

///|
test "inspect_3d_shape" {
  let out = @cli.run_inspect("3d.npy", load_fixture("i2_2x2x2_c_le_v1.npy"))
  assert_eq(out.code, @cli.Success)
  assert_true(out.output.contains("DType         int16"))
  assert_true(out.output.contains("Shape         [2, 2, 2]"))
  assert_true(out.output.contains("Dimensions    3"))
  assert_true(out.output.contains("Elements      8"))
}

// ---- run_validate: the ✓ / ✗ verdict (§13) ----

///|
test "validate_ok" {
  let out = @cli.run_validate(
    "embedding.npy",
    load_fixture("f4_2x3_c_le_v1.npy"),
  )
  assert_eq(out.code, @cli.Success)
  assert_eq(out.output, "✓ embedding.npy is a valid NPY file")
}

///|
test "validate_rejects_length_mismatch" {
  // header declares (2, 3) of <f4 => 24 payload bytes; the blob carries none.
  let blob = v1_with_body(
    "{'descr': '<f4', 'fortran_order': False, 'shape': (2, 3)}",
  )
  let out = @cli.run_validate("invalid.npy", blob)
  assert_eq(out.code, @cli.Invalid)
  assert_true(out.output.has_prefix("✗ invalid.npy\n"))
  assert_true(out.output.contains("DataLengthMismatch"))
  assert_true(out.output.contains("Expected: 24 bytes"))
  assert_true(out.output.contains("Actual:   0 bytes"))
}

///|
test "validate_rejects_garbage" {
  let junk = Bytes::from_array([b'n', b'o', b't', b'n', b'p', b'y', b'!', b'!'])
  let out = @cli.run_validate("junk.npy", junk)
  assert_eq(out.code, @cli.Invalid)
  assert_true(out.output.contains("InvalidMagic"))
}

///|
test "inspect_shares_failure_block" {
  // inspect on a malformed file renders the same ✗ block and exits Invalid (1).
  let junk = Bytes::from_array([b'n', b'o', b't', b'n', b'p', b'y', b'!', b'!'])
  let out = @cli.run_inspect("junk.npy", junk)
  assert_eq(out.code, @cli.Invalid)
  assert_true(out.output.has_prefix("✗ junk.npy\n"))
  assert_true(out.output.contains("InvalidMagic"))
}

// ---- human_size: binary-unit formatting (§13 "3.00 MiB") ----

///|
test "human_size" {
  assert_eq(@cli.human_size(0L), "0 B")
  assert_eq(@cli.human_size(24L), "24 B")
  assert_eq(@cli.human_size(152L), "152 B")
  assert_eq(@cli.human_size(1023L), "1023 B")
  assert_eq(@cli.human_size(1024L), "1.00 KiB")
  assert_eq(@cli.human_size(1536L), "1.50 KiB")
  assert_eq(@cli.human_size(1048576L), "1.00 MiB")
  assert_eq(@cli.human_size(3145728L), "3.00 MiB")
  assert_eq(@cli.human_size(1073741824L), "1.00 GiB")
}

// ---- render_error: all 12 NpyError variants (§12 error model, §13 layout) ----

///|
test "render_error_bare_variants" {
  assert_eq(@cli.render_error(@error.InvalidMagic), "InvalidMagic")
  assert_eq(@cli.render_error(@error.TruncatedHeader), "TruncatedHeader")
  assert_eq(
    @cli.render_error(@error.InvalidHeaderLength),
    "InvalidHeaderLength",
  )
  assert_eq(
    @cli.render_error(@error.InvalidHeaderSyntax),
    "InvalidHeaderSyntax",
  )
  assert_eq(@cli.render_error(@error.ShapeOverflow), "ShapeOverflow")
  assert_eq(
    @cli.render_error(@error.UnsupportedObjectArray),
    "UnsupportedObjectArray",
  )
}

///|
test "render_error_payload_variants" {
  assert_eq(
    @cli.render_error(@error.UnsupportedVersion(9, 0)),
    "UnsupportedVersion\nVersion: 9.0",
  )
  assert_eq(
    @cli.render_error(@error.MissingHeaderField("shape")),
    "MissingHeaderField\nField: shape",
  )
  assert_eq(
    @cli.render_error(@error.InvalidDType("<x9")),
    "InvalidDType\nDType descr: <x9",
  )
  assert_eq(
    @cli.render_error(@error.UnsupportedDType("<c8")),
    "UnsupportedDType\nDType descr: <c8",
  )
  // b'X' is 0x58 = 88; the marker renders as its integer byte value.
  assert_eq(
    @cli.render_error(@error.InvalidByteOrder(b'X')),
    "InvalidByteOrder\nByte order marker: 88",
  )
}

///|
test "render_error_data_length_mismatch" {
  // §13: thousands-separated counts, "Expected:" / "Actual:" column-aligned.
  assert_eq(
    @cli.render_error(@error.DataLengthMismatch(3145728L, 3145216L)),
    "DataLengthMismatch\nExpected: 3,145,728 bytes\nActual:   3,145,216 bytes",
  )
}
