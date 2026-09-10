# Changelog

All notable changes to this project are documented in this file.

The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [v0.3.0] - 2026-09-10

v0.3.0 新增 C1：**NPZ 容器读取**（C1）——只读、未压缩的 `np.savez` ZIP 容器，成员 payload 原样
透传给既有 NPY decode 路径。单元测试 128 → **156**，fixture **31** 个 .npy + **3** 个 .npz
Oracle archive；覆盖率 `src/npz/` **97.1%**（102/105）、overall **92.4%**（822/890，新增 npz
包后分母扩大仍高于 v0.2.0 的 91.7%）、core parser **98.5%**（不变）。工具链仍 pin
MoonBit `0.1.20260827` / NumPy `2.3.4` / Python `3.14`。

### Added

- **NPZ 容器读取（C1）** — `src/npz/` 新包：`decode_npz(Bytes) → Result[NpzArchive, NpyError]`，
  `NpzArchive::get(name)` / `names()`（成员名自动剥 `.npy` 后缀，成员序 = central directory 序）。
  EOCD + central directory 解析后逐成员校验，五类拒绝全部为结构化错误：压缩成员
  （`NpzCompressedMember`）、路径穿越 / 绝对路径（`NpzUnsafeMemberName`）、重复成员
  （`NpzDuplicateMember`，封死 zip-shadowing）、zip64（`NpzZip64Unsupported`）、结构损坏或加密
  （`NpzBadStructure`）。`NpyError` 13 → **19** 变体，`render_error` 穷举分支同步；本库无 inflate
  实现，解压炸弹攻击面 **by construction 不存在**（README Security 容器层小节）。
- **NPZ Oracle fixtures + drift 门禁（C1）** — `interoperability/generate_fixtures.py` 扩展：
  `tests/fixtures/` 新增 3 个 NumPy `np.savez` 真实产物（3 成员数组 / 自定义 key / deflate 压缩）
  与 [`tests/fixtures/npz_expected.json`](tests/fixtures/npz_expected.json)（每 archive / 成员的
  descr / shape / 值 / sha256 / comp method）；`--check` 门禁同步覆盖 NPZ（CI 同实跑）。
  `.gitattributes` 补 `*.npz binary`。单元测试 154 → 156（Oracle fixture 断言 ×3 与既有调整）。
- **NPZ 性质测试（C1）** — `tests/npz_test.mbt`：`savez ≡ save` 等值性质（同一数组的单文件 NPY
  decode 与容器内 `get("arr_0")` 的 header / element_count / payload 字节全等）+ 31-fixture
  透传性质（每个 Oracle fixture 包装成伪单成员 npz 后 `decode_npz` 与直读结果字节级一致）。

### Changed

- 文档：`README.md` / `README_CN.md` Status 表新增 C1 行、Features 增 NPZ bullet、Compatibility
  不支持清单将 NPZ 移出、Library API / error enum / Architecture / Layout 同步、Security 新增
  「NPZ 容器层」小节（by construction, not by filtering）、Development / CI 数字同步。

## [v0.2.0] - 2026-09-10

v0.2.0 Stretch 四项全部落地：complex64 / complex128 读取（S1）、CLI `dump [--limit N]`
（S5）、storage-order 分块读取（S4）、moonNum 读方向适配（S6）；加上新增的创新包 A1/B1/A2。
单元测试 85 → **128**，fixture 26 → **31**，覆盖率 core parser **98.5%**、overall **91.7%**；
本仓首个（也是目前唯一一个）第三方依赖 `amor2025/moonNum@0.1.0`。工具链仍 pin
MoonBit `0.1.20260827` / NumPy `2.3.4` / Python `3.14`。

### Added

- **安全边界性质测试（创新包 A1）** — `tests/security_test.mbt`（3 用例）把「拒绝 object / void
  数组」从功能缺失升级为**可回归验证的架构性质**：object descr 的三种端序写法（`|O` / `<O` / `>O`）
  均在解释任何载荷字节**之前**、且与 `shape`（`()` / `(1,)` / `(2, 3)`）无关地返回
  `UnsupportedObjectArray`；void（`|V8`）经 known-unsupported-kind 表返回 `UnsupportedDType`。
  不新增产品代码，仅将 `dtype.mbt` 已有的前置拒绝固化为回归资产（`edge_test.mbt` 的标量用例
  扩展为全矩阵）。单元测试 85 → **88**。
- **语言内 round-trip 字节恒等性质（创新包 B1）** — `tests/property_test.mbt`：对全部字节级
  Oracle fixture（当前 31 个，名单以 `oracle_fixture_names()` 为准）断言 `decode → encode`
  **逐字节恒等**，且重解码后 dtype / shape / `element_count` 不变。字节级兼容保证从此
  **不依赖 Python 环境**也在 `moon test` 中被强制
  （与 `interoperability/roundtrip.py` 的 NumPy 侧全量校验互补，非替代）。fixture 名单收敛到
  `tests/npy_test.mbt` 的共享 `oracle_fixture_names()`（单一事实源，`fuzz_test.mbt` 改为引用）。
  单元测试 88 → **89**。
- **README Security 章节改写（创新包 A2）** — 原已有的 Security 节只笼统提到 `|O` 前置拒绝，
  本轮改写为「Security by construction」叙事，与 A1 测试逐条对应（三种端序 + void + 精确错误
  变体 + 指向 `tests/security_test.mbt`），并诚实限定边界（不宣称通用沙箱，只声明此类攻击面在
  本库不存在）；兼容性矩阵中「见 Security」的引用仍成立。覆盖率与四门门禁不变（
  core parser 98.5%、overall 91.3%，同 v0.1.0）。
- **complex64 / complex128 读取（v0.2.0 Stretch S1）** — `src/dtype/`：`DType` 新增
  `Complex64` / `Complex128` 变体（descr `<c8` / `>c8` / `<c16` / `>c16`，`itemsize` 8 / 16，
  `name` 为 NumPy 的 `complex64` / `complex128`），元素类型是**单一结构**
  `pub(all) struct Complex { re : Double; im : Double }`（两种宽度共用：MoonBit `Double` 为
  64 位，对 complex128 分量精确、对 complex64 的 f32 分量无损加宽），codec `read_c64` /
  `read_c16` 按 2 × f32 / 2 × f64 的 re,im 交错读取。`kind_size_to_dtype` 新增 `c` 分支，
  `is_known_unsupported_kind` 从此只列入未解码的 kind（大写 `C` = complex256 仍在列）。
  `src/reader/`：`to_c64` / `to_c16` 直接复用既有泛型 `flat(arr, want, read)`，dtype 校验 /
  payload 长度 / storage-order（Q2）与其余 accessor 同一条代码路径，无新增边界逻辑；
  accessor 11 → **13**。写入侧**零改动**：`writer.encode` 按 `descr_code`（`c8` / `c16`）重建
  header、payload 原样透传，跨语言 round-trip 对新 fixture 直接全绿。
- **complex Oracle fixtures（S1 / X2）** — `tests/fixtures/` 新增 5 个 NumPy 2.3.4 真实产物：
  `c8` / `c16` 各一对 LE + BE 的 1-D，加一个 2-D `(2,3)` `c8`（shape 元数据与扁平长度同时
  校验），fixture **26 → 31**。`generate_fixtures.py` 的 `make_values` 对 complex 取
  `im = 2 * re`（实部虚部故意不等：任何 re/im 交换读取在 Oracle 对比下失败，而非静默通过）；
  `expected.json` 用 `jsonable()` 把 complex 表示为 `[re, im]` 二元组（`json.dumps` 无法直接
  序列化 Python `complex`）。fixture 名单收敛点 `oracle_fixture_names()` 同步到 31。单元测试
  89 → **99**；覆盖率 core parser **98.5%**（129/131，不变）、overall **91.3% → 91.6%**
  （557/610 → 579/632，新增代码路径均被覆盖）；`README.md` / `README_CN.md` 的兼容性矩阵、
  库 API、fixture 计数同步（不支持清单里 complex 移出、改列 complex256）。
- **CLI `dump [--limit N]`（v0.2.0 Stretch S5）** — `src/cli/`：`Subcommand` 新增 `Dump(Int)`，
  `parse_args` 接受 `dump <file.npy>`（默认上限 **10**）与 `--limit N`（`0` 合法；缺值、非数字、
  超出 `Int` 可表示范围均归为**用法错误**而非运行时失败——故库代码不 trap（§18 totality），
  且 `--limit` 的解析走 `@string.parse_int`（`raise` 语义）而非 `to_int`（本 pin 的 `String`
  无此方法）。`run_dump` 先 `decode`、再把每个元素过它自己类型的 `to_string` 渲染，complex 走
  S1 的 `to_c64` / `to_c16` 并以 `(re, im)` 打印，覆盖全部 **13** 个元素级 dtype；
  `render_dump` 截断到 `--limit` 并固定输出末行 `(showing K of N elements)`，失败路径与
  `inspect` / `validate` 共用同一个 `✗ <file>` + 结构化错误块（退出码仍 0/1/2，坏 `--limit` → 2）。
  `cmd/main/` 的 match 加 `Dump` 分支，usage 字符串改为 `<inspect|validate|dump>`。
  **渲染格式以实测为准**：`Float` / `Double` 的 `to_string` 省略尾随 `.0`，所以 CLI 真机输出是
  `[0] 0` 与 `[1] (1, 2)`，而不是 `1.0` / `(1.0, 2.0)`——测试 pin、README 示例与 CI grep 一律跟随
  实测，未为实现去凑一个未验证过的格式。
  单元测试 99 → **111**（4 个 `parse_args` + 7 个 `run_dump` + 一个表驱动的
  `dump_covers_all_13_dtypes`：13 行表格逐一对齐 NumPy Oracle `expected.json` 的首 / 末值，作为
  「13 个 dtype 全覆盖」这一宣称的证据，§19）；覆盖率 core parser **98.5%**（129/131，不变）、
  overall **91.6% → 91.2%**（579/632 → 675/740：分母新增 108 行、覆盖 96 行，故比例微降，仍远高于
  80% 阈值）。`.github/workflows/ci.yml` 的 CLI 冒烟步骤扩为 `dump --limit 2` grep 截断行、`c8`
  grep `(1, 2)`（`-F` 字面匹配）、坏 `--limit` 捕获退出码 `== 2`；`README.md` /
  `README_CN.md` 的 CLI 段粘贴上述真实输出并注明 `dump` 先全量解码再截断（`--limit` 省输出行数、
  不省内存）。
- **storage-order 分块读取（v0.2.0 Stretch S4）** — `src/error/`：`NpyError` 新增第 **13** 个变体
  `InvalidChunkRange(Int, Int)`，载荷是原始 `(start, len)`（含负值）；`pub(all) enum` 加变体会立即
  打破穷尽 match，故与 `src/cli/render_error` 的新分支同提交。渲染沿用已有千分位风格但**不带
  ` bytes` 后缀**（这两个数是元素下标）；`group_digits` 顺势修正——旧实现把前导 `-` 当成一位数字，
  位数恰为 3 的倍数时逗号错位（`-100` → `-,100`、`-100000` → `-,100,000`），新实现把符号移到分隔符
  之外，**非负输入逐字节不变**（用旧 / 新算法 1:1 复现核对，`DataLengthMismatch` 的既有输出零漂移）。
  `src/reader/`：新增私有 `fn[T] flat_range(arr, want, read, start, len)`，既有 `flat` 改为以
  `(0, element_count)` 委托它——全量 accessor 与窗口 accessor 共用同一条 dtype 校验 / 解码路径；
  窗口边界在 **Int64** 上对 `element_count` 校验（Int 下 `start + len` 可溢出为假通过），失败返回
  `InvalidChunkRange` 而非 panic（§18 totality）。公开面只加 `to_f32_chunk` / `to_f64_chunk`
  两个（§29 Demo 的 float32 embeddings 主用例），其它 dtype 的窗口访问器按需再加（YAGNI）。
  语义诚实：窗口省的是**输出数组**，不是 payload——`decode` 已把整段数据读进内存，本 API **不是
  lazy I/O**；据此改写 `README.md` / `README_CN.md` 的 Limitations（原「无 streaming / 分块读」→
  「无跨文件 I/O 的 streaming」）、Quick Start 的「惰性」措词、以及 S5 留下的「`--limit` 不省内存」
  前向指针。新增一个以 `header.shape` 算 stride 的行切片用例，README 展示的
  `to_f32_chunk(k * 768, 768)` 行读法因此有真实测试背书（§19 铁律）。
  单元测试 **111 → 118**（一个 `render_error` 用例 + 六个窗口用例：中间窗口、`(0, count)` 与全量
  accessor 逐元素相等（f32 / f64 各一条，钉住委托重构不漂移）、空窗口含 `start == element_count`
  末游标、6 个被拒窗口逐条回捕、dtype 先于窗口校验、行切片）；覆盖率 core parser **98.5%**
  （129/131，不变）、overall **91.2% → 91.4%**（675/740 → 688/753：`reader.mbt` 新增行全被覆盖，
  该文件保持 100%）。
- **moonNum 读方向适配（v0.2.0 Stretch S6）** — `src/adapter/moonnum/`：`to_moonnum_f32` /
  `to_moonnum_f64` 把 `reader.decode` 得到的 `NpyArray` 交给 `amor2025/moonNum@0.1.0` 的 `NdArray`。
  零元素解码：载荷字节 + `shape` + `fortran_order` 直接喂 `NdArray::from_buffer`（moonNum 内部自己
  算字节步长），`Bytes::to_array()` 是整条管线上唯一一次元素级拷贝。三个前置条件**任一不满足即拒**：
  descr 不是本入口对应的 f4 / f8、big-endian（moonNum 的缓冲模型只有小端，其 `is_little_endian()`
  是字面量 `true`，递过去只会得到「看起来合理」的错值）、shape 维度装不进 32 位 `Int`（拒绝，
  不截断）。失败类型是适配器自己的 `pub(all) enum AdapterError`（3 变体 + `message()`）而**不是**
  `NpyError` 的新变体：那是 `pub(all) enum`，加变体会打破 `src/cli/render_error` 的穷举 match
  （S4 踩过），且这些均不是「`.npy` 文件本身有问题」——字节是合法 NPY，只是适配器无法在 moonNum
  的模型里表达它。`moon.mod` 从此新增**本仓第一个也是唯一一个第三方依赖**
  （`import { "moonbitlang/x@0.5.1", "amor2025/moonNum@0.1.0" }`）。选型 go/no-go 与全部 API 事实
  见 `docs/s6-api-card.md`（Task 12 交付物）：**moonNum GO**（`check` / `test` 均退出码 0），
  **numbt NO-GO**——`mizchi/numbt@0.2.4` 的 `check` 能过但 `test` 卡在 C native-stub 编译
  （`cblas.h` 缺失），三条独立拒因（需系统 BLAS + Apple 专属 `-framework Accelerate`、数据模型
  `Mat` 只有 f32/2-D、校验一律 `panic()` 与本仓 totality 纪律冲突），详见 card §4。
  单元测试 **118 → 128**（10 个适配器用例：C / F order、0-d 标量、与 `to_f32` 扁平序一致、
  三条拒因逐条、dtype 门先于字节序门、`message()` 三臂；F order 的 `strides` 与 `ravel` 序、
  0-d 的空 `shape` / `strides` 均先用 **NumPy 2.3.4** 本地实测核对后写入，不凭记忆）；覆盖率
  core parser **98.5%**（129/131，不变）、overall **91.4% → 91.7%**（688/753 → 714/779：
  `adapter.mbt` 26/26 全覆盖，从 `coverage report -f summary` 的未满行清单消失）。
  `.github/workflows/ci.yml` 的步骤**零改动**——现有 `moon update` 在 `moon check` 之前，已经能
  解析新增的第三方依赖，本地模拟 CI 全链路（四门 + `moon update` + fixtures `--check` +
  `roundtrip.py` 31/31）已复现绿；只刷了那步旁边的一句注释（原来只列了 `moonbitlang/x@0.5.1`
  一个依赖，现已是两个）。`README.md` / `README_CN.md` 的 Installation 段同步——原「唯一依赖」
  的说法从 S6 起已不成立，改为两个依赖并注明核心层不依赖任何第三方库。

### Changed

- `src/reader/reader.mbt` 内部重构——泛型 `flat(arr, want, read)` 不再是全量解码的唯一实现，而是
  委托给新的 `flat_range`。公开签名零变更，行为等价性由既有的全部 accessor 测试与新增的
  `(0, count)` 窗口相等断言共同钉住。

- `.github/workflows/ci.yml` — round-trip 步骤名去掉写死的 fixture 计数（原 `(26 fixtures)`）：
  `tests/fixtures/expected.json` 是唯一名单，`roundtrip.py` 自身打印 `N/N passed`，在步骤名里
  重复一个数字只会每次加 fixture 时静默过期（本次 26 → 31 即为一例）。

## [v0.1.0] - 2026-09-08

### Added

- **文档定版（验收准备）** — `README.md` 全量补齐计划 §25 Documentation 十小节（安装 / 快速
  开始 / 兼容性矩阵 / CLI 用法 / 库 API / 限制 / 生态位 / 安全 / 开发 / 许可证）+ §28 生态位图
  + 架构数据流图；新增 `README_CN.md` 全中文版（与英文版双向链接、技术事实与 API 签名逐条一致）。
- **边缘用例 / Fuzz / 覆盖率门禁（M5）** — 第一阶段特性冻结前的鲁棒性收口（计划 §14 / §18），
  单元测试 65 → **85** 全绿：
  - `tests/edge_test.mbt`（17 用例）— **在测试代码内合成**负面 / 边缘用例（不新增 fixture 文件）：
    0-d / N-D、Fortran-order、big-endian、`=` native、空数组、截断 / 损坏 header、shape 溢出、
    payload 长度不符等，逐条钉住具体 `NpyError` 分支。
  - `tests/fuzz_test.mbt`（3 property 测试）— 确定性 splitmix PRNG（`moonbitlang/core/quickcheck/splitmix`，
    固定种子、可精确复现、无 flaky）驱动 §18 totality 不变式：任意 `Bytes` → `decode` / `validate`
    恒返 `Ok` 或结构化 `Err(NpyError)`，绝不 crash / hang / 越界 / 失控分配；三输入分布（纯随机字节 /
    合法 v1 前缀 + 随机 body / 26 fixture 变异），共 **7000 次迭代**全绿，并断言 decode ≡ validate、
    Ok 路径 accessor 恰返 `element_count` 个元素。`tests/moon.pkg` 增导入 splitmix。
  - `.github/workflows/ci.yml` — coverage 步骤由「非阻塞摘要」升级为**强制阈值门禁**：awk 解析
    `moon coverage report -f summary`，core parser（format+lexer+parser）≥ 90% 且项目 overall ≥ 80%，
    任一未达即 CI 失败（去掉 `continue-on-error`）。本地实测 core parser **98.5%**（129/131，format.mbt
    100% 未列入 summary 故为保守下界）、overall **91.3%**（557/610），双阈值达标。
- **CLI（`inspect` / `validate`）** — `src/cli/`（纯逻辑库：`parse_args` + 输出渲染，无 IO，
  可单测）+ `cmd/main/`（薄可执行壳：`@fs` 读字节 + `extern "c"` `exit` 设进程退出码）。
  输出严格对齐 §13（14 列标签表、千分位字节数、`✓`/`✗` 判定）；退出码纪律 valid → 0 /
  非法文件（`NpyError`）→ 1 / 打不开或用法错误 → 2，`$LASTEXITCODE` 实测三类互不混淆。
  `moon run cmd/main --target native -- <inspect|validate> <file.npy>`；CI 增 CLI 冒烟步骤。
- **字节级双向 round-trip（M4）** — 打通 `NumPy → MoonBit → NumPy` 完整链路，第一阶段
  硬目标达成（计划 §23）：
  - `examples/roundtrip/` — 可执行 emit harness：读 `.npy` → `decode` → `encode` → 落盘
    （`moon run examples/roundtrip --target native -- <in> <out>`）。
  - `interoperability/roundtrip.py` — `expected.json` 驱动的跨语言 driver：逐 fixture
    emit + verify，聚合 `[PASS]/[FAIL]`，任一失败退出 1。当前 **26/26 字节级通过**。
  - `.github/workflows/ci.yml` — §19 CI：pin MoonBit `0.1.20260827+d0aaa07` / NumPy
    `2.3.4` / Python `3.14`；fmt → check → test → coverage → fixture `--check` →
    round-trip 全 26 fixture。
- **NPY Writer（M3 `afb9da8`）** — `src/writer/`：`encode(NpyArray) -> Result[Bytes, NpyError]`，
  re-serialize Reader 产物，输出与 `np.save` **逐字节一致**（64 字节对齐、空格填充、
  `\n` 收尾）；已验证至 300 KB payload。
- **dtype codec + NPY Reader（M2 `a7d9aa3`）** — `src/dtype/`、`src/reader/`：
  `decode(Bytes) -> Result[NpyArray, NpyError]`，覆盖全 11 种 primitive numeric dtype
  （bool / i1–i8 / u1–u8 / f4 / f8）、`<` / `>` / `|` 字节序、N-D shape（0-d scalar、3-D）、
  C / Fortran order。
- **NPY header 解析（M1 `8d8f46f`）** — `src/header/`：magic / version / header-len
  （v1 `uint16`、v2/v3 `uint32`）/ Python-literal dict（`descr` / `fortran_order` /
  `shape`）的 lexer + parser。
- **格式与错误基础层** — `src/format/`（`\x93NUMPY` magic、版本常量）、`src/error/`
  （`enum NpyError` + `Result`，12 分支）。
- `AGENTS.md` — M0 验证 gate（2026-09-07）实测固化的 MoonBit 工具链事实与项目约定
  （MoonBit `0.1.20260827`；错误范式 / Bytes / 位宽 / Float reinterpret / native IO /
  CLI 参数 / 测试与覆盖率命令）。
- NumPy 兼容性 Oracle（`interoperability/`）：
  - `generate_fixtures.py` — 数据驱动 fixture 生成器，从 numpy 真实产物字节反推
    `expected.json`；确定性输出（无时间戳）；`--check` 漂移校验、`--full` §15 完整矩阵。
  - `verify_moonbit_output.py` — MoonBit Writer 产物校验（`np.load` / `array_equal` /
    逐字节）；M4 起由 `roundtrip.py` 驱动，26 fixture 全绿。
  - `README.md` — Oracle 使用文档与 CI 集成说明。
- fixtures（`tests/fixtures/`）：**26 个** `.npy` + `expected.json`；P0 种子集 float32
  `(2,3)` C-order v1.0 / v2.0 / v3.0（覆盖 uint16 与 uint32 两条 header-length 解析路径），
  加 M2 codec 定向矩阵（全 dtype × 字节序 × 小 shape × v1.0、0-d scalar、3-D、
  Fortran-order）；均用独立字节 dump 核验对齐计划附录 A（`\x93NUMPY` magic、空格填充 +
  `\n` 收尾、64 字节对齐）。
- 仓库骨架：`README.md`、`LICENSE`（Apache-2.0）、`.gitignore`、`CHANGELOG.md`。
