# moon-npy

Pure MoonBit reader / writer for the **NumPy NPY binary array format** — an
interoperability layer between MoonBit's numeric-computing ecosystem and the
Python / NumPy / AI data ecosystem.

moon-npy lets MoonBit programs read, validate, and produce `.npy` files
**without a Python runtime and without Python FFI**. It is a *format
interop layer*, **not** a re-implementation of NumPy.

> 中文说明见 [`README_CN.md`](README_CN.md)。

## Ecosystem Position

```text
               Numerical Computing
         numbt / numoon / moonNum
                   │ arrays
                   ▼
             ┌───────────┐
             │ moon-npy  │
             └───────────┘
                   │ .npy
                   ▼
       NumPy / PyTorch / ML ecosystem
```

> `moon-npy` is not another NumPy implementation. Existing MoonBit numerical
> libraries focus on numerical computation and multidimensional arrays;
> `moon-npy` focuses specifically on **interoperable NumPy binary
> serialization** — the missing `.npy` bridge that lets a MoonBit program
> exchange arrays with the Python / ML data ecosystem byte-for-byte.

## Status

| 阶段 | 状态 |
|---|---|
| **M0** 工具链验证 gate（附录 B.2 全 7 项） | ✅ **GO** — 见 [`AGENTS.md`](AGENTS.md) |
| NumPy 兼容性 Oracle + fixtures（31） | ✅ 就位（`interoperability/`, `tests/fixtures/`） |
| **M1** NPY header 解析（v1/v2/v3） | ✅ `src/header/` |
| **M2** dtype codec + Reader（decode → 类型化数组） | ✅ `src/dtype/`, `src/reader/` |
| **M3** Writer（encode → 字节级对齐 `np.save`） | ✅ `src/writer/` |
| **M4** `NumPy → MoonBit → NumPy` 字节级双向 round-trip + CI | ✅ **31/31**（第一阶段硬目标达成，§23） |
| **CLI**（`inspect` / `validate` / `dump`） | ✅ `src/cli/`, `cmd/main/`（退出码 0/1/2 `$LASTEXITCODE` 实测） |
| **M5** 边缘 / Fuzz / 覆盖率（§18 totality、§14 阈值） | ✅ 128 测试全绿；core parser **98.5%**、overall **91.7%**（CI 强制门禁） |
| **S1** complex64 / complex128 读取（v0.2.0 Stretch，§6） | ✅ `src/dtype/`（`Complex` + `read_c64` / `read_c16`）、`src/reader/`（`to_c64` / `to_c16`） |
| **S5** CLI `dump [--limit N]`（v0.2.0 Stretch，§6） | ✅ `src/cli/`（`run_dump`，13 个 dtype 全覆盖）、`cmd/main/`（CI 冒烟实测） |
| **S4** storage-order 分块读取（v0.2.0 Stretch，§6） | ✅ `src/reader/`（`flat_range` + `to_f32_chunk` / `to_f64_chunk`）、`src/error/` + `src/cli/`（第 13 变体 `InvalidChunkRange` 及其渲染） |
| **S6** moonNum 生态适配（v0.2.0 Stretch，§6） | ✅ `src/adapter/moonnum/`（读方向 `to_moonnum_f32` / `to_moonnum_f64`）；选型 go/no-go 见 [`docs/s6-api-card.md`](docs/s6-api-card.md) |

Pinned toolchain（CI 复现基准）：**MoonBit `0.1.20260827`** · **NumPy `2.3.4`** · Python `3.14`。
128 个单元测试（`moon test --target native`）+ 31 fixture 跨语言 round-trip 全绿；覆盖率 core parser
（format+lexer+parser）**98.5%**、项目 overall **91.7%**（CI 强制阈值 ≥90% / ≥80%）。

## Features

- ✅ **Reader** — NPY v1.0 / v2.0 / v3.0；primitive numeric dtype（bool / i1–i8 / u1–u8 /
  f4 / f8）+ complex（c8 / c16，v0.2.0 S1 起）；N-D shape（含 0-d scalar、3-D）；C / Fortran
  order；endianness（`<` / `>` / `|`，Reader 另接受 `=`）。结构化错误（`enum NpyError` +
  `Result`），损坏文件拒绝得也对。
- ✅ **分块读取（S4）** — `to_f32_chunk(start, len)` / `to_f64_chunk(start, len)` 按 storage order
  只解码一个窗口（行读取场景）；越界或负值返回第 13 个结构化错误 `InvalidChunkRange(start, len)`，
  绝不 panic。省的是**输出数组**，payload 仍随 `decode` 全量驻留内存（无跨文件 I/O streaming，见
  Limitations）。
- ✅ **生态适配（S6）** — `to_moonnum_f32` / `to_moonnum_f64` 把 `decode` 得到的 `NpyArray` 交给
  `amor2025/moonNum` 的 `NdArray`（shape / storage order 原样传递，零元素解码）；big-endian、非
  f32/f64、以及装不进 32 位 `Int` 的 shape 维度**前置拒绝**，失败用适配器自己的 `AdapterError`
  表达（不侵入 `NpyError`，见下节 Ecosystem Adapter）。
- ✅ **Writer** — 产物与 `np.save` / `numpy.lib.format.write_array` **逐字节一致**（含 64
  字节对齐、空格填充、`\n` 收尾）；已验证至 300 KB payload。
- ✅ **Interop** — `NumPy → MoonBit → NumPy` 双向 round-trip，`np.array_equal` + 逐字节校验，
  31 fixture 全通过。
- ✅ **CLI** — `inspect <file.npy>`（元数据表）/ `validate <file.npy>`（`✓`/`✗` 判定）/
  `dump <file.npy> [--limit N]`（逐元素值，默认前 10 个）；退出码
  valid→0 / 非法文件→1 / 打不开或用法错→2（§13）。纯逻辑在 `src/cli/`，`cmd/main/` 只做 IO。
- ✅ **鲁棒性（M5）** — 边缘用例（0-d / N-D、Fortran-order、big-endian、`=` native、空数组、全
  dtype × shape × order × version）+ 确定性 splitmix fuzz（§18 totality：任意 `Bytes` → `decode` /
  `validate` 恒返 `Ok` 或结构化 `Err(NpyError)`，绝不 crash / hang / 越界 / 失控分配，7000 次迭代
  全绿）；负面用例在测试代码内合成，逐条钉住每个 `NpyError` 分支。

## Installation

模块清单 `moon.mod` 声明 `name = "ShunjunGu/moon-npy"`、`version = "0.2.0"`、
`preferred_target = "native"`，依赖 `moonbitlang/x@0.5.1`（`@fs` 文件 IO）与
`amor2025/moonNum@0.1.0`（仅 S6 适配器 `src/adapter/moonnum/` 使用，详见下文 Ecosystem
Adapter）。核心层（format / header / dtype / reader / writer / error / cli）不依赖任何第三方库。

**作为依赖引入**（发布到 Mooncakes 后；当前尚未发布，请从源码构建）：

```bash
moon add ShunjunGu/moon-npy
```

随后在用到它的包的 `moon.pkg` 里按需 import（包级引用）：

```jsonc
// your moon.pkg
import {
  "ShunjunGu/moon-npy/src/reader",
  "ShunjunGu/moon-npy/src/writer",
  "ShunjunGu/moon-npy/src/dtype",
  "ShunjunGu/moon-npy/src/error",
}
```

**从源码构建 / 运行 CLI**（native target）：

```bash
git clone https://github.com/ShunjunGu/moon-npy && cd moon-npy
moon check --target native                 # 类型检查
moon run cmd/main --target native -- inspect tests/fixtures/f4_2x3_c_le_v1.npy
```

> `moon` 可能不在 PATH：PowerShell 下 `$env:Path = "$env:USERPROFILE\.moon\bin;$env:Path"`。

## Quick Start

读一个 `.npy` 并取出类型化元素（`decode` 返回 `Result`，失败是结构化 `NpyError`，绝不 crash）：

```moonbit
// bytes: 文件字节，例如 @fs.read_file_to_bytes("array.npy")（raise IOError，需 try 桥接）
match @reader.decode(bytes) {
  Ok(arr) => {
    println("dtype=\{@dtype.name(arr.dtype)}  shape=\{arr.header.shape}")
    let flat : Array[Float] = arr.to_f32().unwrap() // storage-order 扁平元素
    println("elements=\{arr.element_count}  first=\{flat[0]}")
  }
  Err(err) => println(@cli.render_error(err)) // 结构化错误渲染
}
```

`decode` 校验 magic / version / header / dtype / shape 溢出 / payload 长度后切出 payload；
元素解码是**惰性**的（指不调用 accessor 就不解码；payload 本身已随 `decode` 全量在内存）——
`to_bool` / `to_i8`…`to_i64` / `to_u8`…`to_u64` / `to_f32` / `to_f64` / `to_c64`
/ `to_c16` 按需把 payload 解成对应 MoonBit 类型的扁平数组（storage order）。只需元数据不解元素时用
`validate`（返回 `NpyMeta`）。写回：`@writer.encode(arr)` 得到与 `np.save` 逐字节一致的 `Bytes`。

complex 两种宽度共用一个 `Complex` 元素结构，分量统一为 64 位 `Double`（`complex64` 的 f32 分量
无损加宽）：

```moonbit
let z : Array[@dtype.Complex] = arr.to_c64().unwrap()
assert_eq(z[1], @dtype.Complex::{ re: 1.0, im: 2.0 }) // tests/fixtures/c8_4_c_le_v1.npy
```

只取一行（S4）：C-order 下 `(rows, cols)` 的第 k 行从元素 `k * cols` 开始，所以 §29 Demo 那个
`100×768` 的 embeddings 读第 k 行就是 `to_f32_chunk(k * 768, 768)`：

```moonbit
let row1 : Array[Float] = arr.to_f32_chunk(3, 3).unwrap() // (2,3) 的第 1 行 = 元素 [3, 6)
assert_eq(row1.map(fn(x) { x.to_double() }), [3.0, 4.0, 5.0]) // tests/fixtures/f4_2x3_c_le_v1.npy
```

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

批量对全部 31 fixture 跑同一链路（**CI 实际执行的命令**）：

```bash
python interoperability/roundtrip.py        # emit(moon run) + verify(numpy) 聚合，31/31
```

## Compatibility Matrix

正确性以**当前 NumPy 的实际行为**为唯一 Oracle。支持矩阵（§15，全部经 fixture 实测）：

| 维度 | 支持取值 | 说明 |
|---|---|---|
| **version** | 1.0 / 2.0 / 3.0 | v1 用 uint16 header-length，v2/v3 用 uint32 |
| **dtype** | `bool` · `i1 i2 i4 i8` · `u1 u2 u4 u8` · `f4 f8` · `c8 c16` | 13 种：11 种 primitive numeric + 2 种 complex（`c8` / `c16` 自 v0.2.0 S1）；各有 `to_*` accessor |
| **shape** | 0-d `()` · 1-d · N-d（实测含 `(2,3)`、`(2,2,2)`） | 0-d scalar → `element_count == 1` |
| **memory order** | C / Fortran | `fortran_order` 作 metadata；accessor 返回 storage-order 扁平数组 |
| **byte order** | `<` little · `>` big · `\|` N/A · `=` native | `=` native 读作 little-endian（MoonBit 各后端均小端，平台假设） |

**不支持**（识别后返回结构化 `UnsupportedDType` / `UnsupportedObjectArray`，而非静默出错）：
object（`\|O`，**主动拒绝**，见 Security）、half / longdouble（`e`/`g`）、complex256（`C`）、
bytes / str（`S`/`U`）、void / structured（`V`）、datetime / timedelta（`M`/`m`）。NPZ、
GGUF / SafeTensors / Parquet 不在范围内（见 Limitations）。

当前入库 fixture 集（**31 个**）：float32 `(2,3)` C-order × v1.0 / v2.0 / v3.0（覆盖 uint16 与
uint32 两条 header-length 解析路径）+ 全 dtype × 字节序定向矩阵（含 `c8` / `c16` 的 LE / BE 与 2-D
`c8`，v0.2.0 S1）+ 0-d scalar + 3-D + Fortran-order。fixture 由
`interoperability/generate_fixtures.py` 用 `numpy.lib.format` 生成，
并从真实产物字节反推 [`tests/fixtures/expected.json`](tests/fixtures/expected.json)（version /
descr / shape / order / header_len / data_offset / checksum / values）；MoonBit 测试断言对齐它。
详见 [`interoperability/README.md`](interoperability/README.md)。

```bash
python interoperability/generate_fixtures.py           # 生成入库 fixture 集
python interoperability/generate_fixtures.py --check   # 校验未漂移（CI）
python interoperability/generate_fixtures.py --full    # §15 完整矩阵
```

## CLI Usage（§13）

`cmd/main/` 是薄可执行壳（只做两件事：`@fs` 读字节、设进程退出码），全部参数解析与输出
渲染都在纯库 `src/cli/`（不碰 IO，可被 `tests/cli_test.mbt` 黑盒覆盖）。

```bash
moon run cmd/main --target native -- inspect  tests/fixtures/f4_2x3_c_le_v1.npy
moon run cmd/main --target native -- validate tests/fixtures/f4_2x3_c_le_v1.npy
moon run cmd/main --target native -- dump     tests/fixtures/c8_4_c_le_v1.npy
moon run cmd/main --target native -- dump     tests/fixtures/f4_2x3_c_le_v1.npy --limit 3
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

`dump` 按 storage order 逐元素打印值，默认最多 10 个，`--limit N` 可调（`0` 合法，只留统计行）；
末尾恒为 `(showing K of N elements)`。两个例子（下方输出为 `moon run` 实测，与 CI 冒烟所 grep 的
一致）：

```text
NPY Dump: tests/fixtures/c8_4_c_le_v1.npy
──────────────────────────
[0] (0, 0)
[1] (1, 2)
[2] (2, 4)
[3] (3, 6)
(showing 4 of 4 elements)
```

```text
NPY Dump: tests/fixtures/f4_2x3_c_le_v1.npy
──────────────────────────
[0] 0
[1] 1
[2] 2
(showing 3 of 6 elements)
```

值走每个类型自己的 `to_string`，因此 **`Float` / `Double` 会省略尾随的 `.0`**——`1.0` 打印为
`1`，complex 打印为 `(1, 2)`。`dump` 覆盖全部 13 个元素级 dtype（表驱动证据测试
`dump_covers_all_13_dtypes` 的 pin 取自 NumPy Oracle）；它先把全量 payload 解码成内存数组
再截断，所以 `--limit` 省的是输出行数，不是内存——要在**库侧**限制解码出的元素数量，用 S4 的
`to_f32_chunk` / `to_f64_chunk`（`dump` 要覆盖 13 个 dtype，故仍走全量 accessor）。

**退出码纪律**：valid → 0；文件非法（任一 `NpyError`）→ 1；文件打不开 / 用法错误（包括
`--limit` 缺值或非数字）→ 2
（两类非 0 码互不混淆，便于脚本区分「坏文件」与「坏调用」）。

## Library API

核心层纯 `Bytes → 结构`，无文件系统 / CLI 依赖；失败一律 `Result[T, NpyError]`，绝不用 `Bool`
或裸 `String` 表达错误。公共接口（签名以源码为准）：

```moonbit
// src/format — magic / version / header-length 前缀
pub(all) enum NpyVersion { V1_0; V2_0; V3_0 }
pub struct NpyPrefix { version; major; minor; header_len : Int64; header_start; data_offset : Int64 }
pub fn parse_prefix(data : Bytes) -> Result[NpyPrefix, NpyError]
pub fn has_magic(data : Bytes) -> Bool

// src/header — 受限 Python-literal 头字典
pub struct NpyHeader { descr : String; shape : Array[UInt64]; fortran_order : Bool }

// src/dtype — descr → (DType, ByteOrder) + itemsize + 逐元素 codec
pub(all) enum DType { Bool; Int8; Int16; Int32; Int64; UInt8; UInt16; UInt32; UInt64; Float32;
                     Float64; Complex64; Complex128 }
pub(all) enum ByteOrder { Little; Big; NotApplicable; Native }
pub fn parse_dtype(descr : String) -> Result[(DType, ByteOrder), NpyError]
pub fn itemsize(dt : DType) -> Int
pub fn name(dt : DType) -> String
pub(all) struct Complex { re : Double; im : Double } // c8 / c16 的元素类型，分量统一 Double
pub fn read_c64(data : Bytes, off : Int, order : ByteOrder) -> Complex // 2 x f32 -> Double
pub fn read_c16(data : Bytes, off : Int, order : ByteOrder) -> Complex // 2 x f64

// src/reader — 校验 / 解码 / 类型化访问
pub struct NpyMeta { version; header; dtype; byte_order; element_count : Int64; data_offset : Int64; payload_len : Int64 }
pub struct NpyArray { version; header; dtype; byte_order; element_count : Int64; data : Bytes }
pub fn validate(data : Bytes) -> Result[NpyMeta, NpyError]
pub fn decode(data : Bytes) -> Result[NpyArray, NpyError]
pub fn NpyArray::to_f32(self) -> Result[Array[Float], NpyError]   // 另有 to_bool / to_i8…to_i64 /
pub fn NpyArray::to_f64(self) -> Result[Array[Double], NpyError]  // to_u8…to_u64（共 13 个全量 accessor）
pub fn NpyArray::to_c64(self) -> Result[Array[Complex], NpyError] // complex64（v0.2.0 S1）
pub fn NpyArray::to_c16(self) -> Result[Array[Complex], NpyError] // complex128（v0.2.0 S1）
pub fn NpyArray::to_f32_chunk(self, start : Int, len : Int) -> Result[Array[Float], NpyError]
pub fn NpyArray::to_f64_chunk(self, start : Int, len : Int) -> Result[Array[Double], NpyError]
// storage-order 窗口 [start, start + len)；越界 / 负值 → InvalidChunkRange（v0.2.0 S4）

// src/writer — 序列化回字节级对齐 np.save 的 NPY
pub fn encode(array : NpyArray) -> Result[Bytes, NpyError]

// src/cli — 纯参数解析 + 输出渲染（无 IO）
pub(all) enum Subcommand { Inspect; Validate; Dump(Int) }
pub(all) enum ExitCode { Success; Invalid; Operational }  // 0 / 1 / 2
pub fn parse_args(argv : Array[String]) -> Result[(Subcommand, String), String]
pub fn run_inspect(path : String, data : Bytes) -> CliOutcome
pub fn run_validate(path : String, data : Bytes) -> CliOutcome
pub fn run_dump(path : String, data : Bytes, limit : Int) -> CliOutcome  // 全 13 个 dtype（v0.2.0 S5）
pub fn render_error(e : NpyError) -> String

// src/error — 13 个结构化错误构造子
pub(all) enum NpyError {
  InvalidMagic; UnsupportedVersion(Int, Int); TruncatedHeader; InvalidHeaderLength
  InvalidHeaderSyntax; MissingHeaderField(String); InvalidDType(String); UnsupportedDType(String)
  ShapeOverflow; DataLengthMismatch(Int64, Int64); UnsupportedObjectArray
  InvalidByteOrder(Byte); InvalidChunkRange(Int, Int)
}
```

整数 accessor 的 MoonBit 类型映射（受 32 位 `Int` 约束，§9.2）：`i8/i16/i32 → Array[Int]`、
`i64 → Array[Int64]`、`u8/u16 → Array[Int]`、`u32 → Array[Int64]`（`0..2³²-1` 装不进 32 位 `Int`，
加宽）、`u64 → Array[UInt64]`。complex accessor 返回 `Array[Complex]`，两种宽度同一元素类型，
由 `arr.dtype`（`Complex64` / `Complex128`）区分字节来自 2 × f32 还是 2 × f64。

## Ecosystem Adapter

S6 接上「`.npy` → 多维数组库」这条最后一公里：`src/adapter/moonnum/` 依赖
`amor2025/moonNum@0.1.0`（纯 MoonBit，无 C / BLAS —— 选型 go/no-go 与全部实测数据见
[`docs/s6-api-card.md`](docs/s6-api-card.md)），把 moon-npy 解析好的 `NpyArray` 交给 moonNum 的
`NdArray`。**不解码任何元素**：载荷字节、`shape`、`fortran_order` 这三个事实两边的数组模型完全
一致，reshape 只是 `NdArray::from_buffer` 内部的字节步长算术，`Bytes::to_array()` 是整个管线上
唯一一次元素级拷贝。

```moonbit
// src/adapter/moonnum — 读方向，float32 / float64 only
pub(all) enum AdapterError {
  UnsupportedDType(String) // descr 不是 f4 / f8
  BigEndianNotSupported(String) // moonNum 的缓冲模型只有小端（card §3.6）
  ShapeDimensionTooLarge(UInt64) // 维度装不进 32 位 Int：拒绝，不截断
}
pub fn AdapterError::message(self : AdapterError) -> String
pub fn to_moonnum_f32(arr : @reader.NpyArray) -> Result[@core.NdArray, AdapterError]
pub fn to_moonnum_f64(arr : @reader.NpyArray) -> Result[@core.NdArray, AdapterError]
```

用法（与 `tests/adapter_test.mbt` 同源，CI 实跑；`@moonnum` 是
`"ShunjunGu/moon-npy/src/adapter/moonnum"` 在 `moon.pkg` 里的默认别名）：

```moonbit
let data = @fs.read_file_to_bytes("tests/fixtures/f4_2x3_c_le_v1.npy").unwrap()
let arr = @reader.decode(data).unwrap()
let nd = @moonnum.to_moonnum_f32(arr).unwrap()
nd.shape() // => [2, 3]
nd.strides() // => [12, 4] —— 字节步长，与 NumPy 的 (12, 4) 直接可比
nd.get_f32(4) // => 4.0
```

三条边界各有一条测试钉住（全部用真实 Oracle fixture 或合成 header，不是臆造数据）：

- **big-endian 拒绝**：`f8_4_c_be_v1.npy`（`>f8`）moon-npy 能正常解码，适配器返回
  `BigEndianNotSupported(">f8")` —— 递给 moonNum 只会得到「看起来合理」的错值，因为它的
  `is_little_endian()` 是字面量 `true`。
- **dtype 拒绝**：`i4_4_c_le_v1.npy`（`<i4`）→ `UnsupportedDType("<i4")`；两个入口各自声明自己的
  dtype 前置条件（`to_moonnum_f64` 收到 `<f4` 同样拒绝），且 dtype 门在字节序门之前。
- **shape 收窄拒绝**：`(1099511627776, 0)`（2⁴⁰ × 0）元素乘积为 0，`reader` 的 Int64 溢出校验
  放行，但维度装不进 `Int` → `ShapeDimensionTooLarge(1099511627776UL)`。

失败类型故意 **不是** `NpyError` 的新变体：那是 `pub(all) enum`，加变体会打破 `src/cli/render_error`
的穷举 match（S4 踩过），而且这些都不是「`.npy` 文件本身有问题」——字节是合法 NPY，只是适配器
无法在 moonNum 的模型里表达它。写方向（`NdArray → .npy`）与非 native 目标下的适配留给 v0.3。

## Architecture

数据流与模块依赖（每层只依赖其上游，`cli` 纯逻辑、`cmd/main` 是唯一碰 IO 的薄壳）：

```text
  Bytes  (来自 @fs.read_file_to_bytes 或内存)
    │
    ▼
  format    magic · version · header-length 前缀        ──►  NpyPrefix
    │
    ▼
  header    lexer + 受限 Python-literal parser          ──►  NpyHeader { descr, shape, fortran_order }
    │
    ▼
  dtype     descr → (DType, ByteOrder) · itemsize · codec
    │
    ├──►  reader.validate(Bytes) → NpyMeta        （只校验，不解元素）
    ├──►  reader.decode(Bytes)   → NpyArray → to_f32() / to_i64() / …  （惰性类型化访问）
    │                              └─ to_f32_chunk(start, len) / to_f64_chunk：storage-order 窗口（S4）
    └──►  writer.encode(NpyArray) → Bytes         （字节级对齐 np.save）

  adapter/moonnum  NpyArray → moonNum NdArray（S6，读方向，f32/f64 LE；失败用适配器自己的 AdapterError）

  error     enum NpyError（13 构造子）贯穿所有层的 Result 失败通道
  cli       parse_args · run_inspect · run_validate · run_dump · render_error（纯逻辑，可黑盒测试）
    │
    ▼
  cmd/main  薄壳：@fs 读字节 + extern "c" exit 设退出码（唯一 IO 边界）
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
│   ├── cli/               # inspect / validate / dump 纯逻辑（parse_args + 渲染，无 IO）
│   └── adapter/moonnum/   # S6 读方向适配 amor2025/moonNum（本仓唯一第三方依赖）
├── cmd/main/              # CLI 可执行薄壳（@fs 读字节 + extern "c" exit 设退出码）
├── tests/                 # *_test.mbt（128，含 edge / fuzz / security / property / adapter）+ fixtures/（*.npy + expected.json）
├── interoperability/      # generate_fixtures.py / verify_moonbit_output.py / roundtrip.py
├── examples/roundtrip/    # emit harness（decode -> encode -> write，`moon run`）
└── .github/workflows/     # ci.yml（§19：fmt/check/test/coverage/fixture/round-trip）
```

## Limitations

范围控制是本项目的第一原则（§5「明确不做什么」）。v0.1.0 有意不实现下列能力；v0.2.0 只新增四项
——complex64 / complex128 读取（S1）、CLI `dump [--limit N]`（S5）、storage-order 窗口读取（S4）、
moonNum 读方向适配（S6）——其余范围未扩大：

- **不是 NumPy**：无线性代数 / FFT / 广播 / 矩阵运算，无 Tensor framework / 自动微分 /
  模型加载（PyTorch 等）。moon-npy 只做 `.npy` 二进制**序列化 / 反序列化**。
- **不做其他格式**：GGUF / SafeTensors / Parquet / **NPZ**（NPZ = ZIP 容器 + 多 NPY，属
  Stretch，不作比赛核心交付）。
- **dtype 范围**：13 个 dtype —— 11 种 primitive numeric + complex64 / complex128（见
  Compatibility Matrix）。**object dtype 主动拒绝**；half / longdouble / complex256 / bytes /
  str / void / structured / datetime / timedelta 识别后返回 `UnsupportedDType`（结构化，非崩溃）。
- **不自动 reshape**：accessor 返回 storage-order **扁平** `Array[T]` + `shape` / `fortran_order`
  metadata，由消费方自行 reshape 成 N-D（保持核心小而完整）。
- **encode 的前置条件**：`writer.encode` 只重序列化 `reader.decode` 得到的 `NpyArray`
  （payload 原样透传、header 按 NumPy 文本形式重建）；「从任意 typed array 构造 NPY」为预留能力。
- **单文件、全内存**：一次性读入整个 `Bytes` 后解析，**没有跨文件 I/O 的 streaming**（不会边读磁盘
  边解码）。v0.2.0 S4 的 `to_f32_chunk` / `to_f64_chunk` 只把**输出数组**限到一个窗口，payload
  本身仍全部驻留内存；真正的按页惰性读（mmap / 文件 seek）不在本轮范围。
- **适配器只单向、只两 dtype**：S6 只做读方向（`NpyArray → NdArray`）与 float32 / float64
  小端；写方向、complex 与整数适配、以及 moonNum 在非 native 目标上的可用性都在 v0.3 之外。

## Security

NPY object arrays carry Python pickle payloads — loading one can execute
arbitrary code (the risk NumPy itself documents, and the reason SafeTensors
exists). moon-npy is secure **by construction**, not by filtering:

- **No pickle interpreter.** The codebase is pure MoonBit: there is no Python
  runtime, no FFI, and no mechanism to invoke one. The only IO in the module is
  reading bytes via `@fs` in `cmd/main`.
- **Object arrays are refused at the dtype layer.** Every endian form of the
  object descr (`|O`, `<O`, `>O`) is rejected with a structured
  `UnsupportedObjectArray`, independently of `shape` and *before* any payload
  byte is interpreted; void dtypes are refused the same way (`|V8` →
  `UnsupportedDType`). Pinned by `tests/security_test.mbt`.
- **Totality over arbitrary input.** The deterministic fuzz suite (7000
  iterations, fixed seeds) proves that *any* byte sequence returns `Ok` or a
  structured `NpyError` — never a trap, an out-of-bounds read, or an execution
  path.

Scope, stated honestly: moon-npy does not parse object or structured arrays, so
"safe" here means *these attack surfaces do not exist in this library* — not a
general sandbox. Files with unsupported dtypes fail loudly, with the exact error
variant, and never partially.

Mechanics backing those claims (all exercised by `moon test`):

- **Overflow-guarded arithmetic (§9.2 / B2)**: MoonBit `Int` is 32-bit and
  wraps, so shape products, `element_count` and byte counts are held in
  `Int64` / `UInt64` with a check at every step → `ShapeOverflow`, never a
  silently truncated allocation size.
- **Strict payload reconciliation**: `element_count * itemsize` must equal the
  bytes actually present, else `DataLengthMismatch(expected, actual)`;
  accessors step over an already-validated payload, so an out-of-bounds read is
  arithmetically impossible.
- **Bounds-safe descr parsing**: `String::get_char` returns `None` past the end
  → `InvalidDType` instead of trapping; a short buffer → `TruncatedHeader`.

## Development

前置：**MoonBit `0.1.20260827`**（pinned）、native target；跨语言测试另需 **NumPy `2.3.4`** /
**Python `3.14`**。工具链事实与语法约定以 [`AGENTS.md`](AGENTS.md) 为**权威**（M0 实测固化，
禁止基于旧假设臆写）。

**提交前三门**（CI 同款，全绿方可提交）：

```bash
moon fmt                                   # 格式化（CI 用 git diff --exit-code 强制无改动）
moon check --target native                 # 类型检查
moon test --target native                  # 128 个单元测试
```

**覆盖率**（CI 强制阈值门禁：core parser ≥90% / overall ≥80%，未达即失败）：

```bash
moon test --target native --enable-coverage; moon coverage analyze
moon coverage report -f summary            # 当前 core parser 98.5%、overall 91.7%
```

**跨语言互操作**（需 NumPy / Python）：

```bash
python interoperability/generate_fixtures.py --check   # fixture 未漂移
python interoperability/roundtrip.py                   # 31 fixture 字节级 round-trip
```

**约定**：核心层用 `enum NpyError` + 内建 `Result`（不用异常表达失败）；长度 / 偏移一律 `Int64`
纪律；黑盒测试文件以 `_test.mbt` 结尾、用 `@pkg.` 前缀访问公共 API、test-only 依赖写进 `moon.pkg`
的 `import { … } for "test"`；每个顶层块前用 `///|` 分隔（`moon fmt` 会规整）。

**里程碑**：M0（工具链 gate）→ M1（header）→ M2（dtype+reader）→ M3（writer）→ M4（round-trip）
→ CLI → M5（edge/fuzz/coverage），见 Status 表；每个里程碑一个规范 commit，`CHANGELOG.md` 记录。
**Feature Freeze（9/22）** 后仅接受 bug fix / tests / docs / compatibility fix / CLI UX / packaging。

## CI

[`.github/workflows/ci.yml`](.github/workflows/ci.yml)（§19）在 `ubuntu-latest` 上 pin
MoonBit `0.1.20260827+d0aaa07` / NumPy `2.3.4` / Python `3.14`，依次跑：`moon fmt`（无 diff）
→ `moon check` → `moon test` → coverage（**强制阈值门禁**：core parser ≥90% / overall ≥80%，未达
即失败）→ fixture `--check` → `roundtrip.py`（31 fixture emit + verify + byte-exact）→ CLI 冒烟
（inspect / validate / dump + 退出码 0/1/2，含 `--limit` 截断与坏 `--limit` → 2）。README 展示的
例子即 CI 实际运行的例子（§19 铁律）。

## License

Apache-2.0 — see [`LICENSE`](LICENSE).

---

_Built for the 2026 MoonBit 国产基础软件生态开源大赛 · 9 月黑客松。_
_设计原则：NPY first / Correctness first / Interop first / Tests first / Small but complete._
