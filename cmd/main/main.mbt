// cmd/main — the thin executable shell for the moon-npy CLI (plan §13, §10.2).
// All argument parsing and output rendering live in the src/cli library; this
// file owns only the two side effects §10.2 permits a `cmd/main` to own: read
// the file's bytes (@fs) and set the process exit status. Usage:
//   moon run cmd/main --target native -- <inspect|validate|dump> <file.npy>
// @env.args()[0] is the exe path, so the subcommand is [1] and the path [2]
// (AGENTS.md §6).

///|
// C `exit(int)`, declared exactly as core/argparse declares its private
// runtime_native_exit (native/llvm only). This is the one mechanism the toolchain
// offers for a chosen non-zero exit status; the public abort() always panics with
// a single uncontrolled code and so cannot express §13's two distinct non-zero
// codes. Verified end-to-end via $LASTEXITCODE in the CLI smoke runs.
#cfg(any(target="native", target="llvm"))
extern "c" fn exit_with(code : Int) = "exit"

///|
// Non-native fallback: no C exit() is reachable, so degrade to abort (a single
// non-zero panic). The CLI is native-only in practice (§10.3: only IO/CLI needs
// the filesystem), so this branch exists only to keep the package compiling off
// native; the distinct-code granularity is intentionally lost there.
#cfg(not(any(target="native", target="llvm")))
fn exit_with(code : Int) -> Unit {
  let _ = code
  abort("moon-npy: cannot set a specific exit code on this target")
}

///|
// Turn argv into the outcome to print + exit with. Parse failures and IO
// failures (file missing / unreadable) become Operational outcomes; a readable
// file is dispatched to the pure command logic in src/cli. path_exists separates
// "cannot open" (Operational, exit 2) from a malformed file (Invalid, exit 1) so
// the two never collapse into one code (§13).
fn resolve(argv : Array[String]) -> @cli.CliOutcome {
  let parsed = match @cli.parse_args(argv) {
    Ok(p) => p
    Err(msg) => return @cli.operational(msg)
  }
  let (sub, path) = parsed
  if !@fs.path_exists(path) {
    return @cli.operational("moon-npy: cannot open '\{path}': no such file")
  }
  // @fs.read_file_to_bytes raises IOError; bridge to Result (AGENTS.md §2) and
  // treat a read error as Operational.
  let read_res = try @fs.read_file_to_bytes(path) |> Ok catch {
    e => Err(e)
  }
  let data : Bytes = match read_res {
    Ok(b) => b
    Err(_) => return @cli.operational("moon-npy: cannot read '\{path}'")
  }
  match sub {
    @cli.Inspect => @cli.run_inspect(path, data)
    @cli.Validate => @cli.run_validate(path, data)
    @cli.Dump(limit) => @cli.run_dump(path, data, limit)
  }
}

///|
fn main {
  let outcome = resolve(@env.args())
  println(outcome.output)
  exit_with(outcome.code.to_int())
}
