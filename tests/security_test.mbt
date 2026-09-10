// Security boundary property tests (§5, innovation pack Task A1).
//
// moon-npy has no pickle interpreter, no FFI and no Python runtime: object
// arrays ('|O' — the NPY carrier for pickled Python objects) and void dtypes
// are refused at the dtype layer BEFORE any payload byte is interpreted, so
// "code embedded in a .npy file" is structurally unexecutable, not merely
// untested. edge_test.mbt pins the scalar '|O' case; this file pins the full
// guarantee as an explicit security property: every endian form of the object
// descr is refused identically, and the refusal never depends on shape or
// payload bytes.

///|
test "object_dtype_refused_all_endian_forms" {
  // All three endian markers must hit the same pre-size refusal — an attacker
  // cannot bypass the boundary by re-spelling the descr.
  for descr in ["|O", "<O", ">O"] {
    let blob = v1_with_body(
      "{'descr': '\{descr}', 'fortran_order': False, 'shape': (2,)}",
    )
    match @reader.decode(blob) {
      Err(@error.UnsupportedObjectArray) => ()
      _ => assert_true(false)
    }
  }
}

///|
test "object_dtype_refused_before_payload" {
  // Header is well-formed, so this refusal is a dtype-layer decision, not a
  // syntax accident; and it fires before payload-length reconciliation, so a
  // header-only blob (no data section, not aligned) still exercises it.
  for shape in ["()", "(1,)", "(2, 3)"] {
    let blob = v1_with_body(
      "{'descr': '|O', 'fortran_order': False, 'shape': \{shape}}",
    )
    match @reader.decode(blob) {
      Err(@error.UnsupportedObjectArray) => ()
      _ => assert_true(false)
    }
  }
}

///|
test "void_dtype_refused" {
  // '|V8' (void) carries opaque bytes and belongs to the same attack surface;
  // it is refused as UnsupportedDType via the known-unsupported-kind list.
  let blob = v1_with_body(
    "{'descr': '|V8', 'fortran_order': False, 'shape': (1,)}",
  )
  match @reader.decode(blob) {
    Err(@error.UnsupportedDType(descr)) => assert_eq(descr, "|V8")
    _ => assert_true(false)
  }
}
