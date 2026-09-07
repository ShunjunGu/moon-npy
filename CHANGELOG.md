# Changelog

All notable changes to this project are documented in this file.

The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `AGENTS.md` — M0 验证 gate（2026-09-07）实测固化的 MoonBit 工具链事实与项目约定
  （MoonBit `0.1.20260827`；错误范式 / Bytes / 位宽 / Float reinterpret / native IO /
  CLI 参数 / 测试与覆盖率命令）。
- NumPy 兼容性 Oracle（`interoperability/`）：
  - `generate_fixtures.py` — 数据驱动 fixture 生成器，从 numpy 真实产物字节反推
    `expected.json`；确定性输出（无时间戳）；`--check` 漂移校验、`--full` §15 完整矩阵。
  - `verify_moonbit_output.py` — MoonBit Writer 产物校验（`np.load` / `array_equal` /
    逐字节），M3/M4 阶段启用。
  - `README.md` — Oracle 使用文档与 CI 集成说明。
- P0 fixtures（`tests/fixtures/`）：float32 `(2,3)` C-order 的 NPY v1.0 / v2.0 / v3.0
  三版 + `expected.json`；已用独立字节 dump 核验对齐计划附录 A（header_len 118/116/116、
  data_offset 128、file 152B、`\x93NUMPY` magic、空格填充 + `\n` 收尾）。
- 仓库骨架：`README.md`、`LICENSE`（Apache-2.0）、`.gitignore`、`CHANGELOG.md`。
