# interoperability/ — NumPy 兼容性 Oracle

本目录是 moon-npy 的**跨语言兼容性验证层**。moon-npy 是 Pure MoonBit 的 NPY 读写库，
不重新实现 NumPy；正确性以**当前 NumPy 的实际行为**为唯一 Oracle（计划 §15/§16/§21，
字节证据见 `../../moon-npy-plan-v0.2.md` 附录 A）。

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
| `verify_moonbit_output.py` | 校验 MoonBit Writer 产物（`np.load` / `array_equal` / 逐字节），M3/M4 阶段启用 |
| `../tests/fixtures/*.npy` | 生成的 fixture（Reader 测试输入） |
| `../tests/fixtures/expected.json` | 每个 fixture 的期望 version/descr/shape/order/header_len/data_offset/checksum/values |

## 生成 / 校验 fixture

```bash
# 生成 P0 种子集（float32 2×3 C-order × v1.0/v2.0/v3.0）
python interoperability/generate_fixtures.py

# 校验现有 fixture 未漂移（CI 用；重算 sha256 与 expected.json 比对）
python interoperability/generate_fixtures.py --check

# 展开 §15 完整矩阵（dtype × shape × order × endian × version，数百文件，供穷举扫描）
python interoperability/generate_fixtures.py --full
```

### 当前 P0 种子集

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
  全 0 会掩盖字节序 / 偏移类 bug（读错也「相等」）。
- **生成方式区分版本**（§8.4 / 附录 A.4）：v1.0 用 `np.save`（对简单数组恒产出 1.0）；
  v2.0/v3.0 **必须**用 `write_array(f, arr, version=(2,0)/(3,0))`，`np.save` 无法生成。
- **安全边界**：`verify_moonbit_output.py` 用 `allow_pickle=False`，拒绝 object/pickle
  数组（对应 Reader 的 `UnsupportedObjectArray`，计划 §5/§12）。

## CI 集成（§19）

```text
Generate NumPy Fixtures  → generate_fixtures.py（或 --check 断言未漂移）
MoonBit Reads NumPy      → moon test（Reader 断言对齐 expected.json）
MoonBit Generates NPY    → moon run（Writer 产出 out.npy）
NumPy Reads MoonBit      → verify_moonbit_output.py out.npy --reference <fixture>
Byte-level round-trip    → verify_moonbit_output.py out.npy --byte-exact <fixture>   # B1 回归
```
