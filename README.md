# moon-npy

Pure MoonBit reader / writer for the **NumPy NPY binary array format** — an
interoperability layer between MoonBit's numeric-computing ecosystem and the
Python / NumPy / AI data ecosystem.

moon-npy lets MoonBit programs read, validate, and produce `.npy` files
**without a Python runtime and without Python FFI**. It is a *format
interop layer*, **not** a re-implementation of NumPy.

> 中文说明见 `README_CN.md`（docs 阶段补充）。

## Status

| 阶段 | 状态 |
|---|---|
| **M0** 工具链验证 gate（附录 B.2 全 7 项） | ✅ **GO** — 见 [`AGENTS.md`](AGENTS.md) |
| NumPy 兼容性 Oracle + P0 fixtures | ✅ 就位（`interoperability/`, `tests/fixtures/`） |
| MoonBit 模块脚手架 + NPY Reader | 🚧 下一步 |
| NPY Writer（字节级对齐）/ CLI | ⏳ 计划中 |

Pinned toolchain（CI 复现基准）：**MoonBit `0.1.20260827`** · **NumPy `2.3.4`** · Python `3.14.0`.

## Features (P0 target)

- **Reader** — NPY v1.0 / v2.0 / v3.0；primitive numeric dtype（bool / i1–i8 / u1–u8 / f4 / f8）；N-D shape；C / Fortran metadata；endianness（`<` / `>` / `|`，另接受 `=`）。结构化错误（`enum NpyError` + `Result`），损坏文件拒绝得也对。
- **Writer** — 产物与 `np.save` / `numpy.lib.format.write_array` **逐字节一致**（含 64 字节对齐、空格填充、`\n` 收尾）。
- **CLI** — `moon-npy inspect <file>` / `moon-npy validate <file>`。
- **Interop** — `NumPy → MoonBit` 与 `MoonBit → NumPy` 双向 round-trip 验证。

## Compatibility Oracle

正确性以**当前 NumPy 的实际行为**为唯一 Oracle。`interoperability/generate_fixtures.py`
用 `numpy.lib.format` 生成 fixture，并从真实产物字节反推
[`tests/fixtures/expected.json`](tests/fixtures/expected.json)（version / descr /
shape / order / header_len / data_offset / checksum / values）。MoonBit 测试断言对齐
`expected.json`。详见 [`interoperability/README.md`](interoperability/README.md)。

当前 P0 种子集：float32 `(2,3)` C-order × v1.0 / v2.0 / v3.0（覆盖 uint16 与 uint32
两条 header-length 解析路径）。

```bash
python interoperability/generate_fixtures.py           # 生成 P0 种子集
python interoperability/generate_fixtures.py --check   # 校验未漂移（CI）
python interoperability/generate_fixtures.py --full    # §15 完整矩阵
```

## Planned layout

```text
moon-npy/
├── AGENTS.md              # M0 实测固化的工具链事实与项目约定（权威）
├── LICENSE                # Apache-2.0
├── moon.mod               # 模块清单（脚手架阶段）
├── src/{format,header,dtype,reader,writer,error}/
├── cmd/main/              # CLI（inspect / validate）
├── tests/fixtures/        # *.npy + expected.json（Oracle）
├── interoperability/      # generate_fixtures.py / verify_moonbit_output.py
└── examples/{inspect,roundtrip}/
```

## Building & testing

MoonBit 模块脚手架落地后（下一步），使用（命令依据 `AGENTS.md` §8 实测）：

```bash
moon check --target native
moon test --target native --enable-coverage
moon coverage report -f summary
moon run cmd/main --target native -- inspect tests/fixtures/f4_2x3_c_le_v1.npy
```

> `moon` 可能不在 PATH：`$env:Path = "$env:USERPROFILE\.moon\bin;$env:Path"`（PowerShell）。

## License

Apache-2.0 — see [`LICENSE`](LICENSE).

---

_Built for the 2026 MoonBit 国产基础软件生态开源大赛 · 9 月黑客松。_
_设计原则：NPY first / Correctness first / Interop first / Tests first / Small but complete._
