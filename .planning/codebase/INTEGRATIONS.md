# External Integrations

**Analysis Date:** 2026-09-11

## APIs & External Services

> **总体结论：本仓库是 offline-by-design 的纯离线库。** `src/` 全部代码不含任何 HTTP 客户端、
> socket、REST / GraphQL 调用、DNS、消息队列或数据库访问（已全仓 grep 核查，唯一的 `curl` 出现在
> `.github/workflows/ci.yml` 安装 MoonBit 工具链那一步，不在库代码内）。外部接触面只有三类：
> **① `.npy` / `.npz` 磁盘二进制格式契约、② 一个第三方 MoonBit 模块（`amor2025/moonNum`）、
> ③ 构建期与 CI 期的工具链 / registry 网络访问**。运行时零网络、零凭据。

**Payment Processing:**
- 不适用（本仓库无任何支付相关代码、依赖或配置）

**Email/SMS:**
- 不适用（无 SMTP / SendGrid / 短信 SDK，无通知通道）

**External APIs:**
- **NumPy NPY 二进制格式（`.npy`）—— 这是本项目真正的「外部契约」，也是唯一的正确性 Oracle**
  - 集成方式：**纯磁盘字节流**，不是网络 API。本库直接读写 NumPy 写出的字节，不经过 Python 进程；反向亦然（`README.md` Ecosystem Position）
  - 规范所有权：`docs/spec/acceptance.md` 是仓库内**唯一权威 spec owner**（`AGENTS.md` 第 6–8 行明确：仓库各处 `§N` / `附录 A` 引用据此在克隆内解析；仓库外早期计划文档的同编号仅作历史来源）
  - **字节契约（`docs/spec/acceptance.md` 附录 A / §7.2）**：
    - Magic `\x93NUMPY` 占偏移 0–5（6 字节）；major / minor 占偏移 6 / 7
    - header 长度字段：**v1.0 = 偏移 8–9 的 uint16 LE**；**v2.0 / v3.0 = 偏移 8–11 的 uint32 LE**
    - header 正文起始：v1.0 = 偏移 **10**（`MAGIC_LEN+2`）；v2.0 / v3.0 = 偏移 **12**（`MAGIC_LEN+4`）；`MAGIC_LEN == 8`
    - `data_offset = header_start + header_len`
  - **Header 语法（§7.3）**：受限 Python literal，**不是 JSON**（`False` 非 `false`、结尾逗号 `(2, 3), }`、单元素元组 `(5,)`、0-d 标量 `()` 均非法 JSON）。实现在 `src/header/lexer.mbt` + `src/header/parser.mbt`，直接在 `Bytes` 上逐字节判定 ASCII，不先转 `String`
  - **对齐与填充（§7.4）**：NumPy 用空格（0x20）填充并以单个 `\n`（0x0a）收尾，使 `data_offset` 对齐到 **64 字节**（`ARRAY_ALIGN == 64`，源 `interoperability/generate_fixtures.py`）。**Writer 必须逐字节复现**；**Reader 禁止假设对齐**（只信任 `header_len`，容忍任意填充）
  - **版本支持**：`v1.0 / v2.0 / v3.0`（`src/format/format.mbt::version_of` 只按 major 决定 header-length 字段宽度，minor 仅信息性）。**版本选择真相（§8.4）**：`np.save(简单数组)` 恒只产出 1.0，v2.0 / v3.0 必须显式 `numpy.lib.format.write_array(f, arr, version=(2,0)/(3,0))`；v3.0 覆盖策略用**原始 dtype**（非 structured），只验证 uint32 长度字段 + UTF-8 header。Writer 侧 `src/writer/writer.mbt` 按 `NpyArray.version` **原样保留**输入版本（`version_major_minor` 映射 1.0 / 2.0 / 3.0），因此 round-trip 不降版
  - **字节序支持**：`<` little · `>` big · `|` N/A（单字节 / bool）· `=` native（Reader 另接受；`src/dtype/endian.mbt` 把 `=` 与 native 均按小端读，理由是「MoonBit 各后端均小端」——文档明确标注这是**对自身运行时的平台假设，而非对 NPY 规范的断言**）。Writer 只产出 `<` / `>` / `|`，从不产出 `=`
  - **dtype 覆盖（13 种）**：`bool`(b1) · `i1 i2 i4 i8` · `u1 u2 u4 u8` · `f4 f8` · `c8 c16`（`src/dtype/dtype.mbt::DType` 13 个变体 + `itemsize` + `descr_code`；complex64/128 自 v0.2.0 S1 起）。**主动拒绝** `|O`（object）→ `UnsupportedObjectArray`；识别但跳过 `C/S/a/U/V/M/m/g/G/e/l/L/p/P` kind → `UnsupportedDType`；畸形 descr → `InvalidDType`（`is_known_unsupported_kind`）
  - **不支持的格式（明确出范围）**：GGUF / SafeTensors / Parquet（`README.md` Limitations）
- **NumPy NPZ 容器格式（`.npz`，ZIP）—— 只读、仅 stored（未压缩）**
  - 实现在 `src/npz/npz.mbt`，字节布局事实由 `interoperability/probe_npz.py` 对 numpy 2.3.4 产物 pin 死
  - 成员 payload 是**完整 NPY 字节流**，原样透传给 `@reader.decode`——容器层不新增任何 NPY 语义
  - 已 pin 的两个反直觉字节事实：① local header 的 crc / size 字段对流式成员是 `0xFFFFFFFF` 占位，故成员长度取 central directory 的 `comp_size`，数据起点用 **local** header 自己的 `30 + name_len + extra_len`，**local size 字段永不被信任**；② zip64 extra field（id 0x0001）**出现在 local header 不等于 zip64 归档**——zip64 判据是 EOCD / central directory 的 `0xFFFF` / `0xFFFFFFFF` 哨兵（`comment_len` 除外）
  - **五类结构化拒绝**：压缩成员 `NpzCompressedMember`（method != 0）、路径穿越 / 绝对路径 `NpzUnsafeMemberName`、重复成员 `NpzDuplicateMember`、zip64 `NpzZip64Unsupported`、结构损坏 / 加密 `NpzBadStructure`
- **`amor2025/moonNum@0.1.0` —— 第三方 MoonBit 模块（生态适配边界）**
  - 集成点：`src/adapter/moonnum/adapter.mbt`（本仓唯一引用该模块的文件），`moon.pkg` 声明 `amor2025/moonNum/src/core` + `amor2025/moonNum/src/dtypes`
  - 方向：**单向、只读**（`NpyArray → NdArray`），只支持 float32 / float64 小端；写方向明确推迟到 v0.3（`docs/s6-api-card.md` §3.5）
  - 契约（card §3.4，全部从编译通过的 scratch 代码抄录）：`NdArray::from_buffer(Array[Byte], Dtype, Array[Int], Order) -> NdArray`、`NdArray::shape()` / `strides()`（**字节步长**）/ `get_f32()` / `get_f64()`；`@core.Order::{C, F}`；`@dtypes.Dtype::{Float32, Float64}`
  - **对接失败用适配器自己的 `AdapterError`**（`UnsupportedDType` / `BigEndianNotSupported` / `ShapeDimensionTooLarge`），**故意不给 `NpyError` 加变体**——`NpyError` 是 `pub(all) enum`，加变体会打破 `src/cli/cli.mbt::render_error` 的穷举 match（S4 已踩过一次）
  - **必须诚实标注的上游局限**：moonNum 的 `NdArray::is_little_endian()` 实现是**字面量 `true`**（`src/core/core.mbt:359`），其缓冲模型只有小端一种。故把 big-endian payload 原样交出会**静默读出倒置的错误数值**而非报错——`adapter.mbt` 把它做成硬性前置拒绝（`match arr.byte_order { Big => Err(BigEndianNotSupported(...)) … }`），并用真实 BE fixture `f8_4_c_be_v1.npy` 驱动测试
  - **生态位重叠（公开事实）**：moonNum 自带 npy 读写（`.mooncakes/amor2025/moonNum/src/io/save_load.mbt` 导出 `to_npy_bytes` / `from_npy_bytes` / `load` / `load_npz` / `load_bytes`），即它既是本适配器的**目标库**也是**同生态位实现**。`docs/s6-api-card.md` §3.7 明确约束措辞：不得把 moonNum 说成「不能读 npy 的数组库」，也不得宣称本适配器取代它
  - 备选池（仅记录，未纳入）：`mizchi/numbt@0.2.4`（no-go：需 `cblas.h` / `-framework Accelerate` 系统 BLAS，`moon test` 失败）、`Ankaluoer/moon-tensor`、`tonyfettes/narray`、`walkzzz/owl_mbt`、`tonyfettes/torch` 等（card §5）

## Data Storage

**Databases:**
- 无。本库不连接任何数据库，无 SQL / NoSQL / ORM / 迁移脚本；数据模型是纯内存的 `Bytes` → `NpyArray`，以及 `NpyArray` → `Bytes`

**File Storage:**
- **本地文件系统即全部存储面**，且访问被刻意收窄到 `cmd/main/` 与 `examples/` 的 `@fs` 调用（`README.md` Architecture：「`cmd/main` 薄壳：`@fs` 读字节 + `extern "c" exit` 设退出码（唯一 IO 边界）」）
  - 读出：`@fs.read_file_to_bytes(String) -> Bytes raise IOError`（`cmd/main/main.mbt`、`examples/roundtrip/main.mbt`、`examples/bench/main.mbt`、`tests/npy_test.mbt`）
  - 写入：`@fs.write_bytes_to_file(String, Bytes)`（`examples/roundtrip/main.mbt`、`examples/bench/main.mbt`）
  - 存在性：`@fs.path_exists(String) -> Bool`（不 raise；用于区分 `Operational` 退出码 2 与 `Invalid` 退出码 1）
  - `src/` 库层**完全不碰文件系统**——它只吃 `Bytes`，这是 `src/cli` 可纯逻辑黑盒测试的前提
- **Oracle fixture 集（跨实现契约的物理载体）**，`tests/fixtures/`：
  - **31 个 `.npy`**（`expected.json` 的 `count: 31`）+ **3 个 `.npz`**（`npz_expected.json` 的 `count: 3`）
  - `expected.json` 每项记录 `version / descr / shape / fortran_order / itemsize / element_count / header_len / header_start / data_offset / data_nbytes / file_nbytes / aligned_64 / sha256 / data_sha256 / values / flat_values`，**全部从 NumPy 真实产物的字节反推**，不手写、不臆测（§21 Oracle 原则）
  - `npz_expected.json` 记录每 archive / 成员的 `raw_name` / `method` / `comp_size` / `data_start` / `payload_sha256` / `descr` / `shape` / `fortran_order` / `values`
  - **`expected.json` 同时是 round-trip driver 的 fixture 清单唯一来源**（`roundtrip.py::load_fixture_names` 读 `data["fixtures"][*]["file"]`），不留手维护的平行列表
  - dtype 覆盖（`expected.json` 实测 descr 集合，23 个）：`|b1` `|i1` `|u1` `<f4` `<f8` `<i2` `<i4` `<i8` `<u2` `<u4` `<u8` `<c8` `<c16` `>f4` `>f8` `>i2` `>i4` `>i8` `>u2` `>u4` `>u8` `>c8` `>c16`
  - sha256 的稳定性由 `.gitattributes` 的 `*.npy binary` / `*.npz binary` 保护（禁止行尾转换 / 文本 diff / merge），形成「checkout 字节恒等」契约
- **运行期输出目录**（全部 gitignore，不入库）：`_build/m4_out/`（roundtrip.py emit 的 MoonBit 产物，默认 `--out-dir`）、`_build/bench_100x768_f32.npy`（bench 自合成输入，非 fixture 依赖）
- `interoperability/fixtures/` —— `.gitignore` 显式忽略的**历史遗留重复目录**（早期命名 `f32_2x3_v10/v20/v30`，与 `tests/fixtures/*.npy` 字节相同、无任何引用）；canonical fixture 只在 `tests/fixtures/`
- 无 S3 / GCS / Azure Blob / 对象存储，无 CDN 回源，无云盘

**Caching:**
- 应用层无缓存（无 Redis / Memcached）。工具链层有两处缓存，均非本仓代码：`~/.moon/registry/cache/`（registry zip）与 `~/.moon/registry/index/`（git 克隆的索引）

## Authentication & Identity

**Auth Provider:**
- 不适用。本仓库**无认证 / 授权 / 会话 / 用户概念**——它是纯函数式的字节格式转换库，没有「用户」这个实体
- 仓库内**不存任何凭据**：无 `.env` / `.env.example` / `*.pem` / `*.key`（已核查）。唯一涉及认证的环节是 `moon publish` 发布到 Mooncakes，其 token 由 MoonBit 工具链在本仓库**之外**（用户级配置）管理，不落盘到仓库

**OAuth Integrations:**
- 不适用（无 OAuth / OIDC / SSO / 第三方登录）

## Monitoring & Observability

**Error Tracking:**
- 无外部服务（无 Sentry / Bugsnag / Rollbar）
- 错误处理**全部在进程内**：`src/error/error.mbt` 的 `pub(all) enum NpyError` 共 **19 个构造子**（13 个 NPY 层 + 6 个 NPZ 层：`NpzCompressedMember` / `NpzUnsafeMemberName` / `NpzDuplicateMember` / `NpzZip64Unsupported` / `NpzBadStructure` / `NpzMemberNotFound`），经内建 `Result` 通道返回；`src/cli/cli.mbt::render_error` 做穷举匹配渲染
- 关键正确性保证不在外部可观测性上，而在**测试与门禁**上：156 个单元测试、7000 次确定性 fuzz（totality 不变式：任意 `Bytes` 恒返 `Ok` 或结构化 `Err`，永不 trap / OOB / 失控分配）、31 个 fixture 的跨语言逐字节 round-trip

**Analytics:**
- 无（无 Mixpanel / GA / PostHog / 遥测上报；无 phone-home）

**Logs:**
- 仅 stdout / stderr，无日志聚合服务
  - CLI 输出到 stdout：`inspect` 的元数据表（标签列宽 14、26 字符 `U+2500` 分隔线）、`validate` 的 `✓/✗` 行、`dump` 的逐元素行 + 末尾 `(showing K of N elements)`；失败时统一的 `✗ <path>` + 结构化错误块
  - `moon` 构建进度写 stderr（`AGENTS.md` §8 的 PowerShell 坑：会被渲染成红色 `NativeCommandError`，判定要看 `$LASTEXITCODE`）
  - `interoperability/roundtrip.py` 把子进程 stdout+stderr 合并捕获为 UTF-8，打印逐 fixture 的 `[PASS]/[FAIL]` 与最终 `N/N passed`

## CI/CD & Deployment

**Hosting:**
- **Mooncakes registry（mooncakes.io）—— 库的唯一分发渠道**
  - 引入方式：`moon add ShunjunGu/moon-npy`（`README.md` Installation；文档页 `mooncakes.io/docs/ShunjunGu/moon-npy`）
  - v0.3.0 是**首个发布版本**（`CHANGELOG.md`）；发布经官方打包校验（干净副本复跑 `moon check` 通过）+ 独立 fresh 模块 `moon add` 冒烟验证
  - 发布产物落盘在 `_build/publish/ShunjunGu-moon-npy-0.3.0.zip`（含 `verify/`）
  - 源码仓库：`https://github.com/ShunjunGu/moon-npy`（`moon.mod` 的 `repository` 字段；本地 git 分支 `main`，跟踪 `origin/main`）
- 无 Web 托管（Vercel / Netlify / ECS / Lambda 均不适用）——交付物是库与 CLI 二进制，不是常驻服务

**CI Pipeline:**
- **GitHub Actions** —— `.github/workflows/ci.yml`，仓库内唯一 workflow
  - 触发：`push` / `pull_request` 到 `main` + `workflow_dispatch`；`permissions: contents: read`；并发组 `ci-${{ github.ref }}` 且 `cancel-in-progress: true`
  - Runner：`ubuntu-latest`
  - **版本 pin（env，§19 可复现性）**：`MOONBIT_VERSION = "0.10.11+6ff76a5f9"`、`PYTHON_VERSION = "3.14"`、`NUMPY_VERSION = "2.3.4"`
  - 外部 action 与网络依赖：`actions/checkout@v4`、`actions/setup-python@v5`、`curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash -s "<ver>"`（MoonBit 安装 CDN，并按 `moonc -v` 的 semver 而非 `moon version` 日期串解析路径）、`moon update`（git 克隆 mooncakes.io 的 registry index 到 `$HOME/.moon/registry/index`——冷 runner 的空索引否则无法解析 `moonbitlang/x@0.5.1` 与 `amor2025/moonNum@0.1.0`）、`python -m pip install "numpy==2.3.4"`
  - **无 secrets**：workflow 不含任何 `secrets.*` 引用，不需要仓库 secret 配置
  - 门禁步骤（顺序，§19）：① `moon fmt` + `git diff --exit-code`（Gate 1/3 格式）→ ② `moon check --target native`（Gate 2/3 类型）→ ③ `moon test --target native`（Gate 3/3 单元）→ ④ **coverage gate**（`--enable-coverage` → `coverage analyze` → `report -f summary` → `awk` **阻塞式**阈值判定）→ ⑤ fixture 漂移（`generate_fixtures.py --check`）→ ⑥ 跨语言 round-trip（`roundtrip.py -v`）→ ⑦ CLI 冒烟 + 退出码断言（`inspect` / `validate` / `dump --limit`，并断言 valid→0、非 NPY 文件→1、缺文件→2、坏 `--limit`→2，两个非零码必须互异）
  - **覆盖率阈值（§14，硬门禁）**：core parser（`format` + `lexer` + `parser`.mbt）**≥ 90%**；project overall（`Total:` 行）**≥ 80%**。任一跌破 → `awk` 非零退出 → 该步骤阻塞。实测：core parser **98.5%**、overall **91.7%**（`coverage-summary.txt` 原始记录为 `Total: 822/890`；`README.md` / `CHANGELOG.md` 记 C1 后 overall **92.4%**）
  - **代码覆盖率服务**：CI **未**接入 Codecov / Coveralls（`AGENTS.md` §7 仅提到 `-f coveralls --send-to codecov` 是**可选**用法，`.github/workflows/ci.yml` 实际只用 `-f summary`）
  - **fixture 漂移门禁（§15 / §21）**：`generate_fixtures.py --check` 逐一比对 31 个 `.npy` 的 sha256（不比对 `spec_ref` 等元数据字段），确保入库 fixture 与 pinned NumPy 的 Oracle 一致
  - 沙箱约束：因 `@fs` 需要真实文件系统，全部跨语言步骤都在 native target 上跑

## Environment Configuration

**Development:**
- **必需 env var：无。** 库与 CLI 运行时零 env var；无 `.env` 文件、无 secrets、无 mock 服务
- 可选 env var：`MOON_BIN`（`interoperability/roundtrip.py::resolve_moon` 的解析链 `--moon` > `$MOON_BIN` > `moon` on PATH）
- PATH 约定：`moon.exe` 在 `C:\Users\<user>\.moon\bin\`，**可能不在 PATH**；PowerShell 首行 `$env:Path = "$env:USERPROFILE\.moon\bin;$env:Path"`（`AGENTS.md` §0 / §8，`README.md` Installation）
- 本地等价的 CI 三步：`moon fmt` → `moon check --target native` → `moon test --target native`
- 跨语言验证需要本地 Python 3.14 + NumPy 2.3.4；无 mock / stub 服务（Oracle 本身就是真 NumPy）

**Staging:**
- 不适用（无 staging 环境——本项目是库，不存在分环境部署）

**Production:**
- 不适用（无生产环境 secrets / 无 failover / 无多区域）。交付面是 Mooncakes registry 上的不可变版本 + GitHub 上的源码；消费方在其自己的工程里 `moon add` 引入，无本仓可控的运行时配置

## Webhooks & Callbacks

**Incoming:**
- 无。本库不监听端口、不注册路由、不接收任何回调（无 HTTP server 代码，`src/` 无 `extern "c"` 之外的平台绑定）

**Outgoing:**
- 无。本库不外发 webhook、不上报遥测、不调用外部 API。唯一的出站网络行为全在 CI 与构建期：`curl` 拉 MoonBit 安装脚本、`moon update` 克隆 registry index、`pip install numpy`

---

*Integration audit: 2026-09-11*
*Update when adding/removing external services*

---

**附：本次审计发现的契约溯源瑕疵（供后续修正，非功能缺陷）**
- `tests/fixtures/npz_expected.json` 的 `oracle.spec_ref` 指向 `docs/plans/2026-09-10-moon-npy-v0.3.0-npz.md`，但 `docs/` 下实际只有 `docs/s6-api-card.md` 与 `docs/spec/acceptance.md`——**该文件在仓库内不存在**，`§4 Task 4` 引用无法在克隆内解析。相较之下 `expected.json` 的 `spec_ref` 指向 `docs/spec/acceptance.md §15/§16, 附录 A`，是可解析的
- `.gitignore` 第 5 行声明「`moon.lock` 需入库以保证依赖可复现（§19）」，但仓库根无 `moon.lock`（`.mooncakes/.moon-lock` 为 0 字节）。当前依赖可复现性实际由 `moon.mod` 的精确版本 pin 承担
