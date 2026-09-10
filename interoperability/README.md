# interoperability/ — NumPy 兼容性 Oracle

本目录是 moon-npy 的**跨语言兼容性验证层**。moon-npy 是 Pure MoonBit 的 NPY 读写库，
不重新实现 NumPy；正确性以**当前 NumPy 的实际行为**为唯一 Oracle（验收边界规范 §15/§16/§21，
字节证据见仓库内 spec owner `../docs/spec/acceptance.md` 附录 A）。

## 锁定版本（可复现，§19）

| 组件 | 版本 |
|---|---|
| NumPy | **2.3.4** |
| Python | 3.14.0 |

CI 必须 pin 以上版本，与 `../AGENTS.md`（MoonBit `0.1.20260827`）一致，保证 fixture 可复现。

## 文件

| 文件 | 作用 |
|---|---|
| `generate_fixtures.py` | 用 `numpy.lib.format` 生成 `.npy` fixture，并从**真实产物字节**反推 `expected.json` |
| `verify_moonbit_output.py` | 校验 MoonBit Writer 产物（`np.load` / `array_equal` / 逐字节）；单一 Oracle 真相源 |
| `roundtrip.py` | **M4 跨语言 driver**：`expected.json` 驱动，逐 fixture `emit`（`moon run examples/roundtrip`）+ `verify`，聚合 `[PASS]/[FAIL]`，任一失败退出 1 |
| `../tests/fixtures/*.npy` | 生成的 fixture（Reader 测试输入 + round-trip 输入） |
| `../tests/fixtures/expected.json` | 每个 fixture 的期望 version/descr/shape/order/header_len/data_offset/checksum/values；亦是 `roundtrip.py` 的 fixture 清单来源 |

## 生成 / 校验 fixture

```bash
# 生成 P0 种子集（float32 2×3 C-order × v1.0/v2.0/v3.0）
python interoperability/generate_fixtures.py

# 校验现有 fixture 未漂移（CI 用；重算 sha256 与 expected.json 比对）
python interoperability/generate_fixtures.py --check

# 展开 §15 完整矩阵（dtype × shape × order × endian × version，数百文件，供穷举扫描）
python interoperability/generate_fixtures.py --full
```

### P0 种子集（当前 31 fixture 中的 3 个）

| 文件 | version | descr | shape | header_len | data_offset | file_nbytes |
|---|---|---|---|---|---|---|
| `f4_2x3_c_le_v1.npy` | 1.0 | `<f4` | (2,3) | 118 (uint16@8) | 128 | 152 |
| `f4_2x3_c_le_v2.npy` | 2.0 | `<f4` | (2,3) | 116 (uint32@8) | 128 | 152 |
| `f4_2x3_c_le_v3.npy` | 3.0 | `<f4` | (2,3) | 116 (uint32@8) | 128 | 152 |

三版覆盖两条 header-length 解析路径（v1.0 = `uint16@8`，v2.0/v3.0 = `uint32@8`），
且 v3.0 用**原始 dtype**（非 structured），在不触及 S3 范畴的前提下验证 P0 对 v3.0
的 uint32 长度字段与 UTF-8 header 读取（计划 §8.4 的 v3.0 覆盖策略）。

## 设计约束

- **Oracle = NumPy 真实产物**：`expected.json` 所有字段都从写出的字节解析得来，不手写、
  不臆测。MoonBit Reader 的断言应对齐 `expected.json`，而非对齐本文档的描述。
- **确定性**：不嵌入时间戳；相同 NumPy 版本重跑 → 字节一致的 `.npy` 与 `expected.json`。
  CI 可用「重生成 + `git diff` 为空」或 `--check` 断言 fixture 未漂移。
- **非平凡值**：元素用 `arange` 铺 `0..n-1`（bool 用奇偶交替），刻意**不用全 0**——
  全 0 会掩盖字节序 / 偏移类 bug（读错也「相等」）。complex 取 `im = 2 * re`（实部虚部不等，
  re/im 交错读取会立刻失败）；`expected.json` 里的 complex 以 `[re, im]` 二元组表示
  （`json.dumps` 不能直接序列化 Python `complex`）。
- **生成方式区分版本**（§8.4 / 附录 A.4）：v1.0 用 `np.save`（对简单数组恒产出 1.0）；
  v2.0/v3.0 **必须**用 `write_array(f, arr, version=(2,0)/(3,0))`，`np.save` 无法生成。
- **安全边界**：`verify_moonbit_output.py` 用 `allow_pickle=False`，拒绝 object/pickle
  数组（对应 Reader 的 `UnsupportedObjectArray`，计划 §5/§12）。

## CI 集成（§19）

§19 pipeline 已落地为 `../.github/workflows/ci.yml`（pin MoonBit `0.1.20260827+d0aaa07` /
NumPy `2.3.4` / Python `3.14`）。各阶段 → 实际命令：

```text
MoonBit Check            → moon check --target native
MoonBit Unit Tests       → moon test --target native（Reader/Writer 断言对齐 expected.json）
Generate NumPy Fixtures  → generate_fixtures.py --check（断言 fixture 未漂移）
MoonBit Reads NumPy      ┐
MoonBit Generates NPY    ├→ roundtrip.py：逐 fixture emit（moon run examples/roundtrip → out.npy）
NumPy Reads MoonBit      │              + verify（np.load / array_equal）
Byte-level round-trip    ┘              + 逐字节 vs Oracle（B1 回归）；31/31 通过
```

`roundtrip.py` 把「MoonBit 读 → 重新输出 → NumPy 校验（含逐字节）」三步合一，委托
`verify_moonbit_output.py` 做校验，保持单一 Oracle 真相源（§19 铁律：README 展示的例子
即 CI 实际运行的例子）。
