// End-to-end demo verification: load the wasm-gc artifact, feed a real .npy
// image through the Int bridge (mnpy_begin / mnpy_push_word / mnpy_inspect),
// then pull the inspect report back one UTF-16 code unit at a time.
// Usage: node verify_demo.mjs <path-to.wasm> <file.npy> [more.npy ...]
import { readFile } from "node:fs/promises";

const wasmPath = process.argv[2];
const npyPaths = process.argv.slice(3);
if (!wasmPath || npyPaths.length === 0) {
  console.error("usage: node verify_demo.mjs <wasm> <npy> [npy ...]");
  process.exit(2);
}

const mod = new WebAssembly.Module(await readFile(wasmPath));
console.log("imports:", JSON.stringify(WebAssembly.Module.imports(mod)));
const inst = new WebAssembly.Instance(mod, {});
const ex = inst.exports;

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
  console.log(`\n=== ${p} (${bytes.length} bytes) ===`);
  console.log(inspectBytes(bytes));
}

// Boundary checks: malformed input must produce the failure report, not a trap.
console.log("\n=== boundary: garbage input ===");
console.log(inspectBytes(new Uint8Array([1, 2, 3, 4, 5])));
console.log(
  "out_unit(-1) =",
  ex.mnpy_out_unit(-1),
  "| out_unit(len+1) =",
  ex.mnpy_out_unit(ex.mnpy_out_len() + 1),
);
