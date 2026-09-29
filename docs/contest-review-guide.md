# 9 月 26 日申报辅助材料与评审路径

本文提供可核验的技术事实、复现步骤与证据索引，供评审直接查阅。
根据最新验收通知，审核通过的选手无需在验收前再次提交表格，只需持续开发并将
对应内容上传到 GitHub。[最后阶段任务清单](contest-final-week-task-checklist.md)记录交付状态。

此前准备的[申报书草稿](contest-application-draft.md)与[模板](contest-application-template.md)
仅作为项目背景材料留存，不是当前验收所需文件。

## 项目事实与版本口径

- 公开源码：<https://github.com/ShunjunGu/moon-npy>；许可证：[Apache-2.0](../LICENSE)。
- 定位：纯 MoonBit 的 NPY 读写与未压缩 NPZ 容器互操作；核心格式处理无需 Python
  运行时，下面的 Python 命令仅用于外部 NumPy 校验。
- 本文复现基线：`fb556f2ea5c5bebece009d5b62d9f4d95a7d2a45`。该提交的
  [模块清单](../moon.mod)声明 `0.4.0`；仓库现有发行记录将它标为候选，已发布包为
  `0.3.0`。本次未重新核验线上发行状态，提交申报前应更新。
- NPY 支持 v1/v2/v3、13 种数值 dtype、大小端与 C／Fortran 存储顺序。访问器返回
  按存储顺序排列的扁平数组。NPZ 写入是源码候选能力，不能用 `0.3.0` 安装命令复现。
- 边界：拒绝 object/pickle；不支持 structured dtype、压缩 NPZ、zip64、mmap 或
  磁盘流式读取。Writer 重编码已解码的数组，不提供任意类型化数组构造接口。
  详见 [README](../README_CN.md) 与[验收规范](spec/acceptance.md)。

## 三个场景的复现材料

前置：MoonBit 与可用的 native 编译环境；外部校验使用 Python 3.14 / NumPy 2.3.4。
CI 的 moonc pin 为 `0.10.14+7d59c7ec9`，`moon version` 显示
`0.1.20260920 (914d7da)`。工具安装、依赖下载和首次编译不计入演示时间。
以下命令均在仓库根目录运行，每条应以退出码 0 结束；命令采用单行形式，可用于
PowerShell 或 Bash。

```sh
git clone https://github.com/ShunjunGu/moon-npy
cd moon-npy
git checkout fb556f2ea5c5bebece009d5b62d9f4d95a7d2a45
moon check --target native
python -c "from pathlib import Path; Path('_build/contest-0926').mkdir(parents=True, exist_ok=True)"
```

最终验收时应改用已验证的发行提交。当前固定 SHA 用于复现本文事实。

### 场景一：读取外部 NPY 数组

| 要素 | 技术素材 |
|---|---|
| 使用需求 | MoonBit 程序接收 Python 预处理后的数值数组，检查布局并提取数值 |
| 输入 | 仓库内 NumPy 生成的 float32、C-order、shape `(2, 3)` fixture |
| API 路径 | `reader.decode(bytes)` → `NpyArray` → `to_f32()`；CLI 展示同一读取能力 |
| 输出与判定 | shape `[2, 3]`、6 个元素、24 字节 payload，元素依次为 `0` 至 `5` |
| 使用边界 | 消费方按 shape 和存储顺序解释扁平数组，库不进行数值计算 |

```sh
moon run cmd/main --target native -- inspect tests/fixtures/f4_2x3_c_le_v1.npy
moon run cmd/main --target native -- dump tests/fixtures/f4_2x3_c_le_v1.npy --limit 6
```

实现：[Reader](../src/reader/reader.mbt)；命令入口：[CLI](../cmd/main/main.mbt)。

### 场景二：NPY 在 MoonBit 与 NumPy 间往返

| 要素 | 技术素材 |
|---|---|
| 使用需求 | MoonBit 接收并重新输出已有数组，交回 Python 流程校验 |
| 输入 | 场景一的 NPY fixture |
| API 路径 | `reader.decode` → `writer.encode` → 文件输出 → NumPy Oracle |
| 输出与判定 | `roundtrip.npy`，数值、dtype、shape 与输入相同，示例逐字节比较通过 |
| 使用边界 | 证明该 fixture 的重编码往返，不等于任意合法 NPY 的原始 header 字节都保持不变 |

```sh
moon run examples/roundtrip --target native -- tests/fixtures/f4_2x3_c_le_v1.npy _build/contest-0926/roundtrip.npy
python interoperability/verify_moonbit_output.py _build/contest-0926/roundtrip.npy --reference tests/fixtures/f4_2x3_c_le_v1.npy --byte-exact tests/fixtures/f4_2x3_c_le_v1.npy
```

成功标志：`roundtrip OK` 与 `[verify] PASS`。
[示例实现](../examples/roundtrip/main.mbt)和[Oracle](../interoperability/verify_moonbit_output.py)
可直接检查；完整 31 个 fixture 的验证入口是 `python interoperability/roundtrip.py`。

### 场景三：未压缩 NPZ 多数组交换

| 要素 | 技术素材 |
|---|---|
| 使用需求 | 将不同 dtype／shape 的多个数组按名称放入一个文件，供后续程序分别读取 |
| 输入 | `features`：float32 `(2, 3)`；`labels`：int32 `(4,)`，仅为异构成员演示，不表示样本一一对应 |
| 写入路径 | 各 NPY 经 `reader.decode` → `NpzMember` → `npz.encode_npz` → `demo.npz` |
| 读取路径 | MoonBit `npz.decode_npz(bytes)` → `names()` / `get(name)` → NPY 数组访问器 |
| 输出与判定 | 两个具名成员；NumPy 逐成员 dtype／shape／数值相同，ZIP_STORED 与 CRC-32 校验通过 |
| 使用边界 | 仅未压缩 NPZ；NPZ 文件整体不承诺与 `np.savez` 逐字节相同 |

```sh
moon run examples/npz_write --target native -- _build/contest-0926/demo.npz features=tests/fixtures/f4_2x3_c_le_v1.npy labels=tests/fixtures/i4_4_c_le_v1.npy
python interoperability/verify_npz_output.py _build/contest-0926/demo.npz --reference features=tests/fixtures/f4_2x3_c_le_v1.npy --reference labels=tests/fixtures/i4_4_c_le_v1.npy
moon test --target native
```

前两条展示 MoonBit 写入 → NumPy 读取，成功标志为 `npz_write OK` 与
`[verify-npz] PASS`。最后一条包含 MoonBit NPZ 读写测试：按名读取、成员缺失、
encode → decode 及拒绝边界；CLI 的 `inspect` 只接收 NPY，不应用于 NPZ。
证据：[NPZ 读取测试](../tests/npz_test.mbt)、[NPZ 写入测试](../tests/npz_write_test.mbt)、
[写入示例](../examples/npz_write/main.mbt)、[NumPy Oracle](../interoperability/verify_npz_output.py)。

## 1–2 分钟评审路径

建议提前运行上述命令并保留结果；全量测试、安装及编译时间不包含在两分钟内。

| 时间 | 展示动作 | 评委可核对的证据 |
|---|---|---|
| 0:00–0:20 | 从 README 打开本文，说明项目定位和候选版本边界 | 纯 MoonBit 格式互操作；不做 NumPy 数值计算 |
| 0:20–0:45 | 展示场景一的 inspect / dump，再展示场景二往返结果 | shape、6 个值、NumPy PASS |
| 0:45–1:10 | 展示场景三的 NPZ 生成和 Oracle 输出 | 两个成员、CRC 与逐成员比较 PASS |
| 1:10–1:40 | 本地浏览器打开 Demo，选择内置样例 | 页面显示 dtype、shape 和数值 |
| 1:40–2:00 | 打开 CI 与限制说明 | 自动验证范围、未覆盖的人工交互和发行待办 |

浏览器入口：[自包含 WASM Demo](../examples/wasm-demo/index.html)。应先下载／克隆再在
支持 WASM GC 的浏览器中打开本地 HTML；GitHub 文件预览不是在线运行页面。
浏览器型号、版本、内置样例／本地文件／损坏输入结果及截图需另行人工记录，
本文不将 Node verifier 等同于浏览器交互验收。

CI 入口：[Actions](https://github.com/ShunjunGu/moon-npy/actions)；
[清单已有的基线运行](https://github.com/ShunjunGu/moon-npy/actions/runs/36152486101)。
历史链接用于追溯，最终发行应补充对应发行 SHA 的成功 CI 链接。

## 旧版复现记录与当前验收证据

### 2026-09-26 本地复现记录

当时的验证环境：Windows / PowerShell，MoonBit 显示版本 `0.1.20260827 (d0aaa07)`，
Python 3.14.0，NumPy 2.3.4。将上述固定提交用 `git archive` 导出至干净目录，
不复制工作区修改或构建产物；依赖来自本机缓存，因此本记录不证明全新网络下载可用。
从本文提取各命令块中的检查、示例及测试命令，依次运行，退出码均为 0。

| 检查 | 实测结果 |
|---|---|
| `moon check --target native` | 通过 |
| NPY inspect / dump | float32、`[2, 3]`、6 个元素，数值 `0` 至 `5` |
| NPY 往返 Oracle | 152 字节；dtype／shape／数值及逐字节比较均 PASS |
| NPZ 写入 Oracle | 514 字节、2 个成员；CRC、ZIP_STORED、具名数组比较均 PASS |
| `moon test --target native` | 176 个测试通过，0 失败 |
| `moon fmt --check` | 通过 |

这次复现不包含远端 clone、浏览器人工交互、在线链接匿名访问或正式发行验证；
对应待办仍保留在任务清单中。

### 当前验收核对

| 字段 | 准备内容／状态 |
|---|---|
| 提交方式 | 最新通知称审核通过者无需再次提交表格；保持开发并将内容上传 GitHub |
| 报名状态 | 由参赛者私下核对原审核结果 |
| 申报草稿与模板 | 历史背景资料；不作为本次验收要求 |
| 至少三个完整场景 | 本文提供输入、操作、输出、判定和边界，供人工撰写引用 |
| 仓库、演示与 CI | 本文提供索引；提交前核对公开可访问及版本对应关系 |
| Mooncakes 与 Release | 最终版本、发布状态和发行 SHA 待发行阶段核对 |

公开记录只写核对日期、非敏感结论和公开链接。本文不是主办方通知。
