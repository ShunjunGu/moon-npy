# Technology Stack

**Analysis Date:** 2026-09-11

## Languages

**Primary:**
- MoonBit — 全部库与可执行体代码：`src/`（`format` / `header` / `dtype` / `reader` / `writer` / `npz` / `error` / `cli` / `adapter/moonnum`）、`cmd/main/`、`examples/roundtrip/`、`examples/bench/`、`tests/`
  - 工具链双版本号（两者指向同一次安装，见 `AGENTS.md` §0 与 `.github/workflows/ci.yml` 注释）：
    - `moon version` = `0.1.20260827 (d0aaa07 2026-08-27)` —— **日期制版本号，非语义化 0.x**
    - `moonc -v` = `v0.10.11+6ff76a5f9 (2026-08-28)` —— 该 semver 串才是安装 CDN `cli.moonbitlang.com/binaries/<version>/` 的 key；日期串在 CDN 上返回 403（`.github/workflows/ci.yml` 第 32–40 行实测记录）
  - `AGENTS.md` §0 明确警告：早期计划文档里「≥ 0.8 / 生态 ~0.10.x」的假设**作废**，一切以此装机版本实测为准
  - feature flags `rr_moon_mod`、`rr_moon_pkg` 已启用（`AGENTS.md` §0）

**Secondary:**
- Python 3.14 — 仅跨语言 Oracle 侧：`interoperability/generate_fixtures.py`、`interoperability/verify_moonbit_output.py`、`interoperability/roundtrip.py`、`interoperability/probe_npz.py`。不参与库的构建或运行
- Bash — `.github/workflows/ci.yml` 的 `run:` 步骤（`ubuntu-latest` 上的 `bash -e`）
- YAML — `.github/workflows/ci.yml`（唯一的 CI 定义处）
- PowerShell — 仅本机开发时的 PATH 修复与退出码判定（`AGENTS.md` §8：「PowerShell 坑」/「PATH 坑」），仓库内无 `.ps1` 文件

## Runtime

**Environment:**
- MoonBit **native** 后端（`moon.mod` 第 14 行 `preferred_target = "native"`）；`_build/index.json` 内容为 `["native"]`
- 无 Node.js / 浏览器运行时；无 Python 运行时依赖（库的卖点即「无 Python runtime、无 Python FFI」，`README.md` Ecosystem Position）
- 构建产物目录：`_build/`（已 gitignore），含 `native/`、`wasm-gc/release/`、`publish/`、`m4_out/`、`bench_100x768_f32.npy`、`moonbit_coverage_*.txt`
- `preferred_target = "native"` 的含义：`cmd/main/` 的退出码纪律依赖 `extern "c" fn exit_with = "exit"`，且**仅**在 `#cfg(any(target="native", target="llvm"))` 下生效（`cmd/main/main.mbt` 第 14–27 行）；非 native 目标降级为 `abort`，§13 的「两个非零码互异」粒度**故意丢失**。库核心层（`src/*`）无 target 限制（全仓无 `supported_targets` 声明）

**Package Manager:**
- MoonBit 自带包管理：`moon add` 写 `moon.mod`，`moon update` 刷新 registry index，`moon tree` 看依赖树
- 依赖来源：mooncakes.io registry；解压缓存 = 模块内 `.mooncakes/`（`AGENTS.md` §0）；registry zip 缓存 = `~/.moon/registry/cache/`；registry index git 克隆 = `~/.moon/registry/index/`
- **Lockfile 现状（诚实标注）**：`.gitignore` 第 5 行声称「`moon.lock` 需入库以保证依赖可复现（§19），故不忽略」，但实测仓库根**不存在 `moon.lock`**，`git ls-files | grep -i lock` 为空；唯一存在的 lock 文件是 `.mooncakes/.moon-lock`，其大小为 **0 字节**。可复现性当前由 `moon.mod` 的精确版本 pin（`moonbitlang/x@0.5.1`、`amor2025/moonNum@0.1.0`）+ CI 工具链 pin 承担，而非 lockfile
- 无 npm / pip lockfile：仓库内 Python 脚本无 `requirements.txt` / `pyproject.toml`（NumPy 版本由 CI env 与文档 pin）

## Frameworks

**Core:**
- 无第三方框架。`src/` 是自研纯 MoonBit 实现（`README.md` Architecture：`format → header → dtype → reader/writer/npz → adapter`，`cli` 为纯逻辑层，`cmd/main` 为唯一 IO 薄壳）
- 无 Web 框架、无 Web 服务器、无 ORM、无 UI 框架

**Testing:**
- MoonBit 内建测试运行器 `moon test`（`AGENTS.md` §7）：`*_test.mbt`（blackbox，用 `@pkg.` 前缀访问公共 API）与 `*_wbtest.mbt`（whitebox）
- 断言原语：`assert_true` / `assert_false` / `assert_eq`；快照 `inspect(v, content=…)` / `debug_inspect`
- 确定性 fuzz：`moonbitlang/core/quickcheck/splitmix`（固定种子 0x5EEDUL / 0xC0FFEEUL / 0xBADC0DEUL，`tests/fuzz_test.mbt` 7000 次迭代）
- 测试规模：**156 个测试**，分布于 `tests/{adapter,cli,dtype,edge,fuzz,npy,npz,property,reader,security,writer}_test.mbt`
- test-only 依赖写在 `tests/moon.pkg` 的 `import { … } for "test"` 块（含 `moonbitlang/core/quickcheck/splitmix`、`moonbitlang/x/fs`、`amor2025/moonNum/src/core`）
- 无 Jest / Pytest / Playwright 等外部测试框架

**Build/Dev:**
- `moon` CLI 各子命令（`AGENTS.md` §8 速查表；CI 与 README 均以此为唯一构建入口）：

  | 目的 | 命令 |
  |---|---|
  | 类型检查 | `moon check --target native` |
  | 编译 + 运行 | `moon run <pkg> --target native [-- args...]`（`--` 之后转发给可执行体） |
  | 测试 | `moon test [--target native] [--enable-coverage]` |
  | 覆盖率 | `moon coverage analyze` / `moon coverage report -f summary` |
  | 格式化 | `moon fmt` |
  | 更新接口 `.mbti` | `moon info` |
  | 加依赖 | `moon add <owner/repo>` / `moon update` |
  | registry 搜索 | `moon search <q>` |
  | 文档服务 | `moon doc --serve` |
  | 脚手架 | `moon new <PATH> --user <u> --name <n>`（**`moon init` 在本 pin 不存在**，`docs/s6-api-card.md` §7） |

- 覆盖率四步（`AGENTS.md` §7）：`moon test --enable-coverage` → `moon coverage analyze` → `moon coverage report -f <fmt>`（flag 是 `-f` 不是 `--format`；格式 `bisect`(默认)/`caret`/`html`/`coveralls`/`cobertura`/`summary`）→ `moon coverage clean`
- `.mbti` 接口文件：仓库内 **51 个** `pkg.generated.mbti`（每包一个），`moon info` 后 `moon fmt` 是收尾纪律；`pkg.generated.mbti` 被 `.gitignore` 忽略
- 性能基准：`moonbitlang/core/bench`（`@core_bench.single_bench`，auto batch sizing 至 ~100ms/批，winsorised 5% tails），入口 `moon run examples/bench --target native --release`
- 发布打包：`moon publish` 产物见 `_build/publish/ShunjunGu-moon-npy-0.3.0.zip` + `_build/publish/verify/`
- 无 Makefile / CMake / Bazel / esbuild / Vite：构建图完全由 `moon.mod` + 各包 `moon.pkg` 描述

## Key Dependencies

**Critical:**
- `moonbitlang/x@0.5.1`（`moon.mod` 第 19 行声明；Apache-2.0，repo `https://github.com/moonbitlang/x`）— **为什么关键：本库唯一被用到的能力是 native 文件 IO**。具体到子包 `moonbitlang/x/fs`（`AGENTS.md` §6 的 E2 gate：`@fs.read_file_to_bytes` / `@fs.write_bytes_to_file` / `@fs.path_exists`，`IOError` 是 `suberror`，调用处必须 `try … catch` 桥接为 `Result`）。使用点集中在 `cmd/main/moon.pkg`、`examples/roundtrip/moon.pkg`、`examples/bench/moon.pkg`、`tests/moon.pkg`（`for "test"`）。注意 `moonbitlang/x/fs/moon.pkg` 自带 `"native-stub": [ "fs_native.c" ]` 与按 target 分文件（`fs_native.mbt` → native/llvm，`fs_js.mbt` → js，`fs_wasm.mbt` → wasm/wasm-gc）——C stub 由依赖自带，本仓不需要系统包
- `amor2025/moonNum@0.1.0`（`moon.mod` 第 20 行声明；Apache-2.0，上游 `repository` 为空串）— **为什么关键：S6 生态适配的唯一目标库**，只被 `src/adapter/moonnum/` 引用（`amor2025/moonNum/src/core` 的 `NdArray::from_buffer` 与 `amor2025/moonNum/src/dtypes` 的 `Dtype`）。选型 go/no-go 与全部实测签名见 `docs/s6-api-card.md`；被拒候选 `mizchi/numbt@0.2.4` 因需系统 BLAS（`cblas.h` / `-framework Accelerate`）而 no-go
  - 依赖共存已验证：moonNum 声明下界 `moonbitlang/x@0.4.46`，被本仓 `x@0.5.1` 满足，解析为**单一** 0.5.1，无重复 `x`（`docs/s6-api-card.md` §3.2 的 `moon tree` 原文）
  - moonNum 特性：纯 MoonBit、无 C FFI（`supported_targets` / `native-stub` / `cc-link-flags` / `extern "c"` 均 0 处，`docs/s6-api-card.md` §3.3），自带 `src/io/save_load.mbt`（`to_npy_bytes` / `from_npy_bytes` / `load` / `load_npz`）与 `src/zlib/`（**本仓不引用其 zlib**）

**Infrastructure:**
- MoonBit core 标准库（**隐式依赖**，`AGENTS.md` §1：`moonbitlang/core/*` 子包可直接在 `moon.pkg` import，无需写进 `moon.mod`）：
  - `moonbitlang/core/env` — `@env.args()`（CLI argv，`AGENTS.md` §6 修正：`args[0]` = exe 路径，用户参数从 `args[1]` 起；`@sys.get_cli_args()` 已弃用）
  - `moonbitlang/core/encoding/utf8` — header 文本编解码（`src/header`、`src/writer`、`src/npz`、`tests`、`examples/bench`）
  - `moonbitlang/core/string` — `src/cli`
  - `moonbitlang/core/float` / `moonbitlang/core/builtin` — `Float::reinterpret_from_int` / `Int64::reinterpret_as_double` 等位模式 API（`AGENTS.md` §5，类型方法自动可用，无需 import）
  - `moonbitlang/core/quickcheck/splitmix` — 确定性 fuzz（test-only）
  - `moonbitlang/core/bench` — 基准（`examples/bench`，别名 `@core_bench`）
  - `moonbitlang/core/json` — bench 的 `Summary` 读回（`examples/bench`，别名 `@json`）
- 无数据库驱动、无 HTTP 客户端、无序列化框架（JSON 仅在 bench 输出用）

## Configuration

**Environment:**
- **运行时零环境变量**：库与 CLI 不读任何 env var；无 `.env` / `.env.example` / secrets 文件（已核查，仓库内不存在）
- 可选 env var `MOON_BIN` —— `interoperability/roundtrip.py` 用它定位 `moon` 二进制（解析顺序 `--moon` > `$MOON_BIN` > PATH，见该脚本 `resolve_moon`）
- **PATH 要求（Windows）**：`moon.exe` 装在 `C:\Users\<user>\.moon\bin\`，**可能不在 PATH**，脚本/PowerShell 首行需显式加（`AGENTS.md` §0 / §8，`README.md` Installation）
- 跨语言验证所需外部版本（非 env var，由文档 + CI env pin）：NumPy `2.3.4`、Python `3.14`

**Build:**
- `moon.mod` — 模块清单（TOML-like，`//` 注释；**无 `.json` 后缀**，`AGENTS.md` §1 明确「`moon.mod.json` / `moon.pkg.json` 的订正错误、已作废」）。字段：`name = "ShunjunGu/moon-npy"`、`version = "0.3.0"`、`readme`、`repository = "https://github.com/ShunjunGu/moon-npy"`、`license = "Apache-2.0"`、`keywords = [ "npy", "numpy", "interop", "binary", "serialization" ]`、`preferred_target = "native"`、`description`、`import { … }`
- 10 个包级 `moon.pkg`：`src/{format,header,dtype,reader,writer,npz,error,cli}/moon.pkg` + `src/adapter/moonnum/moon.pkg` + `cmd/main/moon.pkg` + `tests/moon.pkg` + `examples/{roundtrip,bench}/moon.pkg`
  - **唯一声明 `pkgtype(kind: "executable")` 的三个包**：`cmd/main/moon.pkg`、`examples/bench/moon.pkg`、`examples/roundtrip/moon.pkg`
  - 依赖方向（`README.md` Architecture）：`error` 是叶子包（`src/error/moon.pkg` 注释「Leaf package, no deps」）→ `format`/`dtype` 只依赖 `error` → `header` 再加 `format` + `core/encoding/utf8` → `reader` 汇总 `format`/`header`/`dtype` → `writer`/`npz` 再加 `encoding/utf8` → `cli` 依赖 `error`/`format`/`header`/`dtype`/`reader`/`core/string`
  - 跨包别名约定：`@core` / `@dtypes` = moonNum 的包，`@dtype` = 本仓 `src/dtype`（`src/adapter/moonnum/moon.pkg` 注释）
  - **包级 import 是唯一合法形式**：`.mbt` 文件级 `import` 在本 pin 报 `[3001] Invalid import declaration here`（`docs/s6-api-card.md` §3.4）
- `.gitattributes` — 仓库级行尾政策：`* text=auto eol=lf`（本机 `core.autocrlf=true` 会改写行尾，而 fixture 是字节精确产物，故政策固化进仓库）；`*.npy binary` 与 `*.npz binary`（禁止行尾转换 / 文本 diff / merge，因其 sha256 是 Oracle）；`*.bat` / `*.cmd` / `*.ps1` 保留 CRLF
- `.gitignore` — `_build/`、`.mooncakes/`、`pkg.generated.mbti`、Python 缓存（`__pycache__/`、`.venv/`、`.pytest_cache/`）、覆盖率产物（`*.coverage`、`bisect.coverage`、`uncovered.log`、`coverage-summary.txt`）、`interoperability/fixtures/`（早期命名的重复 fixture，不被任何东西引用）
- `.github/workflows/ci.yml` — CI 即「构建配置的第二真相源」，含 `MOONBIT_VERSION` / `PYTHON_VERSION` / `NUMPY_VERSION` 三个 env pin

## Platform Requirements

**Development:**
- 原生开发环境实测记录（`README.md` Performance、`CHANGELOG.md` Unreleased）：Windows 11 (25H2, build 26200) · Intel Core Ultra 5 236V (8 cores) · MoonBit `0.1.20260827 (d0aaa07)` · `moonc v0.10.11+6ff76a5f9`
- 但**代码本身不限平台**：CI 在 `ubuntu-latest` 上跑全部门禁（`moon fmt` / `check` / `test` / coverage / fixture / round-trip / CLI 冒烟）
- 必装：MoonBit 工具链（native target）+ `git`（`moon update` 需要 git 克隆 registry index）
- 跨语言验证另需：Python 3.14 + NumPy 2.3.4（pin 与 fixture 生成时一致，否则 sha256 契约可能漂移）
- 无需系统 BLAS / zlib / 任何 C 库：本仓依赖（`moonbitlang/x`、`amor2025/moonNum`）均为纯 MoonBit 或自带 C stub
- 无 Docker / 无本地数据库 / 无 devcontainer

**Production:**
- 交付形态 = **库 + CLI 可执行体**，不是长驻服务
- 库分发：Mooncakes registry（`moon add ShunjunGu/moon-npy`，v0.3.0 为首个发布版本，`CHANGELOG.md`）
- CLI 运行：`moon run cmd/main --target native -- <inspect|validate|dump> <file.npy>`；退出码契约 0/1/2（`docs/spec/acceptance.md` §13）
- 目标平台约束：native（`preferred_target`）；主构建产物路径 `_build/native/`。WASM 不在承诺范围（`_build/wasm-gc/release/` 有构建残留，但非 CI 门禁、非文档承诺）
- 无部署环境变量、无密钥、无外网调用

---

*Stack analysis: 2026-09-11*
*Update after major dependency changes*
