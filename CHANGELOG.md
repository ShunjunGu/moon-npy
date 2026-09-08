# Changelog

All notable changes to this project are documented in this file.

The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

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
