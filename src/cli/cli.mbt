// CLI logic layer (plan §13): pure, IO-free argument parsing and output
// rendering for the two v1 commands, `inspect` and `validate`. Per §10.2 every
// decision lives here as a testable library function, so cmd/main stays a thin
// shell that owns only the two side effects a `cmd/main` may own -- reading the
// file's bytes and setting the process exit status. Nothing in this package
// touches @fs / @env, which keeps the CLI compilable on every backend (§10.3)
// and covered directly by tests/cli_test.mbt.

///|
// The two v1 subcommands (§13). `dump` / `convert` / `benchmark` are Stretch
// (§6) and deliberately absent from the first version. `pub(all)` (like DType /
// ByteOrder / NpyError) so tests can construct the variants, not just match them.
pub(all) enum Subcommand {
  Inspect
  Validate
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
// Parse C-style argv into a subcommand + path. argv[0] is the exe path, so the
// subcommand is argv[1] and the file path argv[2] (AGENTS.md §6). Pure: it takes
// the argv array directly so tests can drive it without @env. Returns
// Err(usage message) when arguments are missing or the subcommand is unknown;
// main maps any Err to an Operational (exit 2) outcome.
pub fn parse_args(argv : Array[String]) -> Result[(Subcommand, String), String] {
  if argv.length() < 3 {
    return Err(usage())
  }
  let sub = argv[1]
  let path = argv[2]
  if sub == "inspect" {
    Ok((Inspect, path))
  } else if sub == "validate" {
    Ok((Validate, path))
  } else {
    Err("unknown subcommand: \{sub}\n\{usage()}")
  }
}

///|
// The one-line usage string shown on a parse failure.
fn usage() -> String {
  "usage: moon-npy <inspect|validate> <file.npy>"
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
