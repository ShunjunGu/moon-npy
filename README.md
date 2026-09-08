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
| NumPy 兼容性 Oracle + fixtures（26） | ✅ 就位（`interoperability/`, `tests/fixtures/`） |
| **M1** NPY header 解析（v1/v2/v3） | ✅ `src/header/` |
| **M2** dtype codec + Reader（decode → 类型化数组） | ✅ `src/dtype/`, `src/reader/` |
| **M3** Writer（encode → 字节级对齐 `np.save`） | ✅ `src/writer/` |
| **M4** `NumPy → MoonBit → NumPy` 字节级双向 round-trip + CI | ✅ **26/26**（第一阶段硬目标达成，§23） |
| **CLI**（`inspect` / `validate`） | ✅ `src/cli/`, `cmd/main/`（退出码 0/1/2 `$LASTEXITCODE` 实测） |
| **M5** 边缘 / Fuzz / 覆盖率（§18 totality、§14 阈值） | ✅ 85 测试全绿；core parser **98.5%**、overall **91.3%**（CI 强制门禁） |

Pinned toolchain（CI 复现基准）：**MoonBit `0.1.20260827`** · **NumPy `2.3.4`** · Python `3.14`。
85 单元测试（`moon test --target native`）+ 26 fixture 跨语言 round-trip 全绿；覆盖率 core parser
（format+lexer+parser）**98.5%**、项目 overall **91.3%**（CI 强制阈值 ≥90% / ≥80%）。

## Features

- ✅ **Reader** — NPY v1.0 / v2.0 / v3.0；primitive numeric dtype（bool / i1–i8 / u1–u8 /
  f4 / f8）；N-D shape（含 0-d scalar、3-D）；C / Fortran order；endianness（`<` / `>` / `|`）。
  结构化错误（`enum NpyError` + `Result`），损坏文件拒绝得也对。
- ✅ **Writer** — 产物与 `np.save` / `numpy.lib.format.write_array` **逐字节一致**（含 64
  字节对齐、空格填充、`\n` 收尾）；已验证至 300 KB payload。
- ✅ **Interop** — `NumPy → MoonBit → NumPy` 双向 round-trip，`np.array_equal` + 逐字节校验，
  26 fixture 全通过。
- ✅ **CLI** — `inspect <file.npy>`（元数据表）/ `validate <file.npy>`（`✓`/`✗` 判定）；退出码
  valid→0 / 非法文件→1 / 打不开或用法错→2（§13）。纯逻辑在 `src/cli/`，`cmd/main/` 只做 IO。
- ✅ **鲁棒性（M5）** — 边缘用例（0-d / N-D、Fortran-order、big-endian、`=` native、空数组、全
  dtype × shape × order × version）+ 确定性 splitmix fuzz（§18 totality：任意 `Bytes` → `decode` /
  `validate` 恒返 `Ok` 或结构化 `Err(NpyError)`，绝不 crash / hang / 越界 / 失控分配，7000 次迭代
  全绿）；负面用例在测试代码内合成，逐条钉住每个 `NpyError` 分支。

## Round-trip demo（§29）

NumPy 写一个 `100×768` float32 数组，MoonBit 读入 → 重新编码 → 写回，NumPy 再校验**逐字节一致**：

```bash
# 1) NumPy 产出 Oracle 数组
python -c "import numpy as np; np.save('embeddings.npy', np.arange(100*768, dtype='float32').reshape(100,768))"

# 2) MoonBit 读取 -> decode -> encode -> 写回（无 Python 运行时、无 FFI）
moon run examples/roundtrip --target native -- embeddings.npy embeddings-moonbit.npy
#    -> roundtrip OK: embeddings.npy -> embeddings-moonbit.npy | 307328 bytes | 76800 elements

# 3) NumPy 校验：np.array_equal + 逐字节一致
python interoperability/verify_moonbit_output.py embeddings-moonbit.npy \
    --reference embeddings.npy --byte-exact embeddings.npy
#    -> [verify] PASS
```

批量对全部 26 fixture 跑同一链路（**CI 实际执行的命令**）：

```bash
python interoperability/roundtrip.py        # emit(moon run) + verify(numpy) 聚合，26/26
```

## CLI（§13）

`cmd/main/` 是薄可执行壳（只做两件事：`@fs` 读字节、设进程退出码），全部参数解析与输出
渲染都在纯库 `src/cli/`（不碰 IO，可被 `tests/cli_test.mbt` 黑盒覆盖）。

```bash
moon run cmd/main --target native -- inspect  tests/fixtures/f4_2x3_c_le_v1.npy
moon run cmd/main --target native -- validate tests/fixtures/f4_2x3_c_le_v1.npy
```

`inspect` 打印元数据表（标签列宽 14，`Data size` 用二进制单位、两位小数）：

```text
NPY Array
──────────────────────────
Format        NPY 1.0
DType         float32
Byte order    little-endian
Shape         [2, 3]
Dimensions    2
Elements      6
Memory order  C
Data size     24 B
──────────────────────────
Status        valid
```

`validate` 成功打印 `✓ <file> is a valid NPY file`，失败打印 `✗ <file>` + 结构化错误。
**退出码纪律**：valid → 0；文件非法（任一 `NpyError`）→ 1；文件打不开 / 用法错误 → 2
（两类非 0 码互不混淆）。

## Compatibility Oracle

正确性以**当前 NumPy 的实际行为**为唯一 Oracle。`interoperability/generate_fixtures.py`
用 `numpy.lib.format` 生成 fixture，并从真实产物字节反推
[`tests/fixtures/expected.json`](tests/fixtures/expected.json)（version / descr /
shape / order / header_len / data_offset / checksum / values）。MoonBit 测试断言对齐
`expected.json`。详见 [`interoperability/README.md`](interoperability/README.md)。

当前 fixture 集（**26 个**）：float32 `(2,3)` C-order × v1.0 / v2.0 / v3.0（覆盖 uint16 与
uint32 两条 header-length 解析路径）+ 全 dtype × 字节序定向矩阵 + 0-d scalar + 3-D +
Fortran-order。

```bash
python interoperability/generate_fixtures.py           # 生成入库 fixture 集
python interoperability/generate_fixtures.py --check   # 校验未漂移（CI）
python interoperability/generate_fixtures.py --full    # §15 完整矩阵
```

## Layout

```text
moon-npy/
├── AGENTS.md              # M0 实测固化的工具链事实与项目约定（权威）
├── LICENSE                # Apache-2.0
├── moon.mod               # 模块清单（ShunjunGu/moon-npy, native）
├── src/
│   ├── format/            # magic + version 常量
│   ├── header/            # v1/v2/v3 header lexer + parser
│   ├── dtype/             # dtype codec + endian
│   ├── reader/            # decode(Bytes) -> NpyArray
│   ├── writer/            # encode(NpyArray) -> Bytes（字节级对齐 np.save）
│   ├── error/             # enum NpyError + Result
│   └── cli/               # inspect / validate 纯逻辑（parse_args + 渲染，无 IO）
├── cmd/main/              # CLI 可执行薄壳（@fs 读字节 + extern "c" exit 设退出码）
├── tests/                 # *_test.mbt（85，含 edge / fuzz）+ fixtures/（*.npy + expected.json）
├── interoperability/      # generate_fixtures.py / verify_moonbit_output.py / roundtrip.py
├── examples/roundtrip/    # emit harness（decode -> encode -> write，`moon run`）
└── .github/workflows/     # ci.yml（§19：fmt/check/test/coverage/fixture/round-trip）
```

## Building & testing

命令依据 `AGENTS.md` §8 实测（MoonBit `0.1.20260827`，native target）：

```bash
moon check --target native                 # 类型检查
moon test --target native                  # 85 单元测试
moon test --target native --enable-coverage; moon coverage report -f summary   # 覆盖率
python interoperability/generate_fixtures.py --check   # fixture 未漂移
python interoperability/roundtrip.py       # 26 fixture 字节级 round-trip
```

> `moon` 可能不在 PATH：`$env:Path = "$env:USERPROFILE\.moon\bin;$env:Path"`（PowerShell）。

## CI

[`.github/workflows/ci.yml`](.github/workflows/ci.yml)（§19）在 `ubuntu-latest` 上 pin
MoonBit `0.1.20260827+d0aaa07` / NumPy `2.3.4` / Python `3.14`，依次跑：`moon fmt`（无 diff）
→ `moon check` → `moon test` → coverage（**强制阈值门禁**：core parser ≥90% / overall ≥80%，未达
即失败）→ fixture `--check` → `roundtrip.py`（26 fixture emit + verify + byte-exact）→ CLI 冒烟
（inspect / validate + 退出码 0/1/2）。README 展示的例子即 CI 实际运行的例子（§19 铁律）。

## License

Apache-2.0 — see [`LICENSE`](LICENSE).

---

_Built for the 2026 MoonBit 国产基础软件生态开源大赛 · 9 月黑客松。_
_设计原则：NPY first / Correctness first / Interop first / Tests first / Small but complete._
