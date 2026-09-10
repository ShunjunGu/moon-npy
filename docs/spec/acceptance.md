# moon-npy 验收边界规范（in-repo spec owner）

> **本文件是仓库内的规范所有者（spec owner）**：它承载 CI 与 fixture 所依赖的**验收边界**
> （acceptance boundary），并使治理文件、`.github/workflows/ci.yml`、`interoperability/`、
> `tests/fixtures/expected.json` 中出现的 `§N` / `附录 A` 引用**能在克隆内解析到真实小节**。
>
> **小节编号（§7.2 / §7.4 / §8.4 / §13 / §14 / §15 / §16 / §19 / §23 / 附录 A）与仓库各处
> 的 `§` 引用一一对应**，编号即本文件的锚点。仓库外早期计划文档中的同类编号仅作历史来源，
> **不再是任何交付物、CI 门禁或 fixture 契约的权威引用目标**。
>
> **事实来源**：本文件所有字节布局、退出码、阈值、矩阵、门禁事实**均取自仓库内实际代码与产物**
> （`src/cli/cli.mbt`、`interoperability/generate_fixtures.py`、`.github/workflows/ci.yml`、
> `tests/fixtures/expected.json`），逐条标注代码位置，**非照抄外部计划**。若代码与本文件冲突，
> 以代码为准并同步修订本文件。

## 0. 引用解析索引（§-reference index）

仓库内以 `§N` / `附录 A` 形式引用验收边界处，按下表解析到克隆内的真实所有者：

| 引用记号 | 含义 | 克隆内解析位置 |
|---|---|---|
| `§7.2` | NPY 字节偏移表 | 本文件 §7.2 |
| `§7.3` | Header 受限 Python literal 语法 | 本文件 §7.3 |
| `§7.4` | 64 字节对齐 / `\n` 收尾 | 本文件 §7.4 |
| `§8.4` | 版本选择真相（`np.save` 恒 1.0） | 本文件 §8.4 |
| `§9.2` | 32 位 `Int` 溢出纪律 | `src/reader/reader.mbt`、`src/dtype/`（溢出守卫实现） |
| `§12` | `NpyError` 枚举契约 | `src/error/error.mbt`；本文件 §12 |
| `§13` | CLI 命令与退出码纪律 | 本文件 §13（源 `src/cli/cli.mbt`） |
| `§14` | 覆盖率阈值 | 本文件 §14（源 `.github/workflows/ci.yml`） |
| `§15` | 兼容矩阵 / 入库 fixture 集契约 | 本文件 §15（源 `generate_fixtures.py`） |
| `§16` | 双向 round-trip 语义 | 本文件 §16（源 `interoperability/roundtrip.py`） |
| `§18` | totality / fuzz 不变式 | `tests/fuzz_test.mbt`、`tests/property_test.mbt` |
| `§19` | CI 流水线门禁 | 本文件 §19（源 `.github/workflows/ci.yml`） |
| `§21` | Oracle = NumPy 真实行为 | 本文件 §21（源 `generate_fixtures.py`） |
| `§23` | 第一阶段硬目标（DoD） | 本文件 §23 |
| `附录 A` | fixture 字节契约 | 本文件 附录 A（源 `generate_fixtures.py::parse_npy`） |
| `附录 B` | 工具链实测命令 | `AGENTS.md` §0 / §8（MoonBit 工具链事实） |

> 其它编号（如 `§5`「明确不做什么」、`§6` Stretch、`§29` Demo）属仓库特性/范围说明，
> 权威落点在 `README.md` 的 Limitations / Round-trip demo 小节，非本验收规范的所有权范围。

---

## 附录 A — NPY 字节契约（fixture 真相）

事实源：`interoperability/generate_fixtures.py`（`MAGIC_PREFIX`/`MAGIC_LEN`/`ARRAY_ALIGN` 常量、
`parse_npy()`、`build_entry()`、`make_values()`、`effective_fortran_order()`、`write_npy()`）。
`generate_fixtures.py` 用 pinned NumPy（2.3.4）经 `numpy.lib.format` 生成 `.npy`，再从**实际写出的
字节**反推 `tests/fixtures/expected.json`——expected.json 的每个字段皆解析自 NumPy 真实产物。

### 7.2 字节偏移表

| 字段 | v1.0 | v2.0 / v3.0 |
|---|---|---|
| Magic `\x93NUMPY` | 偏移 0–5（6 字节） | 同 |
| major / minor | 偏移 6 / 7 | 同 |
| header 长度字段 | 偏移 8–9，**uint16 LE** | 偏移 8–11，**uint32 LE** |
| header 正文起始 | **偏移 10**（`MAGIC_LEN+2`） | **偏移 12**（`MAGIC_LEN+4`） |
| 数据起始偏移 `data_offset` | `10 + header_len` | `12 + header_len` |

`parse_npy()` 判定：`raw[:6] != b"\x93NUMPY"` → `bad magic`；`major == 1` 读 uint16@8、
`major in (2,3)` 读 uint32@8、其它 → `unsupported version`。`MAGIC_LEN == 8`（magic 6 + version 2），
故 header 长度字段恒从偏移 8 起。

### 7.3 Header 语法（受限 Python literal，不是 JSON）

典型 Header（NumPy 实测原样）：`{'descr': '<f4', 'fortran_order': False, 'shape': (2, 3), }`。

- 必须解析三个关键字段：`descr`、`fortran_order`、`shape`（`parse_npy()` 对缺失键报错）。
- Header **不是 JSON**：`False`（非 `false`）、结尾逗号 `(2, 3), }`、单元素元组 `(5,)`、0-d 标量 `()`
  均非合法 JSON。`parse_npy()` 用 `ast.literal_eval` 解析。
- Reader 实现约束：直接在 `Bytes` 上逐字节判定 ASCII，不把 header 字节先转 MoonBit `String`。

### 7.4 对齐与填充

- NumPy 用**空格（0x20）填充** header，并以**单个 `\n`（0x0a）收尾**，使 `data_offset` 对齐到
  **64 字节**（`ARRAY_ALIGN == 64`）。`parse_npy()` 断言 `header_bytes` 以 `\n` 结尾，否则报
  `§7.4 violation`；生成器 `generate()` 对每个产物自校验 `aligned_64` 与 `fortran_order`。
- **Writer（验收要求）**：产物须与 `np.save`/`write_array` **逐字节一致**（含 64 对齐与空格填充），
  round-trip 字节比对才能通过（见 §16）。
- **Reader（禁止假设对齐）**：只按 §7.2 读 `header_len` 并消费对应字节，**容忍任意填充/对齐**，
  不得因「未对齐 64」判定文件非法。

### 8.4 版本选择真相

`np.save(简单数组)` 对简单数组**恒只产出 1.0**。故 v2.0/v3.0 必须显式
`numpy.lib.format.write_array(f, arr, version=(2,0))` / `(3,0)`——`write_npy()` 正是此规则的实现：
`version == (1,0)` 走 `np.save`，否则走 `write_array(version=…)`。v3.0 覆盖策略用
`write_array(plain float32, version=(3,0))` 验证 uint32 header 长度解析与 UTF-8 header 读取，
**不引入 structured dtype**。

### A.5 Oracle 值与差异可见性

`make_values()` 刻意不用全 0（会掩盖字节序/偏移 bug）：数值用 `arange` 铺 `0..n-1`；bool 用奇偶交替
（`i % 2 == 0`）；complex 取 `im = 2 * re` 且**故意不相等**，使实部/虚部读反会在 Oracle 比对中失败。
`effective_fortran_order()` 复现 NumPy 写盘规则：仅当 `f_contiguous and not c_contiguous` 才记 `True`
（1-D / 0-D / `(1,1,1,1)` 等同时双连续的数组记 `False`）。`expected.json` 中 complex 序列化为 `[re, im]`
二元组——**纯 JSON 侧约定**，MoonBit 读的是 `.npy` 字节而非该字段。`values` 为 **storage-order** 真值。

---

## §13 CLI 命令与退出码纪律

事实源：`src/cli/cli.mbt`（`Subcommand`、`ExitCode`、`to_int()`、`parse_args()`、`run_*`、`render_*`）。

- **子命令**：`Inspect`、`Validate`、`Dump(Int)`（`Dump` 携带已解析的 `--limit`）。`convert` /
  `benchmark` 属 Stretch，**故意缺席**。
- **退出码**（`ExitCode::to_int`，两层非零码不得合并）：

  | 枚举 | 数值 | 语义（源注释） |
  |---|---|---|
  | `Success` | **0** | 文件是格式良好的 NPY 数组 |
  | `Invalid` | **1** | `validate()` 产出 `NpyError`（内容非法） |
  | `Operational` | **2** | 文件打不开，或用法错误 |

- **argv 索引**：`argv[0]` = exe 路径，子命令 = `argv[1]`，文件路径 = `argv[2]`。
  `parse_args()`：参数 `< 3` → 用法 `Err`（→ `Operational`）；`inspect`/`validate` 只接受恰好一个路径
  （多余参数 → 用法错误）；`dump` 可选 `--limit N`（`N` 须为纯 ASCII 数字），缺省 limit = `10`
  （`default_dump_limit`）；非法 `--limit` 或溢出 → 用法错误（→ `2`），库代码不对可描述输入 trap。
- **输出**：`inspect` 成功渲染元数据表（标签列宽 `label_width = 14`、26 字符 `U+2500` 分隔线、
  `Data size` 用二进制单位两位小数）；`validate` 成功打印 `✓ <path> is a valid NPY file`（退出 0）；
  三命令共用同一 `✗ <path>` + 结构化错误块（退出 `Invalid` 1）。
- **CI 实测退出码**（`.github/workflows/ci.yml` 末尾步骤，本地等价见 §19）：valid fixture → **0**；
  可读的非 NPY 文件（`README.md`）→ **1**（`InvalidMagic`）；不存在文件 → **2**；坏 `--limit x` → **2**。
  两个非零码必须保持**互不相同**。

## §12 NpyError 枚举契约

事实源：`src/cli/cli.mbt::render_error`（穷举匹配）与 `src/error/error.mbt`。CLI 渲染/测试断言的
13 个变体：`InvalidMagic`、`UnsupportedVersion`、`TruncatedHeader`、`InvalidHeaderLength`、
`InvalidHeaderSyntax`、`MissingHeaderField`、`InvalidDType`、`UnsupportedDType`、`ShapeOverflow`、
`DataLengthMismatch`、`UnsupportedObjectArray`、`InvalidByteOrder`、`InvalidChunkRange`（S4 第 13 变体）。
每条 negative case 断言**具体枚举分支**，不接受泛化失败。

---

## §14 覆盖率阈值（验收门禁）

事实源：`.github/workflows/ci.yml`「Coverage gate」步骤（`awk` 阻塞门禁）。

- **core parser（`format` + `lexer` + `parser`.mbt）≥ 90%**；
- **project overall（`Total:` 行）≥ 80%**；
- 阈值任一跌破 → `awk` 非零退出，该步骤阻塞。未出现在 `-f summary` 的文件视为 100% 覆盖，
  求和只计列出的 core 文件是保守下界。
- 当前实测（`coverage-summary.txt` / CI）：core parser **98.5%**、overall **91.7%**。

> 阈值是**验收边界事实**，本文件仅记录，不修改；改阈值须同步改 `ci.yml` 与本节。

---

## §15 兼容矩阵与入库 fixture 集契约

事实源：`generate_fixtures.py`（`p0_specs()`、`m2_matrix_specs()`、`committed_specs()`、`full_specs()`）。

**入库 fixture 集 = `committed_specs()` = `p0_specs()` + `m2_matrix_specs()`，共 31 个文件**
（`expected.json` 的 `count` 字段，README 记 31/31）：

- **P0 种子集（3）**：`<f4` shape `(2,3)` C-order，横跨 v1.0 / v2.0 / v3.0。三版覆盖两条 header-length
  路径（v1.0 = uint16@8，v2.0/v3.0 = uint32@8）。
- **M2 codec 定向矩阵（28）**：11 种 dtype（b1/i1/i2/i4/i8/u1/u2/u4/u8/f4/f8）× 字节序 × `(4,)` C-order
  v1.0（单字节 b1/i1/u1 无字节序变体，descr 前缀 `|`，共 19 个）+ 0-d `f8`、3-D `i2`、F-order `<f4 (2,3)`、
  F-order BE `>i4 (2,3)`（4 个）+ S1 complex：`<c8 (4,)`、`>c8 (4,)`、`<c16 (4,)`、`>c16 (4,)`、
  `<c8 (2,3)`（5 个）。
- `--full` 展开 §15 完整矩阵（dtype × shape × order × endian × version），**默认不入库**。

矩阵维度：dtype（bool/i1-8/u1-8/f4/f8，另 S1 complex c8/c16）· shape（`() (1,) (10,) (2,3) (2,3,4) (1,1,1,1)`）
· memory order（C / Fortran）· byte order（`<` / `>` / 单字节 `|`，Reader 另接受 `=`）· version（1.0/2.0/3.0）。

`expected.json` 记录每个 fixture 的 `version/descr/shape/fortran_order/header_len/data_offset/sha256/values`，
既是 Reader 测试的 ground-truth，也是 `roundtrip.py` 的 fixture 清单来源。生成器**确定性输出**（无时间戳），
同 NumPy 版本重跑字节一致；`--check` 仅逐一比对 `.npy` 的 `sha256`（不比对 `spec_ref` 等元数据字段）。

---

## §16 双向 Round-trip 语义

事实源：`.github/workflows/ci.yml`「NumPy -> MoonBit -> NumPy round-trip」步骤、
`interoperability/roundtrip.py`、`interoperability/verify_moonbit_output.py`。

- **NumPy → MoonBit**：`np.save`/`write_array` → `.npy` → moon-npy `read` → 校验 version/dtype/shape/order/元素值。
- **MoonBit → NumPy**：moon-npy `write` → `.npy` → `np.load`（`allow_pickle=False`，拒绝 object/pickle）
  → `np.array_equal()`。
- **字节级 round-trip（验收强化）**：`emit`（`moon run examples/roundtrip` 解码每个 fixture、用 Writer
  重编码、写字节）+ `verify`（`verify_moonbit_output.py` 让 NumPy 加载该文件，断言 `np.array_equal`
  **且**与 Oracle **逐字节一致**，含 §7.4 对齐）。由 `expected.json` 驱动，脚本自行打印 `N/N passed`。

---

## §19 CI 流水线门禁

事实源：`.github/workflows/ci.yml`（唯一定义处；本节镜像其门禁集合）。

- **版本 pin（可复现）**：`MOONBIT_VERSION = 0.10.11+6ff76a5f9`（对应 `moon version` 显示
  `0.1.20260827 (d0aaa07)`，见 `AGENTS.md` §0）、`PYTHON_VERSION = 3.14`、`NUMPY_VERSION = 2.3.4`。
- **门禁步骤（顺序）**：
  1. `moon update`（刷新 registry index，冷 runner 依赖解析所需，不触碰 pin 定的工具链）；
  2. **Gate 1/3 fmt**：`moon fmt` 后 `git diff --exit-code`；
  3. **Gate 2/3 check**：`moon check --target native`；
  4. **Gate 3/3 test**：`moon test --target native`；
  5. **coverage gate**：见 §14 阈值；
  6. **fixture drift**：`python interoperability/generate_fixtures.py --check`；
  7. **round-trip**：`python interoperability/roundtrip.py -v`（见 §16）；
  8. **CLI + 退出码**：`moon run cmd/main --target native -- {inspect,validate,dump}` 及非零码断言（见 §13）。
- **铁律**：README 展示的例子必须是 CI 中实际运行的例子（Demo 进 CI）。

**本地三步纪律（与 CI Gate 1–3 对应，见 `AGENTS.md` §8）**：fmt / check / test。本规范不改变该纪律，
仅调整验收边界的**引用指向**。

---

## §21 Oracle 原则

正确性以**当前 NumPy（pinned 2.3.4）的实际行为**为唯一 Oracle，而非机械照搬早期 NEP。
`expected.json` 一切字段从产物解析得来（见附录 A）。涉及文件格式的链路：
`AI suggestion → 官方 NumPy 规格 → NumPy 实现行为 → Fixture test → Accept`。

---

## §23 第一阶段硬目标（Definition of Done）

事实源：`.github/workflows/ci.yml` 头注「first-phase hard goal」、`README.md` M4 行（31/31）。

> **NumPy fixtures → MoonBit reads → MoonBit re-emits → NumPy verifies**
> （`np.array_equal` + 逐字节一致）——即 §16 双向 round-trip 对全部 31 个入库 fixture 通过。

达成 §23 当且仅当 §19 全部门禁步骤绿：三工具链版本 pin 一致、fmt 无 diff、check/test 通过、
覆盖率两阈值达标、fixture 无漂移、round-trip 全绿、CLI 退出码 0/1/2 且两非零码互异。
