# S6 API card：第三方数组库选型与 go/no-go 决策

> 主计划 `docs/plans/2026-09-09-moon-npy-v0.2.0-stretch.md` Task 12 的唯一交付物。
> 决策日期：**2026-09-10**（计划排期 9/15，提前 5 天）。
> 工具链：`moon version` = **0.1.20260827**（同 AGENTS.md §0，一切以实测为准）。
> 本文档只记录**已验证**事实；每条签名都从**编译通过**的 scratch 代码里抄，不做记忆推断。

## 1. 结论（go/no-go）

| 候选 | 模块路径 @ 版本 | `check` | `test`（native） | 判定 |
| --- | --- | --- | --- | --- |
| moonNum | `amor2025/moonNum@0.1.0` | **0** | **0**（1/1 passed） | **GO — S6 唯一实现目标** |
| numbt | `mizchi/numbt@0.2.4` | 0 | **1（失败）** | **NO-GO**（§4） |

计划 Step 3 的规则是「只有一个可用 → 只做那一个」，故 **v0.2.0 的 S6 = moonNum 读方向适配器，不做多目标抽象层**。备选池（§5）只作为记录，不进实现。

## 2. 调研方法（可复现）

`mooncakes.io` 网页直连超时，因此**不依赖网页**，改用两条本机可达的权威路径：

1. **本地 registry index**：`$HOME/.moon/registry/index/user/<owner>/<module>.index`，
   每行一个版本的 JSON（含 `version` / `deps` / `license` / `repository` / `created_at`）。
   该 git 仓库最新提交 **2026-09-07**，共 2363 个条目 —— 版本、license、依赖、发布时间一律从这里取。
2. **`moon search <q>`**：确认 registry 实际可达（退出码 0），并扩出候选全景。

检索词（Step 1 全量）：`numbt`、`moonNum`、`num`、`array`、`ndarray`、`tensor`、`matrix`。
下载后用 `.mooncakes/` 里的**真实包源**（`moon.pkg` 链接配置 + `.mbt` 签名 + 上游 README）做判定。

## 3. 选定模块：`amor2025/moonNum@0.1.0`

### 3.1 元数据（registry index 原文）

- 版本 **0.1.0**，发布 **2026-07-06**（该模块至今仅此一版）
- license **Apache-2.0**
- 依赖：`moonbitlang/x@0.4.46`
- `repository` = **空串**（上游未登记仓库地址）
- 描述：「NumPy 的 Moonbit 移植 —— 多维数组、线性代数、FFT、随机数」
- 子包：`src/{core,dtypes,io,linalg,fft,random,lib,ma,matrixlib,polynomial,datetime,exceptions,typing,zlib,char,constants}`

### 3.2 依赖共存（已验证，非推断）

`moon add moonbitlang/x@0.5.1` + `moon add amor2025/moonNum` 后 `moon tree`：

```
username/s6probe@0.1.0 (local ...):
├─ amor2025/moonNum -> amor2025/moonNum@0.1.0
│  └─ moonbitlang/x -> moonbitlang/x@0.5.1
└─ moonbitlang/x -> moonbitlang/x@0.5.1
```

moonNum 声明的下界 `x@0.4.46` 被本仓已用的 `x@0.5.1` 满足，解析成**单一** 0.5.1，
**不引入第二份 `x`**，也不要求本仓降级。

### 3.3 可移植性（Step 2 的硬证据）

全量扫描 moonNum 的 `moon.pkg` 与 `.mbt`：

- `supported_targets`：**0 处**
- `native-stub` / `cc-link-flags` / `wasmpath`：**0 处**
- `extern "c"`：**0 处**

⇒ **纯 MoonBit，无 C FFI**，与 numbt 相反。本仓 CI 的 `runs-on: ubuntu-latest` 与
`moon test --target native` 门禁无需任何系统包（zlib/npz 也是自带 MoonBit 实现）。

### 3.4 精确 API 签名（从 `moon check`+`moon test` 通过的 scratch 代码抄）

外部消费者在 `.mbt` 里**不能**写文件级 `import`（本 pin 报 `[3001] Invalid import
declaration here. Move this declaration to 'moon.pkg'`），导入必须写进包的 `moon.pkg`；
跨包引用统一用 `@alias.` 前缀（类型位置、函数调用位置都是）。

`moon.pkg`：

```toml
import {
  "amor2025/moonNum/src/core",
  "amor2025/moonNum/src/dtypes",
}
```

数组类型与构造（`src/core/core.mbt`）：

```moonbit
pub struct NdArray { data : Array[Byte], dtype : @dtypes.Dtype,
                     shape : Array[Int], strides : Array[Int], offset : Int }
// 字段非 pub：对本包外部只读不可写，只能走下面的公开访问器。

pub(all) enum Order { C F }

pub fn NdArray::from_buffer(
  data : Array[Byte], dtype : @dtypes.Dtype,
  shape : Array[Int], order : Order,
) -> NdArray

pub fn NdArray::new(
  data : Array[Byte], dtype : @dtypes.Dtype,
  shape : Array[Int], strides : Array[Int], offset : Int,
) -> NdArray
```

本仓用到的访问器（全部实测可调）：

```moonbit
pub fn NdArray::ndim(self : NdArray) -> Int
pub fn NdArray::size(self : NdArray) -> Int
pub fn NdArray::itemsize(self : NdArray) -> Int
pub fn NdArray::shape(self : NdArray) -> Array[Int]
pub fn NdArray::strides(self : NdArray) -> Array[Int]
pub fn NdArray::get_f32(self : NdArray, linear_idx : Int) -> Double
pub fn NdArray::get_f64(self : NdArray, linear_idx : Int) -> Double
pub fn NdArray::is_little_endian(self : NdArray) -> Bool   // 见 §3.6
```

`@dtypes.Dtype` 相关变体：`Float32` / `Float64`（另有 `Float16`、`Int8..Int64`、
`Uint8..Uint64`、`Bool`、`Complex64` / `Complex128`、`Datetime64`、`Str_`）。
**注意本仓适配器只用 `Float32` / `Float64`**（§3.5）。

`NdArray::strides` 是**字节步长**（NumPy 约定），不是元素步长 —— 这一点直接决定了
它和 NPY header 的 `fortran_order` 语义可以一一对应。

### 3.5 读方向转换设计（`NpyArray -> NdArray`，v0.2 唯一方向）

本仓 `NpyArray`（`src/reader/reader.mbt`）已经携带适配器需要的全部输入：

```moonbit
pub struct NpyArray {
  version, header, dtype : ..., byte_order : @dtype.ByteOrder,
  element_count : Int64,
  data : Bytes,   // 只含 payload（已按 data_offset 切好）
}
```

转换管线（Task 13 的实现契约）：

1. **dtype 映射**：只接受 `@dtype.DType` 的 `Float32 -> @dtypes.Dtype::Float32`、
   `Float64 -> @dtypes.Dtype::Float64`；其余 11 个 dtype（含 S1 的 complex）返回结构化
   错误。理由：moonNum 的 `Dtype::Float32` 对应的 `get_f32` 返回 `Double`（已加宽），
   而本仓对 complex 的表示是单一 `Complex` 结构，两侧模型不同，**不做一次性铺开**（YAGNI，
   与 S4 只开 f32/f64 窗口访问器同一尺度）。
2. **shape 映射**：`header.shape : Array[UInt64]` → `Array[Int]`。必须过 `element_count`
   （已是 `Int64` 且经 §12 溢出校验）再逐维 `to_int()`；任何一维超出 `Int` 可表示范围 →
   结构化错误，**不截断**（§21：不臆造行为）。0-d（`shape == []`）按 `[]` 传递，
   moonNum 的文档明确 `[]` 即 0-D 标量，与本仓语义一致。
3. **字节序**：只接受 `ByteOrder::LittleEndian` / `Native`（在 x86/ARM 上即 LE）。
   **big-endian 一律拒绝**，理由见 §3.6。
4. **storage order**：`header.fortran_order == false -> @core.Order::C`，
   `true -> @core.Order::F`。这正是 `from_buffer` 的存在意义 —— 它按 order 自动算字节步长，
   与本仓「payload 原样、顺序由 header 决定」的模型完全同构。
5. **载荷传递**：`arr.data.to_array()`（core `Bytes::to_array : Bytes -> Array[Byte]`）
   后交给 `from_buffer`。**这是全流程唯一一次元素级拷贝**；`from_buffer` 自身共享缓冲区、
   只拷贝 `shape`，不做逐元素解码。
6. **返回**：`Result<@core.NdArray, AdapterError>`。

写方向（`NdArray -> .npy` 字节）**明确推迟到 v0.3**，不在 v0.2 的任何 API、README 或
CHANGELOG 里出现「支持写」的字样 —— moonNum 自己有 `to_npy_bytes`，但那是它的实现，
不是本仓的承诺；本仓的字节级 round-trip 保证只覆盖 §「decode → encode 逐字节恒等」这条
已有性质测试的链路。

### 3.6 一处必须诚实标注的 moonNum 局限

```moonbit
pub fn NdArray::is_little_endian(self : NdArray) -> Bool {
  let _ = self
  true
}
```

`is_little_endian()` 的实现是**字面量 `true`**（`src/core/core.mbt:359`）—— moonNum 的
字节缓冲模型只有小端一种，`Dtype` 里也没有字节序维度。这**不是** bug 报告，而是本适配器
必须遵守的边界：把 big-endian 的 `.npy` payload 原样交给 `from_buffer` 会读出**字节序倒置的
错误数值**（例如 `f8_4_c_be_v1.npy` 会静默变成一堆天文数字），而不是报错。故 §3.5 第 3 步
把 BE 拒绝做成硬性前置检查，并作为适配器测试的一条用例（用真实的 BE fixture 驱动）。

### 3.7 生态位交叉（必须公开的事实）

moonNum 自带 npy 读写：`src/io/save_load.mbt` 导出 `to_npy_bytes`、`from_npy_bytes`、
`load`、`load_npz`、`load_bytes`。因此它既是 S6 的**目标库**，也是本仓的**同生态位实现**。
本仓的差异点从来不是「能读 .npy」，而是 **NumPy 2.3.4 产物作为 Oracle 的字节级恒等纪律**
（31 个 fixture、`decode → encode` 逐字节性质测试、`roundtrip.py` 跨语言校验、
`|O` 安全前置拒绝）。S6 的 README 段落**不得**把 moonNum 说成「不能读 npy 的数组库」，
也不得宣称本仓适配器取代它 —— 措辞按 §3.5 收窄为「把 moon-npy 解析出的数组交给
moonNum 做后续数值计算」。

## 4. 被拒候选：`mizchi/numbt@0.2.4`

`moon check --target native` **通过**（类型层可用），但 `moon test --target native`
**失败（退出码 1）**，卡在 C native-stub 编译：

```
.mooncakes/mizchi/blas/src/blas_stub.c(13): fatal error C1083:
    cannot open include file: 'cblas.h': No such file or directory
.mooncakes/mizchi/numbt/src/numbt_stub.c(15): fatal error C1083:
    cannot open include file: 'cblas.h': No such file or directory
```

三条独立理由，任一单独成立即足以 no-go：

1. **链接/构建需要系统 BLAS**：`src/moon.pkg` 声明
   `supported_targets = "native"`、`"native-stub": ["numbt_stub.c"]`、
   `"cc-link-flags": "-framework Accelerate"`（Apple 专属）。上游 README 自述
   「Built on BLAS (Apple Accelerate)」，Linux 需 `sudo apt-get install libopenblas-dev
   liblapack-dev`，并**要求消费者自行按平台改 `moon.pkg` 的链接 flag**。本仓 CI 是
   `ubuntu-latest`（`.github/workflows/ci.yml`），把外部 C 库依赖和一个 macOS flag 引进来
   会直接破坏「clone 下来 `moon test` 就能跑」的交付纪律。
2. **数据模型承载不了本仓的输入**：`pub struct Mat { data : Array[Float]; rows; cols }`
   只有 **f32、只有 2-D**（且字段非 `pub(all)`，外部既不能构造也不能读回），
   既无法表示 `to_f64_chunk`，也无法表示 3-D 与 0-d fixture。
3. **失败模式与本仓 totality 纪律冲突**：`vec_check_range` / `mat_check_shape` 等校验
   一律 `panic()`，而本仓核心层恒返 `Result[T, NpyError]`（§18）。

另：numbt 自己 README 的 Security 段称「代码库是纯 MoonBit —— 没有 FFI」，
与 `native-stub` + `extern "C" fn numbt_*` 的事实不符；本仓不据此库的自述做判断。

## 5. 其它被观测但未纳入 gate 的候选（仅记录）

| 模块 @ 版本 | 备注 |
| --- | --- |
| `Ankaluoer/moon-tensor@0.1.0` | NN 推理算子向，无 deps；不是通用多维数组容器 |
| `tonyfettes/narray@0.1.0` | 2024-09-29 发布，无描述、无 repository，判定为 stale |
| `walkzzz/owl_mbt@0.1.1` | Owl 移植，明确「no C FFI」；范围远大于数组，v0.2 不动 |
| `tonyfettes/torch@0.2.8` | 绑定向，引入外部依赖面 |
| `Luna-Flow/linear-algebra@0.4.7`、`AdUhTkJm/nummoon@0.2.3`、`oboard/numoon@0.4.1` | 未做 gate（计划 gate 只点名 numbt / moonNum） |

## 6. Task 13 的落地约束（照此实现即为机械活）

- 目录：`src/adapter/moonnum/{moon.pkg, adapter.mbt}`，包内 import
  `ShunjunGu/moon-npy/src/{reader,dtype,error}` + `amor2025/moonNum/src/{core,dtypes}`。
- **不动 `NpyError`**：`pub(all) enum` 加变体会立刻打破 `src/cli/render_error` 的穷尽
  match（S4 已踩过一次，见 CHANGELOG）。字节序/dtype/shape 的转换失败属于**转换层**限制，
  不是 .npy 格式错误，故在适配器包内定义自己的 `pub(all) enum AdapterError`。
- `moon.mod` 增加 `amor2025/moonNum@0.1.0` 依赖；`moon test` 门禁继续 `--target native`
  （moonNum 无 target 限制，见 §3.3）。
- 测试至少覆盖：f32 与 f64 各一条（值与 `shape`/`strides` 逐条对齐）、
  C 与 F order 各一条、0-d 一条、**big-endian 被拒一条（用真实 `f8_4_c_be_v1.npy`）**、
  非 f32/f64 dtype 被拒一条。README 只展示其中 CI 真跑过的（§19）。

## 7. 本任务的工具链事实（回填 AGENTS.md 的候选）

- `moon init` 在本 pin **不存在**（`no such subcommand: 'init'`），脚手架命令是
  **`moon new <PATH> --user <u> --name <n>`**。
- 本 pin 用 **TOML 清单**：`moon.mod` / `moon.pkg`（不是 `.json`）。
- `.mbt` 文件级 `import` 非法（`[3001]`），必须写进 `moon.pkg`。
- C 风格 for 的步进子句只接受赋值：`for i = 0; i < n; i = i + 1`，写 `i += 1` 触发
  `[3002] Parse error, unexpected token '+=', you may expect '='`。
- 整数字面量后直接接方法调用会被解析成浮点：`0.to_byte()` 报 `[3002]`，需写
  `(0).to_byte()` 或改走 `Array::new()` + `push`。
- `Array` 在本 pin **没有 `create` 方法**（`[4015] Type Array has no method create`），
  定长初始化用 `Array::make(len, init)`。
