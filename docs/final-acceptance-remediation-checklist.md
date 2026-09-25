# MoonBit 九月赛交付修复清单（核对版）

核对日期：2026-09-25

仓库：`ShunjunGu/moon-npy`

基线：`main`，`d9fdcd6efa5ba3927a041526e12bb52cdb064555`（本地与 GitHub `main` 一致）

本清单逐项复核了对话「确认MoonBit截止时间延期」中的审计结论。下文的证据、
170 个测试和 80.5% 覆盖率均为修复前基线；本轮整改结果记录在下一节。

## 整改执行记录（2026-09-25）

| 编号 | 处理结果 |
|---|---|
| R1 | ✅ 英中 README 均明确：v0.3.0 已发布未压缩 NPZ 读取；`main` 已实现未压缩写入，但尚未发布；压缩 / deflate、zip64、加密仍不支持。 |
| R2 | ✅ M5 的 159 / 81.7% 标为 N7 前历史快照；当前为 `tests/` 173 + whitebox 3 = 全仓 176，overall 80.7%。 |
| R3 | ✅ `docs/spec/acceptance.md` §19 已镜像 CI 的 NPZ 写入 Oracle，含 CRC-32、ZIP_STORED、`np.load` 和 UTF-8 key。 |
| R4 | ⏳ v0.4.0 经公开 API 差异核对可作向后兼容的 minor 候选，`moon.mod` 与 changelog 已按**未发布候选**准备；远端 CI、GitHub Release 和 Mooncakes 发布仍待完成。已在沙箱外用 `gh auth status` 与 `gh api user` 确认 GitHub 登录有效；沙箱内的认证失败是执行环境限制。 |
| R5 | ✅ central-directory 的每条记录均受声明末尾约束，遍历终点也须等于 `cd_offset + cd_size`；缩小 / 放大声明的回归测试已通过。 |
| R6 | ✅ 读入 `.npy` 成员名、写入空 key 均返回 `NpzUnsafeMemberName("")`；回归测试已通过。 |
| R7 | ✅ 固定种子 `decode_npz` fuzz 覆盖任意字节、真实归档变异及 EOCD 字段变异；成功解析时检查 `names()` / `get()` 自洽。 |
| R8 | ✅ 英中 README 已加入浏览器 Demo 入口；CI 加入 WASM GC 构建、带断言的 Node verifier 与浏览器内嵌资源漂移检查，§19 同步。 |
| R9 | ➖ 仍为可选流程建议；没有为凑数量补造 Issue / PR。 |

**本地验证：** `moon fmt --check`、`moon check --target native`、`moon test --target native`
（176/176）、coverage（core parser 130/132 = 98.5%，overall 996/1234 = 80.7%）、
NumPy fixture drift（31 + 3）、31/31 字节级 round-trip、NPZ 写入 Oracle（4 成员 +
UTF-8 key）、WASM verifier 与内嵌资源无差异检查均通过。`moon package` 归档解压到独立目录后，类型检查、
176 项测试、fixture 校验、WASM Demo 与 NPZ 写入 Oracle 再次通过。GitHub Actions
尚未在修复提交上远程运行。

## 核对摘要

| 编号 | 原审计事项 | 核对结果 | 优先级 |
|---|---|---|---|
| R1 | README 把 NPZ 写方向说成尚未实现 | 确认：英文、中文 Limitations 均与 N7 功能说明冲突 | P1 |
| R2 | README 测试数量有漂移 | 部分确认：英中 M5 行不一致；`tests/` 的 167 是正确子目录数，不应当作过期总数 | P2 |
| R3 | `acceptance.md` §19 未记录 NPZ 写 Oracle CI | 确认 | P1 |
| R4 | 主分支功能领先正式发布版本 | 确认：GitHub Release、Mooncakes 和 `moon.mod` 仍为 0.3.0 | P1 |
| R5 | 未核对 NPZ central-directory 声明长度 | 确认：遍历结束时未校验最终位置等于声明的目录末尾 | P2 |
| R6 | `.npy` 成员名可变为空 key | 确认：去后缀后未拒绝空字符串 | P2 |
| R7 | NPZ 缺少确定性变异 fuzz | 确认：现有 fuzz 不调用 `decode_npz` | P2 |
| R8 | WASM Demo 未进入 README/CI | 确认：文件存在，README 和 CI 均未引用其 verifier | P2 |
| R9 | GitHub Issue / PR 轨迹 | 状态属实（各 0）；这是流程建议，不是代码缺陷 | P3/可选 |

**对原审计的计数修正：** `tests/` 中有 167 个测试声明；另外 `src/npz/crc32_wbtest.mbt` 有 1 个、`examples/npz_write/npz_write_wbtest.mbt` 有 2 个 whitebox 测试，全仓合计 170 个。因此 README Layout 中“tests/（167）”计数准确。需要澄清的是英中 README 的 M5 行：英文保留了 159 / 81.7% 旧快照，中文写 170 / 80.5%；两者与当前总览不一致。

## 原审计问题（修复前证据）

### R1 — README 对 NPZ 写支持的描述互相矛盾（P1）

- **证据：** 两份 README 的 Features、API 和 N7 demo 已说明 `encode_npz` 写出未压缩 NPZ，并经 NumPy Oracle/CI 验证；但英文 `README.md` Limitations（约第 551–552 行）与中文 `README_CN.md` Limitations（约第 537–538 行）仍称 `savez` 写方向未实现。
- **影响：** 读者无法判断项目是否支持 NPZ 写入，发布版功能范围也不清晰。
- **原待办：** 同步两份 README，准确说明未压缩 NPZ 读写均已实现，并列明压缩/deflate、zip64、加密等未支持范围；同时明确 N7 尚未随正式版本发布。

### R2 — README 的里程碑测试数和中英文状态未对齐（P2）

- **证据：** `README.md` M5 行为 159 个测试、overall 81.7%；`README_CN.md` 同一行是 170 个测试、overall 80.5%。两份 README 的当前总览均为 170 个测试、80.5%。`CHANGELOG.md` 记录 N7 将测试数从 159 增至 170。
- **计数澄清：** `tests/` 目录内 167 个声明准确；再加 3 个 whitebox 测试，全仓为 170。不要把 Layout 中的 167 直接改成 170；如要避免误读，可写清“tests/ 167；全仓 170（含 3 个 whitebox）”。
- **原待办：** 统一英中 M5 行的含义与覆盖率快照；若 159 / 81.7% 表示 M5 完成时的历史值，就标成历史里程碑，并与当前总览的 170 / 80.5% 区分。

### R3 — 权威验收规范 §19 缺少 N7 Oracle CI 门禁（P1）

- **证据：** [CI workflow](../.github/workflows/ci.yml) 第 146–171 行已有 MoonBit `encode_npz` → Python `zipfile` CRC 检查与 `np.load` 数值校验，并覆盖 UTF-8 key；[验收规范 §19](spec/acceptance.md) 的门禁清单没有这一步。
- **影响：** 仓库自称的规范与实际 CI 不一致，读者无法从规范了解 NPZ 写方向的发布验收证据。
- **原待办：** 在 §19 增加对应门禁描述，并保留 `ci.yml` 为可执行事实源。

### R4 — 主分支和已发布版本之间存在交付差距（P1）

- **证据：** GitHub `main` 当前为 `d9fdcd6`，包含 N7 `encode_npz`；`moon.mod` 仍为 0.3.0，GitHub 最新 Release 是 2026-09-10 的 v0.3.0，Mooncakes 当前列出的最新包也为 0.3.0。
- **影响：** 依赖已发布包的用户拿不到主分支的 NPZ 写能力。
- **原待办：** 将 v0.4.0 作为候选版本进行发布准备评估；它是原审计的建议，尚非已批准的版本决定。发布前确定兼容性、更新版本与 changelog，再验证 GitHub Release、Mooncakes 包和干净环境安装结果。

### R5 — NPZ parser 未校验 central-directory 最终长度（P2）

- **位置：** `src/npz/npz.mbt` 第 200、206–270 行；测试位于 `tests/npz_test.mbt`。
- **证据：** 代码检查 `cd_offset + cd_size` 不得越过 EOCD；之后按 `total_entries` 遍历，但记录边界只与整个文件长度比较。遍历结束后直接返回 archive，没有检查最终 `pos == cd_offset + cd_size`。
- **影响：** 声明的 `cd_size` 与实际遍历到的 central-directory 末尾不一致时，容器仍可能被接受。
- **原待办：** 拒绝目录长度不一致的归档，并为缩小/放大 EOCD `cd_size` 的变异输入添加回归测试。

### R6 — 成员名 `.npy` 会产生空 key（P2）

- **位置：** `src/npz/npz.mbt` 第 154–168、223–230、279–288 行；测试位于 `tests/npz_test.mbt`。
- **证据：** `resolve_member_name` 会移除尾部 `.npy`，但没有检查结果是否为空；`unsafe_member_name("")` 返回 false。因此 raw member name `.npy` 可进入 archive 并以空字符串作为 key。
- **影响：** `NpzArchive` 可以暴露一个非预期的空 key，调用方也可通过 `get("")` 访问。
- **原待办：** 明确空 key 的策略；若拒绝，则返回结构化错误并添加 `.npy` 成员回归测试。

### R7 — NPZ parser 缺少变异 fuzz 覆盖（P2）

- **证据：** `tests/fuzz_test.mbt` 的 totality invariant 调用 NPY `decode` / `validate`；没有调用 `decode_npz`。`tests/npz_test.mbt` 有边界与性质测试，但未对任意字节、真实归档变异或 EOCD 字段变异运行 NPZ fuzz。
- **影响：** 复杂的 EOCD 搜索、central-directory 遍历和偏移处理没有与 NPY 层相同的任意输入鲁棒性证据。
- **原待办：** 增加固定种子的 NPZ 变异 fuzz：覆盖任意字节、真实 fixture 截断/翻转/追加，以及 EOCD offset/size/count 变异；要求只返回 `Ok` 或结构化 `Err`，不 trap。若返回 `Ok`，再检查 `names()` / `get()` 自洽。

### R8 — 浏览器 WASM Demo 未进入 README 和 CI（P2）

- **证据：** `examples/wasm-demo/` 中存在 `index.html` 和 `verify_demo.mjs`；两份 README、`.github/workflows/ci.yml` 与 `docs/spec/acceptance.md` 均没有引用 `wasm-demo` 或 `verify_demo.mjs`。
- **影响：** 评审者不容易发现已有的浏览器演示；Demo 的可运行性也未成为自动门禁。
- **原待办：** 在两份 README 的靠前位置加 Demo 入口与运行说明；检查 verifier 的运行依赖后，将它纳入 CI 和 §19。

### R9 — Issues / PR 数为零（P3，可选流程建议）

- **核对：** 截至核对时，GitHub 仓库显示 0 Issues、0 Pull Requests。
- **判断：** 这不是代码质量缺陷，也不意味着要补造历史。原审计建议用一个真实的 Final Acceptance Issue 和最终收尾 PR 记录剩余工作；是否采用由项目工作方式决定。

## 整改与剩余执行清单

- [x] 修订并同步 README 中 NPZ 能力说明；澄清 M5 历史值、当前值和 `tests/` / 全仓计数。
- [x] 在 `docs/spec/acceptance.md` §19 同步 NPZ 写方向 Oracle 门禁。
- [x] 修复并覆盖 central-directory 长度不一致与空 NPZ key 两个边界。
- [x] 为 `decode_npz` 增加确定性变异 fuzz。
- [x] 在 README 展示 WASM Demo，并将 verifier 接入 CI / §19。
- [ ] 发行：已完成 v0.4.0 候选兼容性评估并更新 manifest 与未发布 changelog，GitHub 登录已核验；待确认远端提交方式与正式发布、填写实际发布日期、验证远端 CI 后发布 GitHub Release 与 Mooncakes 包。
- [x] 将当前工作树打包并解压到独立目录，复现构建、测试、fixture、WASM Demo 与 NPZ 写入 Oracle。
- [ ] 核实正式验收提交入口并完成提交：赛事[官方页面](https://moonbitlang.github.io/Hackathon2026/)写明 2026-09-30 报名与验收截止；[公开源码](https://github.com/moonbitlang/Hackathon2026/blob/main/src/App.tsx)仅给出报名表，独立验收入口及具体时刻仍需从[正式章程](https://bxup9uklfcb.feishu.cn/wiki/Dx4Bwd6D1i3GfHkajQCcF7SznEd)或组委会通知确认。
- [ ] （可选）仅在项目工作流需要时用真实 Issue / PR 跟踪与交付，不补造历史。

## 本轮不纳入的功能扩展

- NPZ deflate / `savez_compressed` 解压、zip64。
- 任意 typed-array 到 NPY 的构造 API。
- mmap、跨文件 streaming 或大规模重构。
- 为提高数字而单纯扩展 dtype 或覆盖率。

## 原核对时确认的正向事实（修复前）

- 本地 `main` 与 GitHub `main` 都是 `d9fdcd6efa5ba3927a041526e12bb52cdb064555`。
- 该 commit 对应最新 CI run 为 success（2026-09-13）；当前没有后续主分支提交。
- N7 写方向与 NumPy Oracle 已在 workflow 实际执行；问题是规范文档没有同步。
- `tests/` 167 + 3 个 whitebox = 全仓 170；当时总览为 core parser 98.5%、overall 80.5%。

## 参考链接

- [GitHub main](https://github.com/ShunjunGu/moon-npy/tree/main)
- [GitHub Releases](https://github.com/ShunjunGu/moon-npy/releases)
- [GitHub Actions](https://github.com/ShunjunGu/moon-npy/actions?query=branch%3Amain)
- [Mooncakes 0.3.0 package](https://mooncakes.io/docs/ShunjunGu/moon-npy@0.3.0)
- [GitHub Issues](https://github.com/ShunjunGu/moon-npy/issues) · [Pull requests](https://github.com/ShunjunGu/moon-npy/pulls)
- [当前 NPZ parser](https://github.com/ShunjunGu/moon-npy/blob/main/src/npz/npz.mbt)
- [CI workflow](https://github.com/ShunjunGu/moon-npy/blob/main/.github/workflows/ci.yml) · [Acceptance spec](https://github.com/ShunjunGu/moon-npy/blob/main/docs/spec/acceptance.md)
