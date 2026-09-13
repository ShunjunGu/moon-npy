///|
// Browser demo bridge for the CLI inspect pipeline. The JS side talks to the
// wasm-gc module through a zero-dependency Int protocol: upload the .npy
// image as little-endian 32-bit words, then pull the report back one UTF-16
// code unit at a time. Declared as a foreign_library package (see moon.pkg)
// and exported with #export_name, so the module instantiates without any
// imported host functions.

///|
let demo_input : Ref[Array[Byte]] = Ref([])

///|
let demo_total : Ref[Int] = Ref(0)

///|
let demo_cursor : Ref[Int] = Ref(0)

///|
let demo_output : Ref[Array[UInt16]] = Ref([])

///|
// Reset the upload buffer. `total` is the exact byte count of the .npy image;
// the buffer is padded to a whole number of 32-bit words for the push loop.
#export_name("mnpy_begin")
pub fn mnpy_begin(total : Int) -> Unit {
  let n = if total < 0 { 0 } else { total }
  demo_total.val = n
  demo_input.val = Array::make((n + 3) / 4 * 4, b'\x00')
  demo_cursor.val = 0
  demo_output.val = []
}

///|
// Append one little-endian 32-bit word. Words pushed past the reserved size
// are ignored, so the JS side may round the file up to whole words.
#export_name("mnpy_push_word")
pub fn mnpy_push_word(word : Int) -> Unit {
  let buf = demo_input.val
  let pos = demo_cursor.val
  if pos + 4 <= buf.length() {
    buf[pos] = (word & 0xFF).to_byte()
    buf[pos + 1] = ((word >> 8) & 0xFF).to_byte()
    buf[pos + 2] = ((word >> 16) & 0xFF).to_byte()
    buf[pos + 3] = ((word >> 24) & 0xFF).to_byte()
    demo_cursor.val = pos + 4
  }
}

///|
// Run the exact CLI inspect pipeline on the uploaded bytes (same code path as
// the `moon-npy` command), snapshotting the report for the pull interface.
#export_name("mnpy_inspect")
pub fn mnpy_inspect() -> Unit {
  let real = demo_total.val
  let data = Bytes::from_array(demo_input.val[:real])
  let outcome = @cli.run_inspect("uploaded.npy", data)
  demo_output.val = outcome.output.code_units().to_owned()
}

///|
// Number of UTF-16 code units in the report (0 before the first inspect).
#export_name("mnpy_out_len")
pub fn mnpy_out_len() -> Int {
  demo_output.val.length()
}

///|
// i-th UTF-16 code unit of the report, or -1 when the index is out of range.
#export_name("mnpy_out_unit")
pub fn mnpy_out_unit(index : Int) -> Int {
  if index >= 0 && index < demo_output.val.length() {
    demo_output.val[index].to_int()
  } else {
    -1
  }
}
