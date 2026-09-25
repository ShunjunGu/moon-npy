// End-to-end demo verification: load the wasm-gc artifact, feed real .npy
// images through the Int bridge, and assert the inspect reports and boundaries.
// Usage: node verify_demo.mjs <path-to.wasm> <file.npy> [more.npy ...]
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { basename } from "node:path";

const wasmPath = process.argv[2];
const npyPaths = process.argv.slice(3);
if (!wasmPath || npyPaths.length === 0) {
  console.error("usage: node verify_demo.mjs <wasm> <npy> [npy ...]");
  process.exit(2);
}

const mod = new WebAssembly.Module(await readFile(wasmPath));
const imports = WebAssembly.Module.imports(mod);
assert.deepEqual(imports, [], "browser demo must have no host imports");
console.log("imports:", JSON.stringify(imports));
const inst = new WebAssembly.Instance(mod, {});
const ex = inst.exports;
for (const name of ["mnpy_begin", "mnpy_push_word", "mnpy_inspect", "mnpy_out_len", "mnpy_out_unit"]) {
  assert.equal(typeof ex[name], "function", `missing WASM export ${name}`);
}

const expectedReports = new Map([
  ["f4_2x3_c_le_v1.npy", [/^DType\s+float32$/m, /^Shape\s+\[2, 3\]$/m, /^Memory order\s+C$/m]],
  ["i4_2x3_f_be_v1.npy", [/^DType\s+int32$/m, /^Shape\s+\[2, 3\]$/m, /^Memory order\s+Fortran$/m]],
]);

// Push the whole file as little-endian 32-bit words and pull the report back.
function inspectBytes(bytes) {
  ex.mnpy_begin(bytes.length);
  for (let i = 0; i < bytes.length; i += 4) {
    const w = (bytes[i] | (bytes[i + 1] << 8) | (bytes[i + 2] << 16) | (bytes[i + 3] << 24)) | 0;
    ex.mnpy_push_word(w);
  }
  ex.mnpy_inspect();
  const len = ex.mnpy_out_len();
  let out = "";
  for (let i = 0; i < len; i++) out += String.fromCharCode(ex.mnpy_out_unit(i));
  return out;
}

for (const p of npyPaths) {
  const bytes = await readFile(p);
  const report = inspectBytes(bytes);
  assert.match(report, /^NPY Array$/m, `${p}: missing valid inspect heading`);
  assert.match(report, /^Status\s+valid$/m, `${p}: inspect did not succeed`);
  for (const marker of expectedReports.get(basename(p)) ?? []) {
    assert.match(report, marker, `${p}: inspect metadata changed`);
  }
  console.log(`\n=== ${p} (${bytes.length} bytes) ===`);
  console.log(report);
}

// Boundary checks: malformed input must produce the failure report, not a trap.
const malformedReport = inspectBytes(new Uint8Array([1, 2, 3, 4, 5]));
assert.match(malformedReport, /^✗ uploaded\.npy$/m, "malformed input was accepted");
assert.match(malformedReport, /^TruncatedHeader$/m, "malformed input lacks a structured error");
const outLen = ex.mnpy_out_len();
assert.equal(ex.mnpy_out_unit(-1), -1, "negative output index was accepted");
assert.equal(ex.mnpy_out_unit(outLen), -1, "end output index was accepted");
assert.equal(ex.mnpy_out_unit(outLen + 1), -1, "past-end output index was accepted");
console.log("\n=== boundary: garbage input ===");
console.log(malformedReport);
console.log(
  "out_unit(-1) =",
  ex.mnpy_out_unit(-1),
  "| out_unit(len) =",
  ex.mnpy_out_unit(outLen),
  "| out_unit(len+1) =",
  ex.mnpy_out_unit(outLen + 1),
);
console.log(`PASS: ${npyPaths.length} fixture report(s), malformed input, and output bounds`);
