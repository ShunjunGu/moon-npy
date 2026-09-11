# Codebase Structure

**Analysis Date:** 2026-09-11

## Directory Layout

```
moon-npy/
├── src/                        # 库源码（9 个包，唯一产物是 .mbt + moon.pkg）
│   ├── error/                  # L1 叶子包：enum NpyError（19 构造子）
│   ├── format/                 # L2：magic / version / header-length 前缀字节布局
│   ├── dtype/                  # L2：DType / ByteOrder / Complex + descr 解析 + 逐元素 codec
│   ├── header/                 # L3：header 词法分析 + 递归下降解析 → NpyHeader
│   ├── reader/                 # L4：validate / decode → NpyMeta / NpyArray + 13 个 to_* accessor
│   ├── writer/                 # L5：encode(NpyArray) → Bytes（逐字节对齐 np.save）
│   ├── npz/                    # L5：decode_npz（只读 + 未压缩 ZIP 容器）
│   ├── cli/                    # L5：纯参数解析 + 输出渲染（零 IO）
│   └── adapter/moonnum/        # L6：S6 读方向适配 amor2025/moonNum（唯一第三方依赖）
├── cmd/main/                   # CLI 可执行薄壳（@fs 读字节 + extern "c" exit 设退出码）
├── examples/
│   ├── roundtrip/              # M4 emit harness（decode → encode → 写盘）
│   └── bench/                  # 四条读取路径的可复现微基准
├── tests/                      # 11 个 *_test.mbt（156 个 test 块）+ fixtures/
│   └── fixtures/               # 31 个 .npy + 3 个 .npz Oracle + expected.json / npz_expected.json
├── interoperability/           # NumPy Oracle 层：fixture 生成 / 校验 / 跨语言 driver（Python）
├── docs/
│   ├── spec/acceptance.md      # 仓库内唯一 spec owner（所有 §N / 附录 A 的解析目标）
│   └── s6-api-card.md          # S6 选型 go/no-go 决策记录 + 实测 API 事实
├── .github/workflows/ci.yml    # §19 CI pipeline（fmt / check / test / coverage / roundtrip / CLI）
├── .planning/codebase/         # 本目录：GSD 代码库地图（ARCHITECTURE.md / STRUCTURE.md 等）
├── .omc/                       # oh-my-claudecode 会话运行态（非源码）
├── AGENTS.md                   # 工具链实测事实 + 项目约定的权威（中文，面向 agent）
├── README.md / README_CN.md    # 用户文档（英文 / 中文双份）
├── CHANGELOG.md                # Keep a Changelog 格式，按里程碑分节
├── moon.mod                    # 模块清单（name / version / import / preferred_target）
├── .gitattributes              # 行尾策略 + *.npy / *.npz 标为 binary
├── .gitignore                  # 排除 _build/ .mooncakes/ pkg.generated.mbti / coverage 产物
└── LICENSE                     # Apache-2.0
```

## Directory Purposes

**`src/error/`：**
- Purpose: 全库唯一的失败通道类型定义
- Contains: 单个 `error.mbt`（27 行）
- Key files: `src/error/error.mbt` — `pub(all) enum NpyError`，19 构造子（13 NPY 层 + 6 NPZ 容器层），`derive(Debug)`
- `moon.pkg` imports: 无（叶子包，只有一行注释说明 "Leaf package, no deps"）
- 公开导出: `NpyError`（仅此一项，无 `pub fn`）

**`src/format/`：**
- Purpose: NPY 固定前缀的字节布局——magic、version、header-length 字段
- Contains: 单个 `format.mbt`（112 行）
- Key files: `src/format/format.mbt` — `NpyVersion`、`NpyPrefix`、`parse_prefix`、`has_magic`、`version_of`、`read_u16_le`、`read_u32_le`、`pub let magic_len : Int = 8`
- `moon.pkg` imports: `ShunjunGu/moon-npy/src/error`
- 公开导出: `NpyVersion`、`NpyPrefix`、`magic_len`、`has_magic`、`version_of`、`read_u16_le`、`read_u32_le`、`parse_prefix`

**`src/dtype/`：**
- Purpose: 元素类型（descr）解析、尺寸计算、逐元素字节解码
- Contains: 4 个 `.mbt`，按概念分文件
- Key files:
  - `src/dtype/dtype.mbt`（227 行）— `DType`、`parse_dtype`、`itemsize`、`name`、`descr_code`；私有 `is_known_unsupported_kind`、`kind_size_to_dtype`
  - `src/dtype/endian.mbt`（60 行）— `ByteOrder`、`endian_char`；私有 `is_big`、`parse_byte_order`
  - `src/dtype/codec.mbt`（154 行）— 13 个 `pub fn read_*`；私有 `read_uint`、`read_bits32`、`sext`
  - `src/dtype/complex.mbt`（16 行）— `pub(all) struct Complex { re : Double, im : Double }`
- `moon.pkg` imports: `ShunjunGu/moon-npy/src/error`（**不**依赖 `format` / `header`）
- 公开导出: `DType`、`ByteOrder`、`Complex`、`parse_dtype`、`itemsize`、`name`、`descr_code`、`endian_char`、13 个 `read_*`

**`src/header/`：**
- Purpose: 受限 Python literal 的 header 字典 → `NpyHeader`
- Contains: 3 个 `.mbt`，按 lexer / parser / model 分文件
- Key files:
  - `src/header/header.mbt`（14 行）— `pub struct NpyHeader { descr, shape, fortran_order }`（仅类型定义）
  - `src/header/lexer.mbt`（165 行）— `priv enum Token`、`lex`、`decode_span`、4 个 ASCII 分类器
  - `src/header/parser.mbt`（149 行）— `pub fn parse_header`、`parse_tokens`、`peek`
- `moon.pkg` imports: `src/error`、`src/format`、`moonbitlang/core/encoding/utf8`
- 公开导出: `NpyHeader`、`parse_header`（`Token` 是 `priv`，包外不可见）

**`src/reader/`：**
- Purpose: 校验 + 解码 + 类型化访问；依赖最深的包（4 个上游）
- Contains: 单个 `reader.mbt`（309 行）
- Key files: `src/reader/reader.mbt` — `NpyMeta`、`NpyArray`、`validate`、`decode`、13 个 `NpyArray::to_*`、2 个 chunk accessor；私有 `flat`、`flat_range`、`slice_payload`、`shape_element_count`、3 个 `Int64`/`UInt64` 上界常量
- `moon.pkg` imports: `src/error`、`src/format`、`src/header`、`src/dtype`
- 公开导出: `NpyMeta`、`NpyArray`、`validate`、`decode`、`NpyArray::to_bool` / `to_i8` / `to_i16` / `to_i32` / `to_i64` / `to_u8` / `to_u16` / `to_u32` / `to_u64` / `to_f32` / `to_f64` / `to_c64` / `to_c16` / `to_f32_chunk` / `to_f64_chunk`

**`src/writer/`：**
- Purpose: `NpyArray` → 与 `np.save` 逐字节一致的 NPY 字节
- Contains: 单个 `writer.mbt`（144 行）
- Key files: `src/writer/writer.mbt` — `pub fn encode`；私有 `py_bool`、`shape_tuple`、`version_major_minor`、`let array_align : Int = 64`
- `moon.pkg` imports: `src/error`、`src/format`、`src/header`、`src/dtype`、`src/reader`、`moonbitlang/core/encoding/utf8`
- 公开导出: `encode`（仅此一项 —— `pkg.generated.mbti` 只有一个 `pub fn`）

**`src/npz/`：**
- Purpose: 只读、未压缩的 `np.savez` ZIP 容器读取
- Contains: 单个 `npz.mbt`（284 行）
- Key files: `src/npz/npz.mbt` — `decode_npz`、`NpzArchive`、`NpzMember`、`NpzArchive::get`、`NpzArchive::names`；私有 `find_eocd`、`match_sig`、`slice_bytes`、`resolve_member_name`、`unsafe_member_name`、3 个签名常量
- `moon.pkg` imports: `src/error`、`src/format`（复用 `read_u16_le` / `read_u32_le`）、`src/reader`、`moonbitlang/core/encoding/utf8`
- 公开导出: `NpzArchive`、`NpzMember`、`decode_npz`、`NpzArchive::get`、`NpzArchive::names`

**`src/cli/`：**
- Purpose: `inspect` / `validate` / `dump` 三个子命令的全部纯逻辑（解析 + 决策 + 渲染），零 IO
- Contains: 单个 `cli.mbt`（470 行，本仓最长的源文件）
- Key files: `src/cli/cli.mbt` — `Subcommand`、`ExitCode`、`CliOutcome`、`parse_args`、`run_inspect`、`run_validate`、`run_dump`、`render_error`、`human_size`、`operational`、`ExitCode::to_int`；私有 `render_inspect` / `render_dump` / `render_failure` / `dump_values` / `render_all` / `row` / `table_rule` / `join_lines` / `group_digits` / `version_label` / `byte_order_label` / `shape_label` / `parse_limit` / `is_digits` / `usage`、`label_width` / `default_dump_limit`
- `moon.pkg` imports: `src/error`、`src/format`、`src/header`、`src/dtype`、`src/reader`、`moonbitlang/core/string`（**不** import `moonbitlang/x/fs` / `core/env` —— 这是它可被黑盒测试的前提）
- 公开导出: `Subcommand`、`ExitCode`、`CliOutcome`、`parse_args`、`run_inspect`、`run_validate`、`run_dump`、`render_error`、`human_size`、`operational`、`ExitCode::to_int`

**`src/adapter/moonnum/`：**
- Purpose: S6 读方向适配器——`NpyArray` → moonNum `NdArray`（f32/f64、小端、零元素解码）
- Contains: 单个 `adapter.mbt`（119 行）
- Key files: `src/adapter/moonnum/adapter.mbt` — `AdapterError`、`AdapterError::message`、`to_moonnum_f32`、`to_moonnum_f64`；私有 `convert`、`shape_as_ints`、`let int_max_as_uint : UInt64`
- `moon.pkg` imports: `src/dtype`、`src/reader`、`amor2025/moonNum/src/core`、`amor2025/moonNum/src/dtypes` —— `moon.pkg` 里有重要别名注释：`@core` / `@dtypes` 是 moonNum 的包，`@dtype` 是本仓的
- 公开导出: `AdapterError`、`to_moonnum_f32`、`to_moonnum_f64`、`AdapterError::message`
- 注意: 本包**不** import `src/error`（刻意不把转换层失败混进 `NpyError`）

**`cmd/main/`：**
- Purpose: CLI 可执行薄壳；只拥有两个允许的副作用——读文件字节、设进程退出码
- Contains: `main.mbt`（65 行）+ `moon.pkg`（声明 `pkgtype(kind: "executable")`）
- Key files: `cmd/main/main.mbt` — `main`、`resolve`、两个 `#cfg` 版本的 `exit_with`（native/llvm 下是 `extern "c" fn exit_with(code : Int) = "exit"`）
- `moon.pkg` imports: `ShunjunGu/moon-npy/src/cli`、`moonbitlang/x/fs`、`moonbitlang/core/env`
- 公开导出: 无（`pkg.generated.mbti` 为空 —— 可执行包不导出 API）

**`examples/roundtrip/`：**
- Purpose: M4 emit harness —— 读 `.npy` → `decode` → `encode` → 写回磁盘，供 NumPy 侧逐字节比对
- Contains: `main.mbt`（62 行）+ `moon.pkg`
- `moon.pkg` imports: `src/reader`、`src/writer`、`moonbitlang/x/fs`、`moonbitlang/core/env`
- 用法: `moon run examples/roundtrip --target native -- <in.npy> <out.npy>`

**`examples/bench/`：**
- Purpose: 四条读取路径（fs read / decode / decode+to_f32 / 逐行 chunk）的单机微基准
- Contains: `main.mbt`（210 行）+ `moon.pkg`
- `moon.pkg` imports: `src/reader`、`moonbitlang/core/bench`（别名 `@core_bench`，因为本包自身叫 `bench`）、`moonbitlang/core/encoding/utf8`、`moonbitlang/core/json`、`moonbitlang/x/fs`
- 用法: `moon run examples/bench --target native --release`；输入在进程内合成（`synthetic_npy_100x768_f32`），不依赖 fixture

**`tests/`：**
- Purpose: 全部单元 / 集成 / 性质 / fuzz / 安全测试（黑盒，用 `@pkg.` 前缀访问公共 API）
- Contains: 11 个 `*_test.mbt`，共 **156** 个 `test` 块；`moon.pkg` 用 `import { ... } for "test"` 声明 test-only 依赖（含全部 9 个 src 包 + moonNum core + `core/quickcheck/splitmix` + `x/fs`）
- Key files:
  - `tests/npy_test.mbt`（15 test）— M1 header pipeline 集成测试；`load_fixture` helper 被同包其它测试复用
  - `tests/reader_test.mbt`（25 test）— M2 Reader，正例钉 `expected.json` 的 `flat_values`
  - `tests/writer_test.mbt`（4 test）— M3 逐字节 round-trip（对全部 Oracle fixture）
  - `tests/dtype_test.mbt`（16 test）— M2 descr 解析正/负例
  - `tests/edge_test.mbt`（17 test）— M5 边缘用例（合成、非 64 对齐）
  - `tests/fuzz_test.mbt`（3 test）— §18 totality，确定性 splitmix，7000 次迭代
  - `tests/security_test.mbt`（3 test）— object dtype 全端形式拒绝性质
  - `tests/property_test.mbt`（1 test）— `decode → encode` 逐字节恒等性质（Python-free）
  - `tests/cli_test.mbt`（34 test）— CLI 纯逻辑，断言 §13 精确输出
  - `tests/adapter_test.mbt`（10 test）— S6 适配器，含 BE 拒绝用例
  - `tests/npz_test.mbt`（28 test）— C1 容器读取 + NPZ 性质测试
- 测试内 helper 惯例：文件顶部定义无 `pub` 的 `fn`（如 `load_fixture`、`decode_fixture`、`expect_dtype`、`npy_v1`、`bytes_equal`），`///|` 分隔

**`tests/fixtures/`：**
- Purpose: NumPy Oracle 真实产物，是全部正例断言的 ground-truth
- Contains: **31** 个 `.npy` + **3** 个 `.npz` + `expected.json` + `npz_expected.json`
- Key files: `expected.json` — 每 fixture 记录 `version` / `descr` / `shape` / `fortran_order` / `header_len` / `data_offset` / `sha256` / `values`；同时是 `interoperability/roundtrip.py` 的 fixture 清单来源
- 命名规则: `<dtype>_<shape>_<order>_<endian>_v<version>.npy`（如 `f4_2x3_c_le_v1.npy`、`c16_4_c_be_v1.npy`、`i2_2x2x2_c_le_v1.npy`）；`.npz` 用 `npz_<描述>_c_le_v1.npz`
- 入库集 = P0 种子集（3）× + M2 codec 定向矩阵（28）；`--full` 展开的完整矩阵**不入库**

**`interoperability/`：**
- Purpose: 跨语言兼容性验证层（Python 侧），moon-npy 的正确性 Oracle
- Contains: 4 个 `.py` + `README.md`
- Key files:
  - `interoperability/generate_fixtures.py` — 用 `numpy.lib.format` 生成 `.npy` / `.npz` fixture，并从**真实产物字节**反推 `expected.json`；`--check` 走 sha256 drift 门禁，`--full` 展开完整矩阵
  - `interoperability/verify_moonbit_output.py` — 单一 Oracle 真相源；`np.load` + `array_equal` + `--byte-exact` 逐字节比对，退出码 0/1/2
  - `interoperability/roundtrip.py` — M4 跨语言 driver：`expected.json` 驱动，逐 fixture `emit`（`moon run examples/roundtrip`）+ `verify`，聚合 `[PASS]/[FAIL]`
  - `interoperability/probe_npz.py` — C1 Task 0 探针（**非交付 Oracle**）：dump `np.savez` / `np.savez_compressed` 的 ZIP 字节布局，锁定本地头占位符与 zip64 extra field 两条事实
  - `interoperability/README.md` — 锁定版本表（NumPy 2.3.4 / Python 3.14）、文件说明、设计约束、CI 集成映射

**`docs/`：**
- Purpose: 仓库内规范与决策记录
- Contains: `spec/acceptance.md`（227 行）+ `s6-api-card.md`
- Key files:
  - `docs/spec/acceptance.md` — **in-repo spec owner**。§0 是 §N 引用解析索引表；附录 A 是 NPY 字节契约（偏移表 / header 语法 / 对齐填充 / 版本选择真相 / Oracle 值可见性）；§12 NpyError 契约、§13 CLI 退出码纪律、§14 覆盖率阈值、§15 兼容矩阵、§16 双向 round-trip、§19 CI 门禁、§21 Oracle 原则、§23 第一阶段 DoD
  - `docs/s6-api-card.md` — S6 选型 go/no-go（moonNum GO / numbt NO-GO）、moonNum 实测 API 签名、读方向转换 6 步契约、`is_little_endian()` 字面量 `true` 的诚实标注、生态位交叉声明
- 注: `docs/plans/` 被文档多处引用但**不在仓库内**（外部历史计划文档，已明确不再作为权威引用目标）

**`.github/workflows/`：**
- Purpose: CI pipeline 定义
- Contains: `ci.yml`（单 job `roundtrip`，`ubuntu-latest`）
- Key facts: env pin `MOONBIT_VERSION: "0.10.11+6ff76a5f9"` / `PYTHON_VERSION: "3.14"` / `NUMPY_VERSION: "2.3.4"`；步骤顺序 = `moon update` → `moon fmt` + `git diff --exit-code` → `moon check --target native` → `moon test --target native` → coverage gate（awk 强制 core parser ≥90% / overall ≥80%）→ `generate_fixtures.py --check` → `roundtrip.py -v` → CLI inspect/validate/dump + 退出码 0/1/2 断言

## Key File Locations

**Entry Points:**
- `cmd/main/main.mbt`: CLI 可执行入口（`main` → `resolve` → `println` + `exit_with`）
- `examples/roundtrip/main.mbt`: M4 emit harness（CI `roundtrip.py` 驱动）
- `examples/bench/main.mbt`: 性能基准（进程内合成输入）
- `src/reader/reader.mbt`: 库的主入口 `validate` / `decode`
- `src/writer/writer.mbt`: 库的主入口 `encode`
- `src/npz/npz.mbt`: 容器入口 `decode_npz`

**Configuration:**
- `moon.mod`: 模块清单 —— `name = "ShunjunGu/moon-npy"`、`version = "0.3.0"`、`preferred_target = "native"`、`import { "moonbitlang/x@0.5.1", "amor2025/moonNum@0.1.0" }`
- `src/*/moon.pkg`、`cmd/main/moon.pkg`、`tests/moon.pkg`、`examples/*/moon.pkg`: 包级 import 清单（**依赖方向的唯一真相源**）；可执行包加 `pkgtype(kind: "executable")`；test 依赖写在 `import { ... } for "test"`
- `.github/workflows/ci.yml`: CI 门禁 + 工具链 pin
- `.gitattributes`: `* text=auto eol=lf`、`*.npy binary`、`*.npz binary`（byte-exact 产物禁止行尾转换）
- `.gitignore`: `_build/`、`.mooncakes/`、`pkg.generated.mbti`、`*.coverage`/`bisect.coverage`/`coverage-summary.txt`、`interoperability/fixtures/`
- 注: `moon.lock` 在 `.gitignore` 注释里被声明「需入库以保证依赖可复现」，但**当前工作树中不存在该文件**

**Core Logic:**
- `src/format/format.mbt`: magic / version / header-length 前缀解析
- `src/header/lexer.mbt` + `src/header/parser.mbt`: header 字典的词法与语法
- `src/dtype/dtype.mbt`: descr → `(DType, ByteOrder)`，含 object array 安全拒绝
- `src/dtype/codec.mbt`: 全部 13 个 dtype 的手工字节序拼装
- `src/reader/reader.mbt`: 全部校验规则 + 载荷对账 + 13 个 accessor
- `src/writer/writer.mbt`: 字节级重建 header + 最小 64 字节对齐
- `src/npz/npz.mbt`: ZIP 结构解析 + 五类安全拒绝
- `src/cli/cli.mbt`: 全部 CLI 决策与渲染
- `src/adapter/moonnum/adapter.mbt`: S6 三条前置拒绝门 + 载荷移交
- `src/error/error.mbt`: 失败类型全集

**Testing:**
- `tests/`: 11 个 `*_test.mbt`（黑盒，156 个 test 块）
- `tests/fixtures/`: 31 `.npy` + 3 `.npz` Oracle + `expected.json` / `npz_expected.json`
- `tests/moon.pkg`: test-only 依赖声明
- `interoperability/roundtrip.py` + `verify_moonbit_output.py`: 跨语言验收（`moon test` 覆盖不到的一环）

**Documentation:**
- `README.md` / `README_CN.md`: 用户文档双份（Ecosystem Position / Status / Features / Installation / Quick Start / Round-trip demo / Performance / Compatibility Matrix / CLI Usage / Library API / Ecosystem Adapter / Architecture / Layout / Limitations / Security / Development / CI / License）
- `AGENTS.md`: 面向 agent 的工具链事实与项目约定（中文，M0 gate 实测固化，**权威**）
- `docs/spec/acceptance.md`: 验收边界 spec owner（§N 引用解析目标）
- `docs/s6-api-card.md`: S6 决策记录
- `interoperability/README.md`: Oracle 层说明（锁定版本 / 文件表 / 设计约束 / CI 映射）
- `CHANGELOG.md`: Keep a Changelog 格式，按里程碑分节（`[Unreleased]` / `[v0.3.0]` / …）

**"我想改 X → 去 Y" 速查表：**

| 我想改… | 主文件 | 连带要改 |
|---|---|---|
| 新增 / 修改 dtype | `src/dtype/dtype.mbt`（枚举 + `itemsize` / `name` / `descr_code` / `kind_size_to_dtype`） | `src/dtype/codec.mbt`（`read_*`）、`src/reader/reader.mbt`（`to_*` accessor）、`src/cli/cli.mbt::dump_values` + `render_error`（穷尽 match）、`src/adapter/moonnum/adapter.mbt`（若 moonNum 有对应类型）、`README.md` 兼容矩阵 |
| 新增 `NpyError` 变体 | `src/error/error.mbt` | `src/cli/cli.mbt::render_error`（**穷尽 match 会编译失败**，必须同步）、`README.md` Library API 的 enum 块、`docs/spec/acceptance.md` §12 变体清单、对应测试 |
| 改 header 语法 / 词法 | `src/header/lexer.mbt` | `src/header/parser.mbt`、`docs/spec/acceptance.md` §7.3、`tests/npy_test.mbt` / `tests/edge_test.mbt` |
| 改字节偏移 / magic / version | `src/format/format.mbt` | `src/writer/writer.mbt`（发射端）、`docs/spec/acceptance.md` 附录 A §7.2 |
| 改校验规则 | `src/reader/reader.mbt::validate` | `tests/fuzz_test.mbt`（`decode == validate + 切片` 契约）、`tests/edge_test.mbt` |
| 改产物字节 / 对齐 | `src/writer/writer.mbt`（`array_align` / `shape_tuple` / `py_bool`） | `tests/writer_test.mbt`、`tests/property_test.mbt`、`docs/spec/acceptance.md` §7.4 / §16 |
| 改 CLI 输出格式 | `src/cli/cli.mbt`（`render_*` / `row` / `table_rule` / `human_size` / `group_digits`） | `tests/cli_test.mbt`（钉精确输出）、`README.md` CLI Usage、`.github/workflows/ci.yml` 的 grep、`docs/spec/acceptance.md` §13 |
| 改 CLI IO / 退出码行为 | `cmd/main/main.mbt` | `src/cli/cli.mbt::ExitCode`、`docs/spec/acceptance.md` §13、README CLI Usage |
| 改 NPZ 容器行为 | `src/npz/npz.mbt` | `tests/npz_test.mbt`、`README.md` Security 容器层小节、`docs/spec/acceptance.md`、`interoperability/probe_npz.py` |
| 改适配器支持范围 | `src/adapter/moonnum/adapter.mbt` | `tests/adapter_test.mbt`、`docs/s6-api-card.md`、`README.md` Ecosystem Adapter |
| 新增 fixture | `interoperability/generate_fixtures.py`（`p0_specs` / `m2_matrix_specs` / `committed_specs`） | 重跑生成脚本落 `tests/fixtures/`、`docs/spec/acceptance.md` §15、`README.md` 的 fixture 计数 |
| 改覆盖率阈值 | `.github/workflows/ci.yml` 的 awk gate | `docs/spec/acceptance.md` §14（**必须同步**，此节自述「改阈值须同步改两处」） |
| 改工具链 pin | `.github/workflows/ci.yml` env | `AGENTS.md` §0、`docs/spec/acceptance.md` §19 |
| 改项目范围 / 限制 | `README.md` Limitations | `README_CN.md`、`CHANGELOG.md`、`docs/spec/acceptance.md` §5 附近 |

## Naming Conventions

**Files:**
- `snake_case.mbt`: 全部 MoonBit 源文件（`dtype.mbt`、`codec.mbt`、`endian.mbt`、`complex.mbt`、`header.mbt`、`lexer.mbt`、`parser.mbt`、`reader.mbt`、`writer.mbt`、`npz.mbt`、`cli.mbt`、`adapter.mbt`、`format.mbt`、`error.mbt`）
- **按概念拆文件而非按类型拆**：`src/dtype/` 4 个文件各占一个概念（类型枚举 / 字节序 / 元素 codec / complex 结构）；`src/header/` 3 个文件分模型 / 词法 / 语法
- `*_test.mbt`: 黑盒测试（本仓全部 11 个测试文件都是黑盒，无 `*_wbtest.mbt`）
- `main.mbt`: 每个可执行包（`cmd/main`、`examples/roundtrip`、`examples/bench`）的唯一入口文件名
- `moon.pkg` / `moon.mod`: 包 / 模块清单，**无 `.json` 后缀**（`AGENTS.md` §1 明确记录这是对旧假设的修正）
- `pkg.generated.mbti`: `moon info` 生成的接口快照（被 `.gitignore` 排除）
- `*.npy` / `*.npz`: 二进制 fixture（`.gitattributes` 标为 `binary`）
- `README.md` / `README_CN.md`: 中英双份大写下划线形式；`AGENTS.md` / `CHANGELOG.md` / `LICENSE` 全大写
- `UPPERCASE.md`: 治理与用户文档（`AGENTS.md`、`CHANGELOG.md`、`README.md`）

**Directories:**
- `lowercase` 单词：`src/error/`、`src/format/`、`src/dtype/`、`src/header/`、`src/reader/`、`src/writer/`、`src/npz/`、`src/cli/`、`docs/`、`tests/`、`examples/`
- `adapter/<libname>`: 适配器按**目标库名**嵌套（`src/adapter/moonnum/`）；这是本仓唯一的嵌套 src 包
- `lowercase` 组合: `cmd/main/`、`examples/roundtrip/`、`examples/bench/`
- 复数用于集合: `tests/`、`examples/`、`docs/`

**Special Patterns:**
- **`///|` 顶层块分隔符**：每个顶层定义（含 `pub fn` / `priv fn` / `let` / `enum` / `struct` / `test`）前必须有 `///|`，`moon fmt` 会规整 —— 这是本工具链的强制惯例（`AGENTS.md` §8）
- **`//` 文件头注释**：每个源文件以一段英文 `//` 块开头，说明本文件的 plan `§N` 出处与职责边界；`moon.pkg` 用 `//` 注释说明本包的定位与别名
- **`test "snake_case_name" { ... }`**：测试名用 snake_case 动词短语（如 `parse_args_inspect`、`object_dtype_refused_all_endian_forms`、`dump_covers_all_13_dtypes`）
- **`Type::method` 定义形式**：方法式函数写作 `pub fn NpyArray::to_f32(self : NpyArray)`、`pub fn NpzArchive::get(self : NpzArchive, key : String)`、`pub fn ExitCode::to_int(self : ExitCode)`、`pub fn AdapterError::message(self : AdapterError)` —— 定义在类型的所属包内
- **文件级 `import` 非法**：本工具链 pin 下 `.mbt` 里写 `import` 报 `[3001]`，导入**必须**写进 `moon.pkg`（`docs/s6-api-card.md` §3.4 / §7 记录）
- **私有 helper 惯例**：包内 helper 一律裸 `fn`（无 `pub`），`//` 注释说明其调用契约；包内中间类型用 `priv enum`（如 `Token`）

**Types:**
- `PascalCase`: `NpyError`、`DType`、`ByteOrder`、`Complex`、`NpyHeader`、`NpyPrefix`、`NpyVersion`、`NpyMeta`、`NpyArray`、`NpzArchive`、`NpzMember`、`AdapterError`、`Subcommand`、`ExitCode`、`CliOutcome`、`Token`
- 枚举构造子 `PascalCase`: `InvalidMagic`、`UnsupportedDType(String)`、`MissingHeaderField(String)`、`V1_0` / `V2_0` / `V3_0`（版本用下划线连缀）、`Complex64` / `Complex128`、`NpzZip64Unsupported`、`Little` / `Big` / `NotApplicable` / `Native`、`Inspect` / `Validate` / `Dump(Int)`
- 命名前缀惯例：容器层类型一律 `Npz*` 前缀（`NpzArchive` / `NpzMember` / `NpzBadStructure` / `NpzZip64Unsupported`…），NPY 层类型一律 `Npy*` 前缀（`NpyError` / `NpyHeader` / `NpyPrefix` / `NpyVersion` / `NpyMeta` / `NpyArray`）—— 错误变体因此自带层归属
- 类型名刻意避开歧义：`Complex` 而非 `Complex64`/`Complex128`（把宽度留给 `DType` 变体）；`DType`（本仓）vs `@dtypes.Dtype`（moonNum）大小写不同，`moon.pkg` 别名注释专门提醒

**Functions:**
- `snake_case`: `parse_dtype`、`parse_header`、`parse_prefix`、`parse_args`、`has_magic`、`version_of`、`read_u16_le`、`read_u32_le`、`read_f32`、`itemsize`、`descr_code`、`endian_char`、`validate`、`decode`、`encode`、`decode_npz`、`run_inspect`、`run_validate`、`run_dump`、`render_error`、`human_size`、`operational`
- 长度 / 尺寸类函数不加后缀：`itemsize(dt)`、`name(dt)`、`descr_code(dt)`、`endian_char(order)`
- 谓词用 `is_` 前缀: `is_big`、`is_space`、`is_digit`、`is_ident_start`、`is_ident_char`、`is_digits`、`is_known_unsupported_kind`
- 私有 helper 无前缀区分，靠无 `pub` 识别

**Constants:**
- `snake_case` 全小写 `pub let`: `pub let magic_len : Int = 8`（`src/format/format.mbt`）
- `snake_case` 全小写包内 `let`: `array_align`、`label_width`、`default_dump_limit`、`int64_max`、`uint64_max`、`int64_max_as_uint`、`int_max_as_uint`、`sig_local` / `sig_central` / `sig_eocd`
- 不用 `SCREAMING_SNAKE_CASE`（与 C / Python 惯例不同）

**Visibility:**
- `pub fn` / `pub struct` / `pub(all) enum`: 公共 API 的默认形式
- `pub(all)`: **只在需要包外构造时**使用 —— `NpyError`（测试要断言具体变体）、`DType` / `ByteOrder` / `Complex`（测试要构造期望值）、`NpyVersion`、`NpzMember`、`AdapterError`、`Subcommand` / `ExitCode`（测试要构造以断言结果）。源码注释反复点明这条理由（"so tests can construct the variants, not just match them"）
- 裸 `pub struct`: 需要的只是**读字段**而非构造时 —— `NpyHeader` / `NpyPrefix` / `NpyMeta` / `NpyArray` / `NpzArchive` / `CliOutcome`。这是本仓最重要的可见性模式（把不变式编码进类型系统）
- 包内私有: 裸 `fn`（无 `pub`），或 `priv enum Token`

## Where to Add New Code

**新增一个 dtype（如 float16 / complex256）：**
- 主代码: `src/dtype/dtype.mbt`（`DType` 枚举 + `itemsize` + `name` + `descr_code` + `kind_size_to_dtype` 分支；若是「已知但不支持」则只需从 `is_known_unsupported_kind` 里移除对应字符）
- 元素解码: `src/dtype/codec.mbt`（新增 `pub fn read_xxx`）
- 访问器: `src/reader/reader.mbt`（新增 `pub fn NpyArray::to_xxx`）
- CLI 渲染: `src/cli/cli.mbt::dump_values`（穷尽 match 会强制你加分支）
- 适配器（可选）: `src/adapter/moonnum/adapter.mbt`（若 moonNum 有对应 `@dtypes.Dtype`）
- 测试: `tests/dtype_test.mbt`（descr 正负例）+ `tests/reader_test.mbt`（值断言）
- Fixture: `interoperability/generate_fixtures.py` 的 `m2_matrix_specs()`
- 文档: `README.md` 兼容矩阵 + Library API + `docs/spec/acceptance.md` §15

**新增一个 `NpyError` 变体：**
- 定义: `src/error/error.mbt`
- **必须同步**: `src/cli/cli.mbt::render_error`（穷尽 match，不加分支编译失败）
- 文档: `README.md` Library API 的 enum 块、`docs/spec/acceptance.md` §12 的变体清单
- 测试: 在对应测试文件里断言**精确变体**（不接受泛化失败）
- 反例提醒: 如果失败**不是**「`.npy` 文件本身有问题」，考虑像 `AdapterError` 那样另立包内错误类型，而不是扩 `NpyError`

**新增一个 CLI 子命令：**
- 枚举: `src/cli/cli.mbt::Subcommand`（加变体）
- 解析: `src/cli/cli.mbt::parse_args`（加分支 + 尾参校验）
- 纯逻辑: `src/cli/cli.mbt::run_<name>`（返回 `CliOutcome`）
- 分派: `cmd/main/main.mbt::resolve`（穷尽 match 会强制你加分支）
- 渲染: `src/cli/cli.mbt::render_<name>`
- 测试: `tests/cli_test.mbt`
- 文档与门禁: `README.md` CLI Usage、`docs/spec/acceptance.md` §13、`.github/workflows/ci.yml` CLI 冒烟步骤

**新增一个包的 helper：**
- 同包私有 helper: 直接写裸 `fn` 到该包已有的 `.mbt`（或按概念新开一个 `snake_case.mbt`，如 `src/dtype/complex.mbt` 的做法）
- 若要跨包复用: 必须提升为 `pub fn` 并想清楚它在哪一层（`slice_payload` 在 `reader` 与 `npz` 之间重复就是**因为不愿引入循环依赖**——这是已记录的可接受取舍，不要轻易"优化"成共享）

**新增适配目标（如 numbt / 其他数组库）：**
- 目录: `src/adapter/<libname>/`（对齐 `src/adapter/moonnum/` 的形态）
- 文件: `moon.pkg`（import 本仓 `src/dtype` + `src/reader` + 目标库子包）+ `adapter.mbt`（自带 `<Lib>Error` enum + `to_<lib>_xxx` 函数）
- 依赖: `moon.mod` 加 `moon add <owner/repo>`
- 测试: `tests/<libname>_test.mbt`
- 决策记录: `docs/` 下加一份选型 card（对齐 `docs/s6-api-card.md`）

**新增测试：**
- 单元 / 集成: `tests/<topic>_test.mbt`（黑盒，`@pkg.` 前缀）
- 依赖声明: `tests/moon.pkg` 的 `import { ... } for "test"` 块
- 断言风格: 正例钉 `tests/fixtures/expected.json` 的值；负例断言**精确 `NpyError` 变体**
- fixture: 需要新字节数据时改 `interoperability/generate_fixtures.py` 并重跑，不要手写 `.npy`
- fuzz / 性质测试: 用固定种子的 `splitmix`（`tests/fuzz_test.mbt` 范式），禁止 wall-clock 熵

**新增 fixture：**
- 生成器: `interoperability/generate_fixtures.py`（`p0_specs()` / `m2_matrix_specs()` / `committed_specs()`）
- 产物: 重跑脚本落地到 `tests/fixtures/`，`expected.json` 的 `count` 同步
- CI: `--check` drift 门禁自动覆盖
- 文档: `README.md` 的 fixture 计数（多处出现）+ `docs/spec/acceptance.md` §15

**新增文档章节：**
- 用户文档: `README.md` **与** `README_CN.md`（双份必须同步）
- 验收边界: `docs/spec/acceptance.md`（新 `§N` 要同时补 §0 的引用解析索引表）
- 工具链事实: `AGENTS.md`
- 变更记录: `CHANGELOG.md`（Keep a Changelog 格式）

## Special Directories

**`_build/`：**
- Purpose: MoonBit 构建输出与运行期临时产物
- Source: `moon build` / `moon test` / `moon run` 自动生成；`examples/bench/main.mbt` 还会往里写 `_build/bench_100x768_f32.npy`（bench 的合成输入落盘）
- Committed: **否**（`.gitignore` 首条）

**`.mooncakes/`：**
- Purpose: 依赖缓存，`moon add` 后解压的第三方包源码
- Source: 由 `moon` 工具链从 registry 拉取
- Committed: **否**（`.gitignore`）；当前含 `amor2025/` 与 `moonbitlang/` 两个子树

**`pkg.generated.mbti`（分散在各包目录）：**
- Purpose: `moon info` 生成的包接口快照，是「本包公开导出」的权威清单
- Source: `moon info`
- Committed: **否**（`.gitignore` 明确排除），但工作树中实际存在（`src/*/`、`cmd/main/`、`tests/`、`examples/roundtrip/`）；`.github/workflows/ci.yml` 无 `moon info` 步骤，故 CI 不校验其 diff

**`bisect.coverage` / `coverage-summary.txt`：**
- Purpose: `moon coverage` 的覆盖率产物
- Source: `moon test --enable-coverage` → `moon coverage analyze` → `moon coverage report -f summary`
- Committed: **否**（`.gitignore`，含 `*.coverage` 通配）
- 注意: `coverage-summary.txt` 在 Windows 上是 **UTF-16 LE** 编码（直接 `cat` 会显示为带空字节的乱码），这是因为 `moon coverage report` 的 Windows 输出编码；CI（Linux）上是 UTF-8，awk gate 依赖这一点

**`tests/fixtures/`：**
- Purpose: NumPy Oracle 真实产物（`.npy` / `.npz`）+ 反推出的期望值 JSON
- Source: `interoperability/generate_fixtures.py`（pinned NumPy 2.3.4）
- Committed: **是**（是交付物与验收依据）；`.gitattributes` 把 `*.npy` / `*.npz` 标为 `binary`，禁止行尾转换与文本 diff —— byte-exact 契约依赖其 sha256 跨平台恒定

**`interoperability/fixtures/`：**
- Purpose: 早期草稿命名方案（`f32_2x3_v10/v20/v30`）留下的废弃副本
- Source: 已被 `tests/fixtures/` 取代，与后者逐字节相同，无任何引用
- Committed: **否**（`.gitignore` 末尾专门 + 注释说明，防止重新入暂存区）

**`.github/`：**
- Purpose: CI 配置
- Contains: `workflows/ci.yml` 单文件
- Committed: 是

**`.omc/`：**
- Purpose: oh-my-claudecode 的会话运行态（`state/` 下的 hud / mission / subagent tracking JSON 等）
- Source: OMC 编排层自动写入
- Committed: **否**（运行时产物，非源码）

**`.planning/`：**
- Purpose: GSD 代码库地图与规划产物
- Contains: `codebase/`（本目录 —— `ARCHITECTURE.md` / `STRUCTURE.md` 等）
- Committed: 由项目方决定（当前不在 `.gitignore` 中）

**`docs/plans/`（**不存在**）：**
- `docs/spec/acceptance.md`、`docs/s6-api-card.md`、`CHANGELOG.md` 多处引用 `docs/plans/2026-09-09-moon-npy-v0.2.0-stretch.md` 等外部历史计划文档，但该目录**不在仓库内**。`docs/spec/acceptance.md` 已明确声明「仓库外早期计划文档中的同类编号仅作历史来源，不再是任何交付物、CI 门禁或 fixture 契约的权威引用目标」。所有 `§N` 引用一律解析到 `docs/spec/acceptance.md`。

---

*Structure analysis: 2026-09-11*
*Update when directory structure changes*
