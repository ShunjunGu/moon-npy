// CLI logic layer (plan §13): pure, IO-free argument parsing and output
// rendering for the v1 commands, `inspect` and `validate`, plus the S5 `dump`. Per §10.2 every
// decision lives here as a testable library function, so cmd/main stays a thin
// shell that owns only the two side effects a `cmd/main` may own -- reading the
// file's bytes and setting the process exit status. Nothing in this package
// touches @fs / @env, which keeps the CLI compilable on every backend (§10.3)
// and covered directly by tests/cli_test.mbt.

///|
// The v1 subcommands (§13) plus the S5 `dump` (plan v0.2 §6 / §7). `convert` /
// `benchmark` remain Stretch and are deliberately absent. `pub(all)` (like DType /
// ByteOrder / NpyError) so tests can construct the variants, not just match them.
// `Dump(Int)` carries the resolved element limit so the pure renderer never has
// to re-read argv; parse_args owns the default.
pub(all) enum Subcommand {
  Inspect
  Validate
  Dump(Int) // S5: element dump, Int = --limit
} derive(Debug, Eq)

///|
// Process exit codes (§13 "退出码纪律"). Two distinct non-zero codes let a caller
// tell a malformed file (Invalid) from a request that could not even be carried
// out -- an unreadable file or bad usage (Operational) -- so the two failure
// classes never collapse into one status. `pub(all)` so tests can construct the
// variants to assert an outcome's code, not merely match it.
pub(all) enum ExitCode {
  Success // 0 — the file is a well-formed NPY array
  Invalid // 1 — validate() produced an NpyError
  Operational // 2 — file could not be opened, or usage error
} derive(Debug, Eq)

///|
// The numeric exit status for an ExitCode (§13).
pub fn ExitCode::to_int(self : ExitCode) -> Int {
  match self {
    Success => 0
    Invalid => 1
    Operational => 2
  }
}

///|
// A rendered command result: the exact text main prints (one line or a
// multi-line block, with no trailing newline -- main's println supplies it) plus
// the exit code main uses. A `pub struct` from another package can have its
// fields read but not be constructed there, so cmd/main builds an operational
// outcome via `operational()` below rather than a record literal.
pub struct CliOutcome {
  output : String
  code : ExitCode
} derive(Debug)

///|
// Label column width of the inspect table (§13: "Memory order" is the longest
// label at 12 columns; every value starts at column 14).
let label_width : Int = 14

///|
// Element limit for `dump` when `--limit` is omitted (S5). Ten is the plan's
// pinned default (v0.2 §7): enough to eyeball a head of data, small enough that
// `dump` on a real embedding file does not flood the terminal.
let default_dump_limit : Int = 10

///|
// Parse C-style argv into a subcommand + path. argv[0] is the exe path, so the
// subcommand is argv[1] and the file path argv[2] (AGENTS.md §6). Pure: it takes
// the argv array directly so tests can drive it without @env. Returns
// Err(usage message) when arguments are missing or the subcommand is unknown;
// main maps any Err to an Operational (exit 2) outcome. Trailing arguments are
// never silently ignored: `inspect` / `validate` take exactly a path, and
// `dump` takes an optional `--limit N` and nothing else.
pub fn parse_args(argv : Array[String]) -> Result[(Subcommand, String), String] {
  if argv.length() < 3 {
    return Err(usage())
  }
  let sub = argv[1]
  let path = argv[2]
  if sub == "inspect" {
    if argv.length() > 3 {
      return Err(usage())
    }
    Ok((Inspect, path))
  } else if sub == "validate" {
    if argv.length() > 3 {
      return Err(usage())
    }
    Ok((Validate, path))
  } else if sub == "dump" {
    let has_limit_flag = argv.length() == 5 &&
      argv[3] == "--limit" &&
      is_digits(argv[4])
    if argv.length() == 3 {
      Ok((Dump(default_dump_limit), path))
    } else if has_limit_flag {
      match parse_limit(argv[4]) {
        Some(n) => Ok((Dump(n), path))
        None => Err(usage())
      }
    } else {
      Err(usage())
    }
  } else {
    Err("unknown subcommand: \{sub}\n\{usage()}")
  }
}

///|
// Parse a `--limit` value that is_digits() has already accepted. The digits-only
// check rules out signs, base prefixes and junk, but a decimal literal long
// enough to overflow the 32-bit Int (AGENTS.md §4) is still possible, and
// @string.parse_int reports that by raising. A limit that cannot be represented
// is a usage error -- library code must not trap on input it can still describe
// (§18 totality).
fn parse_limit(s : String) -> Int? {
  try @string.parse_int(s) |> Some catch {
    _ => None
  }
}

///|
// The one-line usage string shown on a parse failure.
fn usage() -> String {
  "usage: moon-npy <inspect|validate|dump> <file.npy> [--limit N]"
}

///|
// True when every character is an ASCII digit (and the string is non-empty), so
// `--limit -1` and `--limit x` are usage errors rather than parse surprises.
fn is_digits(s : String) -> Bool {
  if s.is_empty() {
    return false
  }
  for c in s {
    if c < '0' || c > '9' {
      return false
    }
  }
  true
}

///|
// Build an Operational outcome carrying `msg` (exit code 2). cmd/main uses this
// for the IO/usage failures it detects on the native side (file cannot be opened
// or read, bad usage), keeping CliOutcome construction inside this package.
pub fn operational(msg : String) -> CliOutcome {
  CliOutcome::{ output: msg, code: Operational, }
}

///|
// inspect: validate the bytes, then render the metadata table (§13). A parse
// failure renders the same ✗ block as validate and exits Invalid (1).
pub fn run_inspect(path : String, data : Bytes) -> CliOutcome {
  match @reader.validate(data) {
    Ok(meta) => CliOutcome::{ output: render_inspect(meta), code: Success, }
    Err(e) => CliOutcome::{ output: render_failure(path, e), code: Invalid, }
  }
}

///|
// validate: report only whether the bytes are a well-formed NPY file (§13).
// Success prints the ✓ line (exit 0); failure prints the ✗ block (exit 1).
pub fn run_validate(path : String, data : Bytes) -> CliOutcome {
  match @reader.validate(data) {
    Ok(_) =>
      CliOutcome::{ output: "✓ \{path} is a valid NPY file", code: Success, }
    Err(e) => CliOutcome::{ output: render_failure(path, e), code: Invalid, }
  }
}

///|
// dump: decode the payload, then render the first min(limit, element_count)
// elements in storage order (S5). A parse or decode failure reuses the same ✗
// block and Invalid exit code as inspect, so the three commands agree on what a
// bad file looks like. The accessors materialize every element before the
// renderer truncates, so dumping a very large array is the S4 chunk API's job;
// the README says so where dump is documented.
pub fn run_dump(path : String, data : Bytes, limit : Int) -> CliOutcome {
  match @reader.decode(data) {
    Ok(arr) =>
      match dump_values(arr) {
        Ok(values) =>
          CliOutcome::{
            output: render_dump(path, values, limit),
            code: Success,
          }
        Err(e) =>
          CliOutcome::{ output: render_failure(path, e), code: Invalid, }
      }
    Err(e) => CliOutcome::{ output: render_failure(path, e), code: Invalid, }
  }
}

///|
// Turn one accessor result into display strings, keeping the Ok / Err shape of
// every dtype branch identical. A closure parameter rather than a trait bound
// because the dtypes render differently (complex is a pair).
fn[T] render_all(
  res : Result[Array[T], @error.NpyError],
  show_value : (T) -> String,
) -> Result[Array[String], @error.NpyError] {
  match res {
    Ok(vals) => {
      let out : Array[String] = []
      for v in vals {
        out.push(show_value(v))
      }
      Ok(out)
    }
    Err(e) => Err(e)
  }
}

///|
// Per-dtype element extraction, each value pre-rendered to its display string.
// The match is exhaustive over all 13 dtypes on purpose: unlike the rest of the
// CLI there is no sensible "not supported yet" here, and a future dtype must
// fail the build rather than degrade into an UnsupportedDType row. The
// rendering closure is written out per branch rather than shared through a
// `let` -- MoonBit does not generalize a local binding over `T`, so one
// polymorphic `digits` value would be pinned to the first dtype that used it.
fn dump_values(
  arr : @reader.NpyArray,
) -> Result[Array[String], @error.NpyError] {
  match arr.dtype {
    @dtype.Bool => render_all(arr.to_bool(), fn(v) { v.to_string() })
    @dtype.Int8 => render_all(arr.to_i8(), fn(v) { v.to_string() })
    @dtype.Int16 => render_all(arr.to_i16(), fn(v) { v.to_string() })
    @dtype.Int32 => render_all(arr.to_i32(), fn(v) { v.to_string() })
    @dtype.Int64 => render_all(arr.to_i64(), fn(v) { v.to_string() })
    @dtype.UInt8 => render_all(arr.to_u8(), fn(v) { v.to_string() })
    @dtype.UInt16 => render_all(arr.to_u16(), fn(v) { v.to_string() })
    @dtype.UInt32 => render_all(arr.to_u32(), fn(v) { v.to_string() })
    @dtype.UInt64 => render_all(arr.to_u64(), fn(v) { v.to_string() })
    @dtype.Float32 => render_all(arr.to_f32(), fn(v) { v.to_string() })
    @dtype.Float64 => render_all(arr.to_f64(), fn(v) { v.to_string() })
    @dtype.Complex64 =>
      render_all(arr.to_c64(), fn(z : @dtype.Complex) { "(\{z.re}, \{z.im})" })
    @dtype.Complex128 =>
      render_all(arr.to_c16(), fn(z : @dtype.Complex) { "(\{z.re}, \{z.im})" })
  }
}

///|
// The dump block: the "NPY Dump: <path>" title and the same 26-character rule as
// inspect, then "[i] value" for the first min(limit, length) entries, then the
// count row (§13 table style reused for S5). The total comes from the rendered
// values rather than meta.element_count so no Int64 -> Int narrowing is needed:
// decode() has already reconciled payload_len with element_count * itemsize, and
// payload_len is bounded by the file size, so the two counts always agree here.
fn render_dump(path : String, values : Array[String], limit : Int) -> String {
  let total = values.length()
  let shown = if limit < total { limit } else { total }
  let lines : Array[String] = ["NPY Dump: \{path}", table_rule()]
  for i = 0; i < shown; i = i + 1 {
    lines.push("[\{i}] \{values[i]}")
  }
  lines.push("(showing \{shown} of \{total} elements)")
  join_lines(lines)
}

///|
// The ✗ block both commands share on a parse failure (§13): the path, then the
// structured error rendering.
fn render_failure(path : String, e : @error.NpyError) -> String {
  "✗ \{path}\n\{render_error(e)}"
}

///|
// Build the inspect table exactly as §13 specifies: the "NPY Array" title, a
// 26-character U+2500 rule, one padded row per field, a second rule, then the
// Status row. Every value comes from the validated NpyMeta; Data size is the
// payload byte count validate() already reconciled (element_count * itemsize).
fn render_inspect(meta : @reader.NpyMeta) -> String {
  let h = meta.header
  let order = if h.fortran_order { "Fortran" } else { "C" }
  let rule = table_rule()
  join_lines([
    "NPY Array",
    rule,
    row("Format", version_label(meta.version)),
    row("DType", @dtype.name(meta.dtype)),
    row("Byte order", byte_order_label(meta.byte_order)),
    row("Shape", shape_label(h.shape)),
    row("Dimensions", "\{h.shape.length()}"),
    row("Elements", "\{meta.element_count}"),
    row("Memory order", order),
    row("Data size", human_size(meta.payload_len)),
    rule,
    row("Status", "valid"),
  ])
}

///|
// The 26-character U+2500 rule that fences the inspect table (§13). Built by
// repetition so the character count is exact rather than hand-typed.
fn table_rule() -> String {
  let mut s = ""
  for i = 0; i < 26; i = i + 1 {
    s = "\{s}─"
  }
  s
}

///|
// Join lines with a single '\n' between them and no trailing newline (main's
// println supplies the final one). Array has no join, so concatenate manually
// (the same loop form the Writer uses).
fn join_lines(lines : Array[String]) -> String {
  let mut out = ""
  for i = 0; i < lines.length(); i = i + 1 {
    if i > 0 {
      out = "\{out}\n"
    }
    out = "\{out}\{lines[i]}"
  }
  out
}

///|
// One inspect row: the label padded with spaces into a `label_width`-column
// field, then the value (§13 alignment). Labels are ASCII, so String.length()'s
// byte count equals the column count.
fn row(label : String, value : String) -> String {
  let mut s = label
  let pad = label_width - label.length()
  for i = 0; i < pad; i = i + 1 {
    s = "\{s} "
  }
  "\{s}\{value}"
}

///|
// NpyVersion -> the "NPY x.y" label (§13 shows "NPY 1.0").
fn version_label(v : @format.NpyVersion) -> String {
  match v {
    @format.V1_0 => "NPY 1.0"
    @format.V2_0 => "NPY 2.0"
    @format.V3_0 => "NPY 3.0"
  }
}

///|
// ByteOrder -> a human label. Little/Big name the endianness; NotApplicable is
// the '|' single-byte/bool case where order is irrelevant; Native is the '='
// writer-order case (§9.2).
fn byte_order_label(o : @dtype.ByteOrder) -> String {
  match o {
    @dtype.Little => "little-endian"
    @dtype.Big => "big-endian"
    @dtype.NotApplicable => "not applicable"
    @dtype.Native => "native"
  }
}

///|
// Shape -> "[a, b, ...]" (§13 shows "[1024, 768]"); a 0-d scalar renders "[]".
fn shape_label(shape : Array[UInt64]) -> String {
  let mut s = "["
  for i = 0; i < shape.length(); i = i + 1 {
    if i > 0 {
      s = "\{s}, "
    }
    s = "\{s}\{shape[i].to_string()}"
  }
  "\{s}]"
}

///|
// Render a byte count as a human-readable binary-unit size with two decimals
// (§13 shows "3.00 MiB"). Counts below 1 KiB print as an integer "N B". Integer
// math keeps the displayed digits exact. The CLI only ever feeds this the
// payload length, which is bounded by the file size (an Int), so `total * 100`
// stays far inside Int64; callers passing an astronomically large literal are
// outside the intended domain.
pub fn human_size(total : Int64) -> String {
  let units : Array[String] = ["B", "KiB", "MiB", "GiB", "TiB", "PiB", "EiB"]
  // Find the largest unit whose threshold (1024^u) still fits in `total`.
  let mut u = 0
  let mut threshold = 1024L
  while u < 6 && total >= threshold {
    u = u + 1
    threshold = threshold * 1024L
  }
  if u == 0 {
    return "\{total} B"
  }
  // divisor = 1024^u; scaled = floor(total * 100 / divisor) = whole hundredths.
  let mut divisor = 1L
  for i = 0; i < u; i = i + 1 {
    divisor = divisor * 1024L
  }
  let scaled = total * 100L / divisor
  let whole = scaled / 100L
  let frac = scaled % 100L
  let frac_str = if frac < 10L { "0\{frac}" } else { "\{frac}" }
  "\{whole}.\{frac_str} \{units[u]}"
}

///|
// Render an NpyError for the CLI failure block (§13). The first line is always
// the variant name; variants carrying a payload add detail lines below it. The
// DataLengthMismatch layout ("Expected:" / "Actual:" aligned, thousands-separated
// byte counts) is pinned by §13; the other detail lines follow the same shape.
pub fn render_error(e : @error.NpyError) -> String {
  match e {
    @error.InvalidMagic => "InvalidMagic"
    @error.UnsupportedVersion(maj, min) =>
      "UnsupportedVersion\nVersion: \{maj}.\{min}"
    @error.TruncatedHeader => "TruncatedHeader"
    @error.InvalidHeaderLength => "InvalidHeaderLength"
    @error.InvalidHeaderSyntax => "InvalidHeaderSyntax"
    @error.MissingHeaderField(f) => "MissingHeaderField\nField: \{f}"
    @error.InvalidDType(d) => "InvalidDType\nDType descr: \{d}"
    @error.UnsupportedDType(d) => "UnsupportedDType\nDType descr: \{d}"
    @error.ShapeOverflow => "ShapeOverflow"
    @error.DataLengthMismatch(expected, actual) =>
      "DataLengthMismatch\nExpected: \{group_digits(expected)} bytes\nActual:   \{group_digits(actual)} bytes"
    @error.UnsupportedObjectArray => "UnsupportedObjectArray"
    @error.InvalidByteOrder(b) =>
      "InvalidByteOrder\nByte order marker: \{b.to_int()}"
  }
}

///|
// Insert a thousands separator into a non-negative integer's decimal text (§13
// shows "3,145,728"). Digits are collected from the least significant end, a
// comma every three, then read back in order.
fn group_digits(n : Int64) -> String {
  let s = "\{n}"
  let len = s.length()
  if len <= 3 {
    return s
  }
  let rev : Array[Char] = []
  let mut k = 0
  for i = len - 1; i >= 0; i = i - 1 {
    if k > 0 && k % 3 == 0 {
      rev.push(',')
    }
    match s.get_char(i) {
      Some(c) => rev.push(c)
      None => ()
    }
    k = k + 1
  }
  let mut out = ""
  for j = rev.length() - 1; j >= 0; j = j - 1 {
    out = "\{out}\{rev[j]}"
  }
  out
}
