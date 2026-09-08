#!/usr/bin/env python3
"""M4 cross-language round-trip driver (plan §16 / §19 / §23 / §29).

Oracle-driven: the authoritative fixture list comes from
``tests/fixtures/expected.json`` (produced by ``generate_fixtures.py`` from real
NumPy output), never a hand-maintained list. For each fixture the driver runs the
two remaining §19 CI stages that ``moon test`` cannot cover on its own:

  1. emit   — ``moon run examples/roundtrip --target native -- <in> <out>``
              MoonBit reads the NumPy fixture, decodes it, re-encodes it with the
              Writer, and writes the bytes to disk ("MoonBit Generates NPY").
  2. verify — ``python verify_moonbit_output.py <out> --reference <in>
              --byte-exact <in>``
              NumPy loads the MoonBit-written file and asserts dtype/shape/values
              match ("NumPy Reads MoonBit", np.array_equal) AND that it is
              byte-for-byte identical to the Oracle fixture ("Byte-level
              round-trip", the B1 alignment regression).

Together these close ``NumPy -> MoonBit -> NumPy`` end to end across two language
runtimes -- the first-phase hard goal (§23). Verification is delegated to
``verify_moonbit_output.py`` so there is a single Oracle source of truth (§19
铁律: the example the README shows is the example CI actually runs).

Exit code: 0 if every fixture passes both stages, 1 otherwise (so CI fails).

Usage:
  python interoperability/roundtrip.py [--moon PATH] [--out-dir DIR]
                                       [--only NAME] [-v]

``moon`` is resolved from --moon, then $MOON_BIN, then PATH (AGENTS.md §8 notes
moon may live in ~/.moon/bin and not be on PATH).
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

# Repo-relative anchors: this file lives in interoperability/, so ROOT is the
# module root (where moon.mod is). moon/verify are invoked with cwd=ROOT so the
# fixture-relative paths inside expected.json and the harness resolve identically
# to how `moon test` sees them (AGENTS.md §7).
ROOT = Path(__file__).resolve().parent.parent
FIXTURES = ROOT / "tests" / "fixtures"
EXPECTED = FIXTURES / "expected.json"
VERIFY = ROOT / "interoperability" / "verify_moonbit_output.py"
HARNESS_PKG = "examples/roundtrip"


def load_fixture_names(only):
    """Return the fixture filenames to exercise, straight from the Oracle."""
    data = json.loads(EXPECTED.read_text(encoding="utf-8"))
    names = [entry["file"] for entry in data["fixtures"]]
    if only is not None:
        names = [n for n in names if n == only]
        if not names:
            raise SystemExit(f"[roundtrip] --only {only!r} not found in expected.json")
    return names


def resolve_moon(cli_moon):
    """moon binary: --moon > $MOON_BIN > 'moon' on PATH."""
    return cli_moon or os.environ.get("MOON_BIN") or "moon"


def run(cmd):
    """Run cmd with cwd=ROOT, capturing stdout+stderr as UTF-8 text.

    moon writes build progress to stderr (AGENTS.md §8); capturing it keeps the
    driver's own report clean and works identically on Windows and Linux CI.
    """
    try:
        proc = subprocess.run(
            cmd,
            cwd=ROOT,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
    except FileNotFoundError:
        return 127, f"command not found: {cmd[0]!r}"
    return proc.returncode, (proc.stdout + proc.stderr).strip()


def emit(moon, in_path, out_path):
    """Stage 1: MoonBit decode -> encode -> write the fixture to out_path."""
    out_path.parent.mkdir(parents=True, exist_ok=True)
    cmd = [
        moon, "run", HARNESS_PKG, "--target", "native", "--",
        in_path.as_posix(), out_path.as_posix(),
    ]
    code, msg = run(cmd)
    return code == 0, msg


def verify(out_path, ref_path, verbose):
    """Stage 2: NumPy loads out_path; array_equal + byte-exact vs the Oracle."""
    cmd = [
        sys.executable, VERIFY.as_posix(), out_path.as_posix(),
        "--reference", ref_path.as_posix(),
        "--byte-exact", ref_path.as_posix(),
    ]
    if verbose:
        cmd.append("-v")
    code, msg = run(cmd)
    return code == 0, msg


def _indent(text, prefix="        "):
    return "\n".join(prefix + line for line in text.splitlines())


def main(argv=None):
    ap = argparse.ArgumentParser(
        description="NumPy -> MoonBit -> NumPy byte-exact round-trip driver (§16/§19).",
    )
    ap.add_argument("--moon", help="path to the moon binary (default: $MOON_BIN or PATH)")
    ap.add_argument(
        "--out-dir",
        default=str(ROOT / "_build" / "m4_out"),
        help="where MoonBit-written .npy files land (default: _build/m4_out, gitignored)",
    )
    ap.add_argument("--only", help="run a single fixture by filename (debugging)")
    ap.add_argument("-v", "--verbose", action="store_true", help="show verify detail")
    args = ap.parse_args(argv)

    names = load_fixture_names(args.only)
    moon = resolve_moon(args.moon)
    out_dir = Path(args.out_dir)

    print(f"[roundtrip] moon={moon}  fixtures={len(names)}  out_dir={out_dir}")
    passed = []
    failed = []  # (name, stage, message)

    for name in names:
        in_path = FIXTURES / name
        out_path = out_dir / name
        ok, msg = emit(moon, in_path, out_path)
        if not ok:
            failed.append((name, "emit", msg))
            print(f"  [FAIL] {name}  (emit)")
            if args.verbose:
                print(_indent(msg))
            continue
        ok, msg = verify(out_path, in_path, args.verbose)
        if not ok:
            failed.append((name, "verify", msg))
            print(f"  [FAIL] {name}  (verify)")
            if args.verbose:
                print(_indent(msg))
            continue
        passed.append(name)
        print(f"  [PASS] {name}")

    print(f"\n[roundtrip] {len(passed)}/{len(names)} passed, {len(failed)} failed")
    if failed:
        for name, stage, _ in failed:
            print(f"  - FAILED {name} at stage '{stage}'")
        return 1
    print("[roundtrip] OK: every fixture is a byte-exact NumPy -> MoonBit -> NumPy round-trip")
    return 0


if __name__ == "__main__":
    sys.exit(main())
