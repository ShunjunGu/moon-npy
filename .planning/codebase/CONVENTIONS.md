# Coding Conventions

**Analysis Date:** 2026-09-11

> 权威来源：`AGENTS.md`（仓库自带的 **M0 实测固化** 约定文档，2026-09-07 gate，工具链 `moon 0.1.20260827`）与
> 仓库内 spec owner `docs/spec/acceptance.md`。本文中每条约定都对照真实源码验证，并给出出处与代码示例。
> 引用形如「AGENTS.md §N」/「§N」均指这两份文件的小节号。

## Naming Patterns

**Files:**
- 源文件一律 **snake_case**：`src/error/error.mbt`、`src/format/format.mbt`、`src/header/lexer.mbt`、
  `src/header/parser.mbt`、`src/dtype/codec.mbt`、`src/dtype/endian.mbt`、`src/reader/reader.mbt`、
  `src/writer/writer.mbt`、`src/npz/npz.mbt`、`src/cli/cli.mbt`。
- 包清单 = **`moon.pkg`**（包级），模块清单 = **`moon.mod`**（模块级）——**均无 `.json` 后缀**，
  TOML-like 语法，`//` 注释（AGENTS.md §1；早期计划把二者"订正"为 `moon.mod.json` / `moon.pkg.json`
  属错误，已作废）。
- 接口快照 = `pkg.generated.mbti`，由 `moon info` 生成，首行为
  `// Generated using `moon info`, DON'T EDIT IT`，且被 `.gitignore` 忽略 —— **禁止手改**。
- 测试文件集中在仓库根 `tests/` 单包内，命名 `<topic>_test.mbt`（blackbox，用 `@pkg.` 前缀访问公共 API）。
  白盒形态 `*_wbtest.mbt` 在当前工具链下存在（AGENTS.md §7），但**本仓库未写任何一个**。
- 目录名在 adapter 处用嵌套包路径 `src/adapter/moonnum/`，与包名 `moonnum` 对应。

**Functions:**
- 一律 **snake_case**，无 async 前缀（MoonBit 核心层无 async）。
- 按动词前缀形成一族命名：
  - `parse_*` —— 解析入口：`parse_prefix`、`parse_header`、`parse_dtype`、`parse_byte_order`、`parse_args`、`parse_limit`
  - `read_*` —— 字节级取数：`read_u16_le`、`read_u32_le`、`read_bits32`、`read_bool`、`read_i8` … `read_c16`
  - `to_*` —— 类型化访问器：`to_bool`、`to_i8` … `to_c16`、`to_f32_chunk`、`to_f64_chunk`、`to_int`
  - `render_*` —— 纯字符串渲染：`render_error`、`render_inspect`、`render_dump`、`render_failure`、`render_all`
  - `is_*` / `has_*` —— 布尔谓词：`is_space`、`is_digit`、`is_ident_start`、`is_ident_char`、`is_big`、
    `is_known_unsupported_kind`、`is_digits`、`has_magic`、`unsafe_member_name`
  - `run_*` —— 命令执行体：`run_inspect`、`run_validate`、`run_dump`
- 方法用 `Type::method` 形式定义（定义在包内、类型所属包）：
  ```moonbit
  pub fn NpyArray::to_i8(self : NpyArray) -> Result[Array[Int], @error.NpyError] { … }   // src/reader/reader.mbt
  pub fn ExitCode::to_int(self : ExitCode) -> Int { … }                                  // src/cli/cli.mbt
  pub fn NpzArchive::get(self : NpzArchive, key : String) -> Result[NpzMember, @error.NpyError] { … }  // src/npz/npz.mbt
  pub fn AdapterError::message(self : AdapterError) -> String { … }                      // src/adapter/moonnum/adapter.mbt
  ```
- 带断言的测试 helper 必须标 `raise`：`fn check_total(blob : Bytes) -> Unit raise`（`tests/fuzz_test.mbt:49`）、
  `fn expect_dtype(…) -> Unit raise`（`tests/dtype_test.mbt:12`）——因为 `assert_eq` / `assert_true` 带
  error effect，只能在 `test` block 内直接调用。

**Variables:**
- 常量一律 **snake_case 小写**（**不是** UPPER_SNAKE_CASE），并**显式标注类型**：
  ```moonbit
  pub let magic_len : Int = 8                              // src/format/format.mbt
  let array_align : Int = 64                               // src/writer/writer.mbt
  let label_width : Int = 14                               // src/cli/cli.mbt
  let default_dump_limit : Int = 10                        // src/cli/cli.mbt
  let int64_max : Int64 = 0x7FFFFFFFFFFFFFFFL              // src/reader/reader.mbt
  let uint64_max : UInt64 = 0xFFFFFFFFFFFFFFFFUL           // src/reader/reader.mbt
  let int_max_as_uint : UInt64 = 0x7FFFFFFFUL              // src/adapter/moonnum/adapter.mbt
  ```
  （UPPER_SNAKE_CASE 只出现在 Python 侧脚本，如 `interoperability/generate_fixtures.py` 的
  `MAGIC_PREFIX` / `MAGIC_LEN` / `ARRAY_ALIGN`，与本仓库 MoonBit 侧约定不同。）
- 数值字面量后缀是强约定：`Int64` 用 `L`（`128L`、`24L`、`1000000` 不带）、`UInt64` 用 `UL`（`0UL`、`4UL`、`0x5EEDUL`）。
- 可变局部变量用 `let mut`（`let mut acc = 0UL`、`let mut p = 0`）；循环游标惯用
  `i` / `j` / `k`（元素）、`pos` / `p`（token 游标）、`o` / `off` / `base`（字节偏移）、`u`（单位级别）。
- **私有标记：无下划线前缀**。私有性由 `fn`（无 `pub`）或 `priv` 关键字表达，不靠命名：
  - 包私有函数：`fn read_uint`、`fn sext`、`fn lex`、`fn parse_tokens`、`fn shape_element_count`、`fn slice_payload`
  - 显式私有类型：`priv enum Token { LBrace … }`（`src/header/lexer.mbt:13`）
- 局部变量遮蔽在 `let (dtype, byte_order) = parsed` 这类解构中常见（`src/reader/reader.mbt:98`）。

**Types:**
- 结构体 / 枚举一律 **PascalCase，无前缀**：`NpyError`、`DType`、`ByteOrder`、`NpyVersion`、`NpyPrefix`、
  `NpyHeader`、`NpyMeta`、`NpyArray`、`NpzArchive`、`NpzMember`、`Subcommand`、`ExitCode`、`CliOutcome`、
  `AdapterError`、`Complex`、`Token`。
- 枚举构造子 **PascalCase**（无 payload）：`InvalidMagic`、`TruncatedHeader`、`ShapeOverflow`、
  `V1_0`/`V2_0`/`V3_0`、`Bool`/`Int8`/…/`Complex128`、`Little`/`Big`/`NotApplicable`/`Native`、
  `Success`/`Invalid`/`Operational`、`Inspect`/`Validate`。
- 带 payload 构造子 **PascalCase(Type, …)**，payload 类型注释写在 enum 定义旁：
  ```moonbit
  pub(all) enum NpyError {
    UnsupportedVersion(Int, Int)
    MissingHeaderField(String)          // descr / fortran_order / shape absent
    DataLengthMismatch(Int64, Int64)    // (expected, actual)
    InvalidByteOrder(Byte)
    InvalidChunkRange(Int, Int)         // (start, length) out of range / negative (S4)
    NpzBadStructure(String)
  } derive(Debug)                        // src/error/error.mbt
  ```
  ```moonbit
  pub(all) enum Subcommand { Inspect; Validate; Dump(Int) }  // Dump 携带已解析的 --limit
  pub(all) enum AdapterError { ShapeDimensionTooLarge(UInt64) }  // src/adapter/moonnum/adapter.mbt
  ```
- 可见性是个**有意的三层梯度**，且源码注释解释了理由：
  | 写法 | 语义 | 用途 | 实例 |
  |---|---|---|---|
  | `pub` | 公共 API | 稳定导出面 | `decode`、`encode`、`parse_dtype`、`decode_npz`、`render_error` |
  | `pub(all)` | 公共且**可跨包构造** | 测试需要构造变体而不只是 match | `NpyError`、`DType`、`ByteOrder`、`NpyVersion`、`Subcommand`、`ExitCode`、`AdapterError`、`Complex` |
  | `pub struct` | 字段可读、**外部不可构造** | 只读数据载体 | `NpyHeader`、`NpyMeta`、`NpyArray`、`NpzArchive`、`CliOutcome` |
  | `fn` / `priv enum` | 包私有 | 内部实现 | `read_uint`、`lex`、`Token`、`slice_payload` |
  - 出处：`src/cli/cli.mbt:12-13`「`pub(all)` (like DType / ByteOrder / NpyError) so tests can construct
    the variants, not just match them」；`src/reader/reader.mbt:7-10`「NpyHeader is a `pub struct` in the
    header package, so this package can read its fields … but must not construct it」；
    `src/cli/cli.mbt:44-48`「A `pub struct` from another package can have its fields read but not be
    constructed there, so cmd/main builds an operational outcome via `operational()` rather than a record literal」。
- `derive` 属性只在需要时加，且**组合固定**：
  - `derive(Debug)` —— 单用（`NpyError`、`CliOutcome`）
  - `derive(Debug, Eq)` —— 需要 `==`/`!=` 比较的枚举与结构（`NpyVersion`、`DType`、`ByteOrder`、`Complex`、
    `Subcommand`、`ExitCode`、`AdapterError`）
  - **不 derive 的实例也有理由记录**：`pub struct NpzArchive` 注释写明「No Debug derive: NpyArray has none,
    and the archive is asserted through its members, not its repr.」（`src/npz/npz.mbt:56-57`）
- 单元素结构体（仅一个 struct 承载两种宽度）：`pub(all) struct Complex { re : Double; im : Double }` ——
  命名刻意避开 `Complex64`/`Complex128`，以免与 `DType::Complex64`/`Complex128` 冲突（`src/dtype/complex.mbt:1-10`）。

## Code Style

**Formatting:**
- 格式化工具：**`moon fmt`**（工具链自带）。仓库根**没有 `.moonfmt` 或任何 formatter 配置文件**——
  完全使用工具链默认格式。
- **实测证据（2026-09-11）**：`moon fmt --check` → `Finished. moon: no work to do`（exit 0），
  即全树当前处于 `moon fmt` 的规范输出状态。CI 用更强的方式强制这一点：跑 `moon fmt` 后 `git diff --exit-code`。
- 缩进 **2 空格**；无 tab。`///|` 块分隔符顶格。
- **行宽无硬性限制**。实测最长行 110（`src/cli/cli.mbt`），其余文件 ≤ 100；绝大多数行在 80 以内。
- **每个顶层块前必须写 `///|`**（AGENTS.md §8「块风格」）。实测 `src/` 下 127 个顶层声明对应 127 个
  `///|` 块头，覆盖率 100%（含私有 `fn` 与顶层 `let` 常量）。
- 多行参数表**纵向展开 + 尾随逗号**：
  ```moonbit
  pub fn version_of(
    major : Int,
    minor : Int,
  ) -> Result[NpyVersion, @error.NpyError] {
  ```
  多行 record literal 同样尾随逗号：`Ok(NpyPrefix::{ version, major, minor, …, })`。
  **单行 record literal 也保留尾随逗号**，这是本仓库最好识别的排版特征：
  ```moonbit
  Ok(NpyHeader::{ descr, shape, fortran_order: fortran, })
  CliOutcome::{ output: msg, code: Operational, }
  let z = @dtype.Complex::{ re: 1.0, im: 2.0, }
  ```
- 类型标注 **冒号前留空格**：`data : Bytes`、`off : Int`、`kind : Char`、`self : NpyArray`。
- 字符串拼接只用**插值** `"\{x}"`，无独立 concat 运算符（AGENTS.md §7）：
  ```moonbit
  let path = "tests/fixtures/\{name}"
  let descr = "\{@dtype.endian_char(array.byte_order)}\{@dtype.descr_code(array.dtype)}"
  "\{solid}\{count} B"
  ```
- 长布尔表达式换行时**运算符置行首**：
  ```moonbit
  data.length() >= 6 &&
  data[0].to_int() == 147 && // 0x93
  data[1].to_int() == 78 && // 'N'
  ```
- 行尾注释用 `//`，与代码间至少一个空格；`///|` 恒占独立行。

**Linting:**
- **没有独立 linter**（无 ESLint/clippy 类比物）。唯一的静态门禁是 `moon check --target native`。
- 警告治理：AGENTS.md §2/§6 记录 `try?` 与 `@sys.get_cli_args()` 触发 **Warning 0020（弃用）**，
  两者在本仓库均已禁用并给出替代写法。CI 未启用 `-d/--deny-warn`（`moon test --help` 显示该 flag 存在但未使用）。
- **提交前三门**（AGENTS.md §8，与 CI Gate 1–3 一一对应）：
  ```bash
  moon fmt                                   # 格式化
  moon check --target native                 # 类型检查
  moon test --target native                  # 156 个测试
  ```
- **收尾纪律**（AGENTS.md §8 表格末行）：`moon info` 后 `moon fmt`，并检查 `pkg.generated.mbti` 的 diff
  是否符合预期——接口变更必须显式 review，不能悄悄漂移。

**MoonBit 语法与二进制/字节序惯例（项目特有，均为 M0 实测固化）：**
- **多语句 `match` / `try` 分支必须用 `{ }` 包裹**，否则第二行被当作新分支模式 → 编译报
  `Parse error ... expect =>`（AGENTS.md §2）。仓库代码严格遵循：
  ```moonbit
  Ok(version) => {
    let header_start = if major == 1 { 10 } else { 12 }
    …
  }
  ```
- **`raise` → `Result` 的唯一桥接写法**（`try?` 已弃用，AGENTS.md §2）：
  ```moonbit
  let r = try may_raise(x) |> Ok catch { e => Err(e) }
  ```
  实际用例见 `cmd/main/main.mbt:46`、`src/header/lexer.mbt:64`、`src/npz/npz.mbt:150`、`tests/npy_test.mbt:17`。
- **字节序：无跨后端内建能力，一律手工拼装**（AGENTS.md §3「手工拼装是所有后端的安全基线」）：
  - `u16` LE：`data[o].to_int() | (data[o + 1].to_int() << 8)`（`src/format/format.mbt:47`）
  - `u32` LE 且**立即加宽到 `Int64`**：`data[o].to_int64() | (… << 8) | (… << 16) | (… << 24)`（`src/format/format.mbt:52`）
  - 循环式通用装配（`n` 字节、按序决定权重）见 `src/dtype/codec.mbt::read_uint`；大端分支是
    `acc = (acc << 8) | b`，小端分支是 `acc = acc | (b << (8 * i))`。
  - Float 位模式用 `reinterpret`：`Float::reinterpret_from_int`、`UInt64::reinterpret_as_double`（AGENTS.md §5）。
- **下标 vs 安全取值的固定分工**（AGENTS.md §3）：`data[i]` → `Byte`（已验证长度后使用）；
  `data.get(i)` → `Byte?`（越界安全）；`String::get_char(i)` → `Char?`（`src/dtype/dtype.mbt` 注释明示
  用它把"越界"变成 `InvalidDType` 而不是 trap）；`data.unsafe_get(i)` 在本仓库**未使用**。
- **Byte 字面量用十六进制** `b'\xFF'` / `b'\x93'`，**可打印 ASCII 用字符形式** `b'N'`、`b'P'`、`b'K'`、
  `b'{'`、`b' '`、`b'\n'`——见 `src/format/format.mbt:14-19`、`src/writer/writer.mbt:106-111`、`src/npz/npz.mbt:35-41`。
- **魔数一律具名常量**并附出处注释：
  ```moonbit
  let sig_local : Array[Byte] = [b'P', b'K', b'\x03', b'\x04']    // src/npz/npz.mbt
  let sig_central : Array[Byte] = [b'P', b'K', b'\x01', b'\x02']
  let sig_eocd : Array[Byte] = [b'P', b'K', b'\x05', b'\x06']
  let array_align : Int = 64                                       // src/writer/writer.mbt
  ```
  裸数字只在原始字节序列中出现，且紧跟行尾注释说明 ASCII 值（`data[0].to_int() == 147 && // 0x93`）。
- **ASCII 判定用 `Byte::to_int()` 码值 + 行尾注释**，不用字符字面量比较：
  ```moonbit
  fn is_space(b : Byte) -> Bool {
    let c = b.to_int()
    c == 32 || c == 9 || c == 10 || c == 13 // ' ' \t \n \r
  }
  ```
- **位操作常量用 `0x…L` / `0x…UL`**：哨兵值比较写作 `cd_offset == 0xFFFFFFFFL`、`read_u16_le(…) == 0xFFFF`
  （`src/npz/npz.mbt:181-191`）。
- **溢出防护模式**：任何 `count * itemsize` 之前先做除法式预检：
  ```moonbit
  if element_count > int64_max / itemsize { return Err(@error.ShapeOverflow) }
  ```
  （`src/reader/reader.mbt:105`；同类写法 `shape_element_count` 的 `count > uint64_max / dim`，
  以及 `src/adapter/moonnum/adapter.mbt` 的 `dim > int_max_as_uint` 先判后转）。
- 类型宽度纪律（AGENTS.md §4）：**`Int` 是 32 位有符号、溢出回绕**，故字节数 / 元素总数 / shape 乘积 /
  header 偏移**一律 `Int64` 或 `UInt64`**；窄化 `.to_int()` 只在**已证明边界安全之后**执行，且通常配注释
  （`src/reader/reader.mbt:128`、`src/npz/npz.mbt:29-31`）。

## Import Organization

**Order:**
`moon.pkg` 内的 import 列表可观察到的稳定顺序（`tests/moon.pkg`、`src/cli/moon.pkg`、`src/writer/moon.pkg`）：
1. **本项目包** `"ShunjunGu/moon-npy/src/<pkg>"` —— 按依赖层次排列（`error` → `format` → `header` → `dtype`
   → `reader` → `writer` → `npz` → `cli` → `adapter/moonnum`）
2. **第三方 mooncakes 依赖** —— `"amor2025/moonNum/src/core"`、`"moonbitlang/x/fs"`
3. **`moonbitlang/core/*` 子包** —— `"moonbitlang/core/encoding/utf8"`、`"moonbitlang/core/string"`、
   `"moonbitlang/core/quickcheck/splitmix"`、`"moonbitlang/core/env"`

> 实测偏差：第 2、3 组之间**没有严格规则**——`tests/moon.pkg` 是 core 在前 x 在后，
> `cmd/main/moon.pkg` 是 x 在前 core 在后。可靠的部分只有「本项目包在前」。新代码按就近分组即可。

**Grouping:**
- 单个 `import { … }` 块，**无空行分组**，每项独占一行，`}` 前保留尾随逗号：
  ```toml
  import {
    "ShunjunGu/moon-npy/src/error",
    "ShunjunGu/moon-npy/src/format",
    "moonbitlang/core/encoding/utf8",
  }
  ```
- **依赖两步模型**（AGENTS.md §1）：`moon add <owner/repo>` 写 `moon.mod`（模块级可用）；
  每个**实际用到的包**还要在该包自己的 `moon.pkg` 里再 import 一次（包级引用）。
- `moonbitlang/core/*` 子包**只写 `moon.pkg`，不写 `moon.mod`**（core 是隐式依赖，AGENTS.md §1）。
- 可执行包在文件顶部单独一行声明：`pkgtype(kind: "executable")`（`cmd/main/moon.pkg`、
  `examples/roundtrip/moon.pkg`、`examples/bench/moon.pkg`）。
- **test-only 依赖**在 `tests/moon.pkg` 用 `for "test"` 收尾（`docs/spec/acceptance.md` / `README_CN.md` 均记录此约定）：
  ```toml
  import {
    "ShunjunGu/moon-npy/src/reader",
    "moonbitlang/core/quickcheck/splitmix",
    "moonbitlang/x/fs",
  } for "test"
  ```
- **`.mbt` 文件内禁止写 `import`**：文件级 import 会被本工具链 pin 拒绝（`src/adapter/moonnum/moon.pkg:2-4`
  的注释记录了这一实测，并指向 `docs/s6-api-card.md` §7）。→ **一切 import 只能出现在 `moon.pkg`**。

**Path Aliases:**
- **没有路径别名机制**（无 `@/` 类映射）。包引用一律走 `@<包名末段>`：`@error.NpyError`、
  `@format.parse_prefix`、`@dtype.DType`、`@header.parse_header`、`@reader.validate`、`@cli.run_dump`、
  `@moonnum.to_moonnum_f32`、`@core.NdArray`、`@dtypes.Dtype`、`@fs.read_file_to_bytes`、`@env.args()`、
  `@utf8.encode`、`@string.parse_int`、`@splitmix.new`、`@core_bench.single_bench`。
- 别名**只用于消解包名冲突**，在 `moon.pkg` 里用 `"pkg/path" @alias` 语法：
  - `examples/bench/moon.pkg`：`"moonbitlang/core/bench" @core_bench` —— 因为本包名恰好也叫 `bench`
  - `src/adapter/moonnum/moon.pkg`：`"amor2025/moonNum/src/core"` 解作 `@core`、
    `"amor2025/moonNum/src/dtypes"` 解作 `@dtypes`，而 `@dtype` 指本仓库 `src/dtype`——三者刻意区分，
    注释明确记录了这一点。

## Error Handling

**Patterns:**
- **核心层（`format` / `header` / `dtype` / `reader` / `writer` / `npz`）一律 `Result[T, NpyError]`，
  绝不用 `raise` 表达失败**（AGENTS.md §2；§2 结论「核心层坚持 enum + Result（跨后端一致、
  失败通道显式、不依赖异常语法演进）；仅薄 IO / CLI 层需要处理 `@fs` 的 `raise IOError`」）。
  `src/error/error.mbt:1-3` 把这条写进模块头：
  ```moonbit
  // Core layers (format/header/dtype/reader/writer) return Result[T, NpyError];
  // failure is never expressed as a Bool or a bare String.
  ```
- 签名一律写成 `-> Result[Array[Int], @error.NpyError]`，**不写 `raise`**。
- 传播惯用法是 **match + early return**，不用 `?` 运算符（本仓库未出现 `?` 传播语法）：
  ```moonbit
  let prefix = match @format.parse_prefix(data) {
    Ok(p) => p
    Err(e) => return Err(e)
  }
  ```
  （`src/reader/reader.mbt:86-103`；同形见 `src/header/parser.mbt:21-30`、`src/npz/npz.mbt:217-221`）
- 需要错误透传而不需要值时，用 `_` 忽略成功值：
  ```moonbit
  match @reader.validate(data) {
    Ok(_) => CliOutcome::{ output: "✓ \{path} is a valid NPY file", code: Success, }
    Err(e) => CliOutcome::{ output: render_failure(path, e), code: Invalid, }
  }
  ```
- **`Option` 承担"可能不存在"，`Result` 承担"可能失败"**——两者不混用：
  - `descr.get_char(0)` → `Char?`；`@env.current_dir()` → `String?`
  - `fn parse_limit(s : String) -> Int?`（溢出 → `None`，而**不是**一个 error 类型）
  - 形态固定为 `match … { Some(c) => c; None => return Err(…) }`（`src/dtype/dtype.mbt:188-191`）
- **薄 IO / CLI 边界才允许 `try … catch`**，且必须是 AGENTS.md §2 记录的桥接式：
  ```moonbit
  // @fs.read_file_to_bytes raises IOError; bridge to Result (AGENTS.md §2) and
  // treat a read error as Operational.
  let read_res = try @fs.read_file_to_bytes(path) |> Ok catch { e => Err(e) }
  ```
  （`cmd/main/main.mbt:44-53`；同形用于 `@utf8.decode`：`src/header/lexer.mbt:64`、`src/npz/npz.mbt:150`）
- **`abort` 只出现在测试 helper**，且写明理由：
  ```moonbit
  // Uses abort (not assert_eq) because assertions with an error effect are only
  // allowed directly inside a `test` block, not in a plain helper fn.
  fn check_prefix(fixture : String, major : Int, header_start : Int) -> Unit { … abort(…) }
  ```
  （`tests/writer_test.mbt:51-53`；同形 `check_dict`、`read_or_abort`（`examples/bench/main.mbt:60`）、
  各 `_test.mbt` 里的 `decode_fixture` / `load_fixture` 的 `.unwrap()`）
- **库代码不得对可描述的输入 trap**（§18 totality）：`@string.parse_int` 会 raise，故在
  `parse_limit` 里被 `try` 接住转成 `Int?` —— 注释写明「library code must not trap on input it can still
  describe (§18 totality)」（`src/cli/cli.mbt:112-114`）。
- **不新增 `NpyError` 变体以扩展其它层** —— 这会破坏 `src/cli/render_error` 的穷举匹配（S4 曾因此被破坏，
  见 CHANGELOG），故 adapter 自建 `AdapterError`：
  ```moonbit
  // A conversion-layer failure. Deliberately NOT a new @error.NpyError variant:
  // adding one to that `pub(all) enum` breaks the exhaustive match in
  // src/cli/render_error (S4 hit exactly this, see CHANGELOG), and none of these
  // cases is a complaint about the .npy file …
  pub(all) enum AdapterError { … }   // src/adapter/moonnum/adapter.mbt:19-24
  ```

**Error Types:**
- **单一顶层 error enum**：`pub(all) enum NpyError`（`src/error/error.mbt`），当前 19 个变体 + `derive(Debug)`。
  `src/error/moon.pkg` 是**叶子包、零依赖**（文件内仅一行注释说明此事）。
- 变体名描述**失败类别**，不是消息字符串；payload 承载机器可读上下文（`docs/spec/acceptance.md` §12）：
  ```moonbit
  UnsupportedVersion(Int, Int)        // (major, minor)
  MissingHeaderField(String)          // 缺失的 key 名
  DataLengthMismatch(Int64, Int64)    // (expected, actual)
  InvalidByteOrder(Byte)              // 原始字节
  InvalidChunkRange(Int, Int)         // (start, length)
  NpzMemberNotFound(String)           // 未命中的 key
  ```
- **`Invalid` vs `Unsupported` 的区分是刻意契约**（`src/dtype/dtype.mbt`）：`InvalidDType` = descr 本身畸形；
  `UnsupportedDType` = descr 合法但本库不解码（structured / void / complex256 / longdouble / datetime …）。
  还有一张显式的"已知但不支持"kind 表：`fn is_known_unsupported_kind(kind : Char)` 列了 14 个字符。
- 错误渲染集中在**一个穷举函数**：`pub fn render_error(e : @error.NpyError) -> String`（`src/cli/cli.mbt:405`）。
  约定：**第一行恒为变体名**，带 payload 的变体才追加详情行，详情行前缀固定
  （`Field:` / `DType descr:` / `Version:` / `Member:` / `Detail:` / `Start:` / `Length:`），
  唯一的对齐特例是 `DataLengthMismatch`：
  ```moonbit
  @error.DataLengthMismatch(expected, actual) =>
    "DataLengthMismatch\nExpected: \{group_digits(expected)} bytes\nActual:   \{group_digits(actual)} bytes"
  ```
- **退出码纪律**（`docs/spec/acceptance.md` §13，源 `src/cli/cli.mbt`）：两层非零码**不得合并**
  | 枚举 | 数值 | 语义 |
  |---|---|---|
  | `Success` | 0 | 文件是格式良好的 NPY 数组 |
  | `Invalid` | 1 | `validate()` 产出 `NpyError`（内容非法） |
  | `Operational` | 2 | 文件打不开，或用法错误 |
  非 native target 上无法设置具体退出码，降级为 `abort` 并保留注释说明 granuality 是有意丢失的
  （`cmd/main/main.mbt:23-27`，配 `#cfg(not(any(target="native", target="llvm")))`）。
- **全部 negative test 断言具体枚举分支，不接受泛化失败**（`docs/spec/acceptance.md` §12）。

## Logging

**Framework:**
- **本仓库没有日志框架**——这是一个库 + 单命令 CLI，`src/` 下没有任何 logging 相关 import，
  没有 logger 实例、没有 log level、没有结构化日志。
- 唯一的用户可见输出是 CLI 的 `String` 渲染，由 `cmd/main/main.mbt` 末尾一次性写出：
  ```moonbit
  fn main {
    let outcome = resolve(@env.args())
    println(outcome.output)
    exit_with(outcome.code.to_int())
  }
  ```

**Patterns:**
- 「诊断」职责由**结构化错误渲染**承担，而非日志：失败时输出 `✗ <path>` + `render_error(e)` 的多行块
  （`src/cli/cli.mbt::render_failure`），成功时输出元数据表或 `✓` 行。没有 stderr 通道、没有 debug 开关。
- **渲染逻辑与 IO 严格分离**是硬性架构约束，这正是"没有日志"的原因（`src/cli/cli.mbt:1-7`）：
  > Nothing in this package touches @fs / @env, which keeps the CLI compilable on every backend (§10.3)
  > and covered directly by tests/cli_test.mbt.
  所以 `src/cli` 是纯函数，`cmd/main` 只拥有两个副作用（读文件字节、设退出码）。
- 性能可观测性走**独立 example** 而非日志：`examples/bench/main.mbt` 用 `@core_bench.single_bench`
  输出四条读取路径的微基准（命令 `moon run examples/bench --target native --release`）。

## Comments

**When to Comment:**
- 注释密度显著高于一般项目：`src/` 共约 2250 行，其中 **约 676 行是 `//` 注释（≈30%）**。
  单文件极值：`src/cli/cli.mbt` 141/470、`src/npz/npz.mbt` 98/284、`src/reader/reader.mbt` 87/309、
  `src/writer/writer.mbt` 63/144、`src/dtype/codec.mbt` 60/154。
- 注释**解释 why 与契约，不复述 what**。可归纳为四类固定写法：
  1. **前置条件（caller 义务）用大写 `PRECONDITION:` 起头**：
     ```moonbit
     // PRECONDITION (caller-enforced): off + itemsize <= Bytes::length(data).
     // decode() (reader.mbt) checks element_count * itemsize == payload length
     // before any element is read, so an accessor on a decoded NpyArray never
     // indexes out of bounds. Bounds are checked once at the decode boundary, not
     // per element (§18: no crash / no out-of-range trap on the validated path).
     ```
     （`src/dtype/codec.mbt:8-12`；同形 `read_c64` / `read_c16` / `encode`）
  2. **反直觉决策的理由**：
     ```moonbit
     // The rejected window is echoed back verbatim, negatives included, so a
     // caller can tell which bound it got wrong.
     // Bytes is immutable with no zero-copy sub-slice returning Bytes (only
     // BytesView), so the payload is copied once here; element decoding stays
     // lazy afterwards.
     ```
  3. **跨层契约 / 与 spec 的对应**：几乎每段注释都带 §号——`§7.2`、`§7.3`、`§7.4`、`§9.2`、`§9.3`、
     `§10.1`、`§10.2`、`§11`、`§12`、`§13`、`§14`、`§16`、`§17`、`§18`、`§19`、`§21`、`§23`、`§29`、
     `§5`、`§4.4`、`附录 A`、`B2`、`E1`/`E2`/`E3`、以及 `AGENTS.md §N` 的交叉引用。
     这是本仓库**最强的注释惯例**：任何非平凡判断都能追溯到一份验收边界文档。
  4. **刻意不做某事的说明**（不是 TODO，见下）。
- 大段落用横幅注释分隔：
  ```moonbit
  // ---- format.parse_prefix: magic + version + header-length field (§7.2) ----
  // ---- negative: header body errors (§12) ----
  // ---- S4 streaming chunk reads: to_f32_chunk / to_f64_chunk (§29 Demo) ----
  ```
- 每个 `.mbt` 首部有一段文件级 block comment，写明**职责 + 所属 spec 章节 + 与相邻层的关系 + 已知取舍**，
  例如 `src/reader/reader.mbt:1-10` 的「Q1 layout note」、`src/npz/npz.mbt:1-31` 的 「Security posture」+
  「Byte-layout facts pinned by …」。

**JSDoc/TSDoc:**
- MoonBit 的文档块形态在本仓库统一为 **`///|` 分隔符 + 紧随其后的 `//` 行**（Doc 文本写 `//`，不写 `///`）：
  ```moonbit
  ///|
  // Read n bytes (1..=8) at `off` as an unsigned magnitude, honoring order.
  // Little / NotApplicable / Native assemble little-endian (byte i has weight
  // 8*i); Big reverses (first byte is most significant). …
  fn read_uint(data : Bytes, off : Int, n : Int, order : ByteOrder) -> UInt64 {
  ```
- **文档覆盖是 100% 的**（2026-09-11 实测）：`src/` 下 **127 个顶层声明**（`pub`/私有 `fn`、`struct`、`enum`、
  顶层 `let`）与 **127 个 `///|` 块头**一一对应，无遗漏；`pub` 项单独统计为 72 项，未文档化 0 项。
  → **每个顶层声明都必须有 `///|` 块头**，无论可见性。
- **不使用结构化 doc tag**：仓库内没有 `@param` / `@returns` / `@throws`，契约写在散文里
  （必要信息用 `PRECONDITION:` / `§N` 标注，而不是 tag）。
- 模块（文件）头注释在每个 `.mbt` 顶部，写在首个 `///|` 之前。

**TODO Comments:**
- 实测 `src/`、`tests/`、`cmd/`、`examples/` 下 **零 TODO / FIXME / XXX / HACK**。
- 未实现范围用**明确的"故意缺席"陈述**表达，而不是 TODO 标记：
  ```moonbit
  // `convert` / `benchmark` remain Stretch and are deliberately absent.   // src/cli/cli.mbt:11-12
  // The write direction (NdArray -> .npy bytes) is deliberately deferred
  // to v0.3 -- see docs/s6-api-card.md §3.5 …                           // src/adapter/moonnum/adapter.mbt:2-3
  // chunk accessors for the other dtypes are deliberately absent until
  // something needs them.                                               // src/reader/reader.mbt:275-276
  ```
- 变更追踪走 `CHANGELOG.md`（严格 Keep a Changelog 1.1.0 + SemVer）与 `.planning/` 下的计划文档，
  不在代码里留 TODO。

**Comments 语言（实测比例）：**
- **代码注释 ≈100% 英文**。实测对全部 27 个 `.mbt` 文件（`src/` + `tests/` + `cmd/` + `examples/`）做 CJK 扫描，
  仅 **3 行**含中文字符，且都是引用 spec 章节标题或路径名的括注：
  - `src/cli/cli.mbt:22` — `// Process exit codes (§13 "退出码纪律"). …`
  - `tests/cli_test.mbt:109` — `// ---- ExitCode / operational outcome (§13 退出码纪律) ----`
  - `examples/roundtrip/main.mbt:10` — `// ("MoonBit 读取并重新输出"). It does NOT construct arrays from typed data --`
- **文档层是中文**：`AGENTS.md`、`docs/spec/acceptance.md`、`docs/s6-api-card.md`、`interoperability/README.md`、
  `README_CN.md`、`CHANGELOG.md`、Python 脚本的 docstring 全部为简体中文。
- 结论：**「代码注释英文 / 设计文档中文」是已固化的双语分工**。新增代码注释应写英文；
  规范、设计说明、README、CHANGELOG 写中文。（`README.md` 为英文版，与 `README_CN.md` 成对维护。）

## Function Design

**Size:**
- 无硬性行数上限；主力函数普遍 20–60 行。超长逻辑被抽成小函数，而不是靠注释分段。
- **典型的抽取模式是"共享主体 + 薄包装"**：
  - `src/reader/reader.mbt` 把 13 个类型化访问器全部委托给 `fn[T] flat(arr, want, read)` →
    `fn[T] flat_range(arr, want, read, start, len)`，于是每个 `to_*` 只有 3–6 行：
    ```moonbit
    pub fn NpyArray::to_i16(self : NpyArray) -> Result[Array[Int], @error.NpyError] {
      flat(self, @dtype.Int16, @dtype.read_i16)
    }
    ```
  - `src/cli/cli.mbt` 抽出 `render_all` / `dump_values` / `join_lines` / `row` / `table_rule` /
    `shape_label` / `group_digits` / `human_size`，使 `render_inspect` 只剩一张字段表。
  - `src/adapter/moonnum/adapter.mbt` 抽出 `fn convert(arr, want, nn_dtype)`，
    两个公共入口 `to_moonnum_f32` / `to_moonnum_f64` 各 4 行。
- 单一抽象层次：解析、校验、渲染、装配分别独立成函数，不混层。

**Parameters:**
- 参数写法 `name : Type`（**冒号前留空格**）。
- 泛型参数写在函数名之前：`fn[T] flat(…)`、`fn[T] flat_range(…)`、`fn[T] render_all(…)`（`src/reader/reader.mbt`、
  `src/cli/cli.mbt`）。
- 无默认参数机制；可选行为用**命名常量**承载（`default_dump_limit`）或**payload 携带已解析值**
  （`Subcommand::Dump(Int)`，注释说明「so the pure renderer never has to re-read argv; parse_args owns the default」）。
- ≥3 个参数且超一行宽时纵向展开，每参数一行 + 尾随逗号：
  ```moonbit
  fn kind_size_to_dtype(
    kind : Char,
    size : Int,
    descr : String,
  ) -> Result[DType, @error.NpyError] {
  ```
- 高阶参数用**闭包**而非 trait bound，并写明理由：
  ```moonbit
  // A closure parameter rather than a trait bound because the dtypes render differently (complex is a pair).
  fn[T] render_all(
    res : Result[Array[T], @error.NpyError],
    show_value : (T) -> String,
  ) -> Result[Array[String], @error.NpyError] {
  ```
  内联闭包写 `fn(v) { v.to_string() }`、`fn(z : @dtype.Complex) { "(\{z.re}, \{z.im})" }`。
- **月亮坑（MoonBit 特有）**：局部 `let` 绑定**不会跨 `T` 泛化**，所以多态渲染闭包必须逐分支重写——
  源码明确记录了这个陷阱（`src/cli/cli.mbt:218-221`）：
  > The rendering closure is written out per branch rather than shared through a `let` -- MoonBit does not
  > generalize a local binding over `T`, so one polymorphic `digits` value would be pinned to the first dtype that used it.

**Return Values:**
- **失败通道是类型的一部分**：几乎全部公共函数返回 `Result[T, @error.NpyError]`（或 adapter 的
  `Result[_, AdapterError]`）。
- guard clause 早期返回，写在函数开头：
  ```moonbit
  if n < 2 {
    return Err(@error.InvalidDType(descr)) // need at least <endian><kind>
  }
  ```
- 表达式位置的 `if/else` 直接产出值，避免 early return，并有注释说明这一取向：
  ```moonbit
  // Map (kind char, itemsize) to a supported DType. All branches yield a
  // Result so no early return is needed in expression position.
  ```
- 最后的 `match` 结果直接作为返回值，不引入临时变量：
  ```moonbit
  match kind_size_to_dtype(kind, size, descr) {
    Ok(dt) => Ok((dt, order))
    Err(e) => Err(e)
  }
  ```
- **`match` 必须穷举**，且"不写 `_` 兜底"是**刻意设计**，用于让新增 dtype 编译失败而不是静默降级：
  ```moonbit
  // The match is exhaustive over all 13 dtypes on purpose: unlike the rest of the
  // CLI there is no sensible "not supported yet" here, and a future dtype must
  // fail the build rather than degrade into an UnsupportedDType row.
  ```
  （`src/cli/cli.mbt:216-221` 的 `dump_values`；同形 `itemsize` / `name` / `descr_code` / `version_label` /
  `byte_order_label` / `render_error`）
  - 唯一有意的 `_` 兜底是语义上确实同构的分支，并配注释：`fn is_big(order : ByteOrder) -> Bool { match order { Big => true; _ => false } }`
    （`src/dtype/endian.mbt:20-25`，注释说明 Little / NotApplicable / Native 三者同读小端）。
- `Unit` 返回类型只在需要时显式写 `-> Unit`（如 `fn check_dict(…) -> Unit`，因为它用 `abort` 而非返回）；
  纯过程式函数省略箭头。

## Module Design

**Exports:**
- **没有 barrel / index 文件**——MoonBit 无 re-export 机制，**包边界即模块边界**。
- 包按职责单向切分，依赖严格无环：
  ```
  error  (叶子，零依赖)
    ← format              （magic/version/header_len/LE 装配）
        ← header          （lexer + parser：受限 Python literal → NpyHeader）
        ← dtype           （descr → (DType, ByteOrder) + 元素 codec）
    ← reader              （validate/decode + 类型化 accessor；依赖 format+header+dtype）
    ← writer              （encode → 字节；依赖 format+header+dtype+reader）
    ← npz                 （ZIP 容器；依赖 error+format+reader）
    ← cli                 （纯逻辑；依赖 error+format+header+dtype+reader）
    ← adapter/moonnum     （→ moonNum NdArray；依赖 dtype+reader + 外部 moonNum）
  cmd/main  ⟶ cli + @fs + @env        （唯一拥有副作用的可执行体）
  examples/roundtrip ⟶ reader + writer + @fs + @env
  examples/bench    ⟶ reader + @core_bench + @utf8 + @json + @fs
  tests     ⟶ 全部 9 个 src 包 + moonNum + splitmix + @utf8 + @fs（`for "test"`）
  ```
  `src/error/moon.pkg` 全文只有一行注释 `// src/error - structured NpyError enum (plan section 12). Leaf package, no deps.`
  —— 无环依赖是被显式记录的设计事实。
- 导出面刻意收窄（三层梯度见 Naming Patterns 的「Types」）：稳定 API 用 `pub`，测试需要构造的用 `pub(all)`，
  只读载体用 `pub struct`，其余不导出。多处源码注释解释为何这样选（`src/reader/reader.mbt:6-10`、
  `src/cli/cli.mbt:44-48`、`src/npz/npz.mbt:52-60`）。
- 跨层"只读不构造"的传播方式有固定套路：`NpyMeta` → `NpyArray` 逐字段复制而不是共享可变状态
  （`src/reader/reader.mbt:139-146` 的 `NpyArray::{ version: meta.version, header: meta.header, … }`）。
- 接口快照：`moon info` 生成 `pkg.generated.mbti`（含 `// Generated using `moon info`, DON'T EDIT IT`），
  被 `.gitignore` 忽略但保留在工作树，作为 review 时的接口 diff 依据（AGENTS.md §8 收尾步骤）。
  `.mbti` 中可见公共项按 `// Values` / `// Errors` / `// Types and methods` / `// Type aliases` / `// Traits` 分区。

**Barrel Files:**
- **不适用**（MoonBit 生态无 barrel/index 惯例，无 re-export 语法）。等价物是 `pkg.generated.mbti`
  接口快照 + `moon info` 后的 diff 检查：接口变更必须显式可见。
- 避免循环依赖的手段不是"从具体文件 import"（MoonBit 按包 import），而是**把共享类型下沉到叶子包**：
  `NpyError` 放在零依赖的 `src/error`，`NpyHeader` 放在只依赖 error 的 `src/header`，
  于是 `reader` / `writer` / `cli` 都能引用它们而不形成回边。`src/npz/npz.mbt:104-109` 记录了
  另一条相关取舍：为了不引入 `npz → reader` 的私有 helper 依赖，`slice_bytes` 与 `reader.slice_payload`
  刻意重复实现，注释写明「the duplication is the accepted cost of keeping the reader package unaware of containers
  (no cyclic dependency)」。

---

*Convention analysis: 2026-09-11*
*Update when patterns change*
