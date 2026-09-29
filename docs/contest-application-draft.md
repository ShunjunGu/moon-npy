# moon-npy：面向 MoonBit 的 NumPy 数组文件互操作库

> 项目申报书草稿 · 2026-09-26 · AI 辅助起草，供参赛者自行改写与核实，尚未定稿。
> 2026-09-29 最新验收通知：审核通过的选手无需在验收前再次提交表格；本草稿仅作历史背景材料。

**公开仓库：** <https://github.com/ShunjunGu/moon-npy>

**开源许可证：** Apache-2.0
**申报方向与最终验收版本：** 由参赛者依据正式表单及发行结果补充。

## 项目定位与价值

moon-npy 是使用 MoonBit 实现的 NumPy NPY 数组文件读写库，并提供未压缩 NPZ
多数组容器的读写能力。项目面向需要在 MoonBit 与 Python 之间交换数值数据的开发者：
Python 侧可以继续使用 NumPy 准备数据，MoonBit 侧直接读取数组的类型、形状、存储顺序
和元素，也可以将已读取的数组重新输出，交回 Python 校验与使用。

项目聚焦数组文件互操作，与数值计算库分工协作。核心格式处理无需 Python 运行时或
Python FFI；Python 仅用于开发验证中的外部对照。已有的 moonNum 读取适配器支持将
小端 float32／float64 数组接入其多维数组模型，为后续数值处理提供数据入口。

## 三个完整使用场景

**一、在 MoonBit 中读取 Python 预处理数据。** 开发者将 NumPy 生成的 `.npy`
文件交给 MoonBit 程序，通过 `reader.decode` 校验文件并取得数组，再用 `to_f32`
等访问器提取元素，供下游程序按形状和存储顺序使用。项目中的 `(2, 3)` float32
样例可由 CLI 的 `inspect` 查看元数据、由 `dump` 输出数值，结果为 6 个元素
`0` 至 `5`。该流程展示了从外部文件到 MoonBit 数组访问的完整读取过程。

**二、在 MoonBit 与 NumPy 之间往返保存数组。** 跨语言数据流水线需要确认数组经过
MoonBit 读写后仍能被 Python 正确读取。项目的 roundtrip 示例先解码输入 NPY，
再用 `writer.encode` 重编码并保存，最后由 NumPy 校验 dtype、shape 和元素值。
上述样例的输出为 152 字节，与参考文件逐字节一致。这一能力适用于已有数组的交换
与重序列化；当前不提供从任意 MoonBit 类型化数组直接构造 NPY 的接口，也不承诺
保留任意输入文件的原始 header 文本。

**三、以未压缩 NPZ 交换多个具名数组。** 当一次交付包含多个数组时，开发者可以将
各个 NPY 文件读入，组成具名成员，再用 `npz.encode_npz` 写入一个 NPZ 文件。
接收方在 MoonBit 中通过 `decode_npz`、`names()` 和 `get(name)` 按名称访问数组，
也可直接用 NumPy 加载。演示将 float32 `(2, 3)` 与 int32 `(4,)` 两个独立数组打包为
`features`、`labels`，输出 514 字节的归档；外部校验确认两个成员的类型、形状和数值
一致，并通过 CRC-32 与未压缩存储方式检查。两组数组仅演示异构成员，不表示样本配对。

## 实现与验证

项目支持 NPY v1／v2／v3、13 种数值 dtype、大小端以及 C／Fortran 存储顺序，
提供显式的结构化错误和 `inspect`、`validate`、`dump` 命令。2026-09-26 对固定源码
提交的干净导出目录进行复现：类型检查、格式检查及 176 项测试全部通过，以上 NPY
往返和 NPZ 写入的 NumPy 校验通过。NPZ 测试还覆盖 MoonBit 按名读取与读写往返。

评审可从[中文 README](../README_CN.md)进入
[三个场景的复现命令与验证记录](contest-review-guide.md)，并查看
[CI](https://github.com/ShunjunGu/moon-npy/actions)及
[浏览器 WASM Demo](../examples/wasm-demo/index.html)。Demo 需下载后在支持 WASM GC
的浏览器中打开；浏览器人工交互证据仍待补齐。

## 当前边界与交付计划

当前实现全内存处理，不支持 object/pickle、structured dtype、压缩 NPZ、zip64、
mmap 或磁盘流式读取。源码清单版本为 `0.4.0` 候选；本草稿依据的仓库记录中，
已发布版本为 `0.3.0`，NPZ 写入需从源码运行，最终发布状态仍需核对。
赛前工作将集中于正式发行、已发布包的消费者验证和演示证据补齐，保持核心功能范围稳定。

---

改写时请补充真实的选题动机与开发体会，并按正式字段确认申报方向、发行版本、提交 SHA
及对应链接；不要将尚未完成的发行或人工验收写为已完成。技术事实以
[复现记录](contest-review-guide.md)为依据。
