# AGENTS.md — moon-npy 项目智能体指南（M0 实测固化）

> 本文件记录 **M0 验证 gate（2026-09-07）实测确认** 的 MoonBit 工具链事实与项目约定。
> 正式开发（Reader / Writer / CLI）必须遵循此处**已验证**的语法与 API，禁止基于旧假设或博客版本臆写。
> 证据：`../m0smoke/` 探针模块在 **native target** 编译 + 运行全部通过（throwaway，非交付库）。
> 验收边界规范：`docs/spec/acceptance.md`（仓库内**唯一权威 spec owner**：§7.2/§7.4/§8.4/§12/§13/
> §14/§15/§16/§19/§21/§23/附录 A 的字节契约、退出码、覆盖率阈值、CI 门禁均在此，仓库各处 `§N`
> 引用据此在克隆内解析。早期仓库外计划文档中的同类编号仅作历史来源，不再作为交付/CI 引用目标）。

## 0. 工具链版本（B.2 #1）

- `moon version` = **`0.1.20260827 (d0aaa07 2026-08-27)`**
- **日期制版本号**（非语义化 0.8 / 0.10）。计划里"≥ 0.8 / 生态 ~0.10.x"的假设**作废**，一切以此装机版本实测为准。
- feature flags：`rr_moon_mod`、`rr_moon_pkg` 已启用。
- 安装位置：`C:\Users\<user>\.moon\bin\moon.exe`（**可能不在 PATH**，脚本首行显式加）。
- core 库源码（bundled）：`C:\Users\<user>\.moon\lib\core\`（builtin / float / double / bytes / int64 / env / error …）。
- 依赖缓存：模块内 `.mooncakes\`（`moon add` 后解压）；registry zip：`~\.moon\registry\cache\`。

## 1. 清单文件（修正计划 §11）

- 模块清单 = **`moon.mod`**，包清单 = **`moon.pkg`**（**均无 `.json` 后缀**，TOML-like 语法，`//` 注释）。
  - 计划 v0.2 §11 曾把二者"订正"为 `moon.mod.json` / `moon.pkg.json` —— **该订正错误、已作废**。`moon new` 脚手架与官方 scaffold AGENTS.md 均用无后缀名（v0.1 原本正确）。
- `moon.mod` 关键字段：`name = "local/xxx"`、`version`、`preferred_target`、`import { "moonbitlang/x@0.5.1", }`。
- `moon.pkg` 声明**包级** import：`import { "moonbitlang/x/fs", "moonbitlang/core/env", }`；可执行包加 `pkgtype(kind: "executable")`。
- 依赖两步：`moon add <owner/repo>` 写 moon.mod（模块级可用）；每个用到的包再在自己 moon.pkg 里 import（包级引用）。
- `moonbitlang/core/*` 子包（如 `env`）可直接在 moon.pkg import，无需写进 moon.mod（core 是隐式依赖）。

## 2. 错误模型（E1，B.2 #2 —— 修正计划 §10.1）

**核心层决策不变**：普通 `enum NpyError {...}` + 内建 `Result[T, NpyError]`（`Ok` / `Err`）。实测全通过。

- `enum` 支持带 payload 构造子（`UnsupportedVersion(Int, Int)`）与无 payload（`ShapeOverflow`）。
- `match res { Ok(v) => ...; Err(e) => ... }` 正常。
- **多语句 match / try 分支必须用 `{ }` 包裹**（否则第 2 行被当成新分支模式，编译报 `Parse error ... expect =>`）。

**`try?` 已弃用（Warning 0020）** —— 计划 §10.1 用 `try?` 做 raise→Result 桥接的写法**作废**。替代：

```moonbit
// raise -> Result 桥接（替代已弃用的 try?）
let r = try may_raise(x) |> Ok catch { e => Err(e) }
```

**typed error（方案 B，实测亦可用，核心层不采用）**：

- `suberror Name { Constructor(Payload) }` 声明；`-> T raise Name` 标注；`raise Constructor(...)` 抛出。
- `try! expr`（断言不抛）、`try expr catch { e => ... } noraise { v => ... }`（完整处理）。
- 内建 `Failure::Failure(String)`；顶层致命错误可 `fail("msg")` / `panic`。
- 结论：核心层坚持 enum + Result（跨后端一致、失败通道显式、不依赖异常语法演进）；仅薄 IO / CLI 层需要处理 `@fs` 的 `raise IOError`。

## 3. Bytes / 字节序（E3，B.2 #3 —— 修正计划 §9.3）

- 下标 `data[i]` → **`Byte`**（非 Option）。`data.get(i)` → `Byte?`（安全）。`data.unsafe_get(i)` → `Byte`。
- `Byte.to_int()` / `to_int16()` / `to_int64()`；`Int.to_byte()` / `UInt.to_byte()`。Byte 字面量：`b'\xFF'`（十六进制）或 `b'N'`（字符）。
- `Bytes::length() -> Int`、`Bytes::from_array(Array[Byte]) -> Bytes`、`Bytes::to_array() -> Array[Byte]`。
- **`Bytes::make(len, init)` 是位置参数**（计划 §9.3 写的 `Bytes::make(len, ~init=)` 命名参数**作废**）。实测 `Bytes::make(4, b'\xAB')` → 4 字节全 0xAB。
- `Bytes::makei(length, i => byte_expr)`（可 raise）亦存在。
- **无跨后端内建「按字节序读 u16/u32/float」** —— 手工拼装是所有后端的安全基线（实测 u16 LE=513、u32 LE=67305985 正确）。

## 4. 数值位宽（B2 —— 确认计划 §9.2）

- **`Int` = 32 位有符号、溢出回绕**（实测 `1000000 * 1000000 = -727379968`，即 1e12 mod 2³²）。
- `Int64` / `UInt64` 独立存在；`Float` = 32 位；`Double` = 64 位；无独立 `Int8/UInt8`（`Byte` 承担 8-bit）。
- **纪律**：字节数 / 元素总数 / shape 乘积 / header 偏移 **一律 `Int64`（或 `UInt64`）**；乘 `itemsize` 前先做溢出预检 → `ShapeOverflow`，绝不静默截断。

## 5. Float / Double ↔ 位模式（B.2 #4 —— 补全计划 §9.3）

实测确认的确切 API 名：

- **float32（`Float`）**，`moonbitlang/core/float`（类型方法自动可用，无需在 moon.pkg import）：
  - `Float::reinterpret_from_int(Int) -> Float`、`Float::reinterpret_as_int(Float) -> Int`
  - 另有 `reinterpret_from_uint` / `reinterpret_as_uint`
- **float64（`Double`）**，`moonbitlang/core/builtin`（int64.mbt，自动可用）：
  - `Int64::reinterpret_as_double(Int64) -> Double`、`Double::reinterpret_as_int64(Double) -> Int64`
  - 另有 `UInt64::reinterpret_as_double` / `UInt64::reinterpret_as_int64`
- 实测：f32 LE `00 00 80 3F`→1.0、`00 00 80 BF`→-1.0；f64 LE `00…F0 3F`→1.0、`00…F0 BF`→-1.0；`Double` round-trip 精确相等。

## 6. 文件 IO / CLI 参数（E2 + sys，B.2 #5/#6 —— 修正计划 §10.4 / §13）

**E2 gate 通过**：`moonbitlang/x@0.5.1` 的 `@fs` 在 **native target 可用**（首选方案即通过，无需回退 async / FFI）。

- `@fs.read_file_to_bytes(String) -> Bytes raise IOError` —— 实测读 152B fixture，magic `\x93NUMPY`、version 1.0 / 2.0 全对。
- `@fs.write_bytes_to_file(String, Bytes) -> Unit raise IOError`（Writer 用）。
- 另有 `read_file_to_string` / `write_string_to_file` / `path_exists(String)->Bool`（不 raise）/ `is_file` / `is_dir` / `read_dir` / `create_dir` / `remove_file` / `remove_dir`。
- `IOError` 是 `suberror`（typed raise）→ 调用处必须 `try … catch` / `try!` / 桥接为 Result。

**CLI 参数（修正）**：

- `@sys.get_cli_args()`（`moonbitlang/x/sys`）**已弃用（Warning 0020）**，实现只是转调 `@env.args()`。
- **改用 `@env.args()`（`moonbitlang/core/env`）**：`args() -> Array[String]`，native 返回 C-style argv：
  - **`args[0]` = 程序（exe）路径，用户参数从 `args[1]` 起**（计划 §13 注释"args[0]=子命令"**错误**，索引整体 +1）。
  - 例：`moon-npy inspect a.npy` → `args = [exepath, "inspect", "a.npy"]`，子命令 = `args[1]`，路径 = `args[2]`。
- 另有 `@env.current_dir() -> String?`、`get_env_var` / `get_env_vars`、`now() -> UInt64`、`rand(Int) -> Bytes?`。
- `moon run <pkg> --target native -- <args...>`：`--` 之后的参数转发给可执行体（实测 `@env.args()` 长度 1→2）。

## 7. 测试 / 覆盖率（B.2 #7 —— 修正计划 §14 / 附录 B）

- 测试文件：`*_test.mbt`（blackbox，用 `@pkg.` 前缀访问被测包公共 API）、`*_wbtest.mbt`（whitebox）。
- 断言：`assert_true(cond)` / `assert_false(cond)` / `assert_eq(a, b)`；快照 `inspect(v, content=…)` / `debug_inspect(v, content=…)`（无 bang，test 文件内自动可用）。
- **字符串插值 `"\{x}/file.txt"` 是拼接字符串的方式**（无需独立 concat 运算符）。
- 运行：`moon test`（默认 target）；刷新快照 `moon test --update`；指定 `moon test --target native`。
- **覆盖率（确切命令）**：
  1. `moon test --enable-coverage` —— 跑测试 + 生成 trace（`_build/moonbit_coverage_*.txt`）。
  2. `moon coverage analyze` —— 一体化：插桩跑测试 + 终端 caret 报告（官方 scaffold 推荐 `moon coverage analyze > uncovered.log`）。
  3. `moon coverage report -f <fmt>` —— 从已有数据出报告；**flag 是 `-f` 不是 `--format`**；格式 `bisect`(默认)/`caret`/`html`/`coveralls`/`cobertura`/`summary`。
  4. `moon coverage clean` —— 清理产物（`bisect.coverage` 等）。
  - 实测：`moon coverage report -f summary` → `Total: 8/203`（可执行体 main.mbt 未被 test 触达属正常）。CI 可用 `-f coveralls --send-to codecov`。

## 8. 工具命令速查

| 目的 | 命令 |
|---|---|
| 类型检查 | `moon check --target native` |
| 编译 + 运行 | `moon run <pkg> --target native [-- args...]` |
| 测试 | `moon test [--target native] [--enable-coverage]` |
| 覆盖率 | `moon coverage analyze` / `moon coverage report -f summary` |
| 格式化 | `moon fmt` |
| 更新接口(.mbti) | `moon info` |
| 加依赖 | `moon add <owner/repo>` |
| 文档服务 | `moon doc --serve` |
| 收尾 | `moon info` 后 `moon fmt`，检查 `.mbti` diff 是否符合预期 |

- **PowerShell 坑**：moon 把进度写 stderr，PowerShell 渲染成红色 `NativeCommandError`，但 `$LASTEXITCODE` 才是真相（装饰性，非真错）。判定用 `2>&1 | Out-String` + 查 `$LASTEXITCODE`。
- **PATH 坑**：`moon` 可能不在 PATH，脚本首行 `$env:Path = "$env:USERPROFILE\.moon\bin;$env:Path"`。
- **块风格**：每个顶层块前用 `///|` 分隔；`moon fmt` 会规整。

## 9. M0 Gate 结论（B.2 全 7 项）

| # | 项 | 结果 |
|---|---|---|
| 1 | `moon version` | ✅ `0.1.20260827 (d0aaa07)`，日期制 |
| 2 | E1 错误范式 | ✅ enum+Result+Ok/Err；suberror+raise+try/catch/noraise 亦可；**try? 弃用**→`try … \|> Ok catch` |
| 3 | E3 / Bytes | ✅ 下标→Byte、get→Byte?、unsafe_get、to_int/to_int64、手工 LE、from_array、**make 位置参数** |
| 4 | Float reinterpret | ✅ `Float::reinterpret_from_int/as_int`、`Int64::reinterpret_as_double`、`Double::reinterpret_as_int64` |
| 5 | E2 native IO | ✅ **`@fs.read_file_to_bytes` native 可用**（152B / magic / version 1.0+2.0 全对） |
| 6 | CLI 参数 | ✅ `@env.args()`（`@sys.get_cli_args` 弃用）；**args[0]=exe，用户参数从 args[1] 起** |
| 7 | coverage | ✅ `test --enable-coverage`→`analyze`→`report -f summary`（8/203）；6 种格式可用 |

**结论：GO。** 全 7 项 gate 通过；最大风险 E2（native 文件 IO）已消除，无需回退 async / native FFI。
计划假设与实测的偏差均为**可就地修正的次级项**（清单文件名 `.json`、`try?` 弃用、`@sys`→`@env`、`Bytes::make` 参数形、CLI 参数索引、coverage flag），已回填计划 §9–§13 / 附录 B 与本文件。
**下一步**：以 `moon new` 脚手架正式 `moon-npy` 模块（本 AGENTS.md 置于其根），进入 Reader 开发（§23 时间线）。
