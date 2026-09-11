# Testing Patterns

**Analysis Date:** 2026-09-11

> 事实来源：`AGENTS.md` §7（M0 实测固化的测试/覆盖率命令）、`docs/spec/acceptance.md` §12/§13/§14/§15/§16/§19、
> `.github/workflows/ci.yml`（唯一 CI 定义处）、`interoperability/*.py`，以及全部 11 个 `tests/*_test.mbt` 的实读。
> 覆盖率与测试数均为本机 2026-09-11 实测。

## Test Framework

**Runner:**
- **MoonBit 内建测试框架** + `moon test`（工具链 pin：`moon 0.1.20260827 (d0aaa07 2026-08-27)`，AGENTS.md §0）。
  无第三方测试框架（无 Jest/Vitest/pytest 类比物）——测试块是语言与工具链的一等公民。
- **没有测试配置文件**：测试行为由 `moon.mod`（模块）与各 `moon.pkg`（包）决定，仓库内不存在 `*.config.*`。
- test-only 依赖在 `tests/moon.pkg` 用 `for "test"` 声明：
  ```toml
  import {
    "ShunjunGu/moon-npy/src/error",
    …
    "amor2025/moonNum/src/core",
    "moonbitlang/core/encoding/utf8",
    "moonbitlang/core/quickcheck/splitmix",
    "moonbitlang/x/fs",
  } for "test"
  ```
- **实测（2026-09-11）**：`moon test --target native` → `Total tests: 156, passed: 156, failed: 0.`

**Assertion Library:**
- **MoonBit 内建断言，无外部库**（AGENTS.md §7）：
  - `assert_eq(a, b)` —— 主要断言形式
  - `assert_true(cond)` / `assert_false(cond)`
  - 快照形态 `inspect(v, content=…)` / `debug_inspect(v, content=…)`（test 文件内自动可用，无 bang）
- **快照断言在本仓库完全未使用**（对项目内 `.mbt` 全文搜索 `inspect(` 无命中；仅第三方 vendored 的
  `.mooncakes/moonbitlang/x/codec/base64/base64_wbtest.mbt` 使用）。无 `moon test --update` 流程，
  也没有 `__snapshots__` 目录。见 Common Patterns 的「Snapshot Testing」。
- 关键约束：`assert_eq` / `assert_true` **带 error effect**，所以
  - 只能在 `test` block 内**直接**调用；
  - 想从 helper 内断言，helper 必须标注 `raise`：
    ```moonbit
    fn expect_dtype(descr : String, want_dt : @dtype.DType, want_order : @dtype.ByteOrder) -> Unit raise
    fn check_total(blob : Bytes) -> Unit raise
    ```
  - 非 `test` 上下文要失败只能用 `abort("…")`，且必须写注释说明原因（`tests/writer_test.mbt:51-53`）。

**Run Commands:**
```bash
moon test --target native                    # 全量（156 tests），提交前必跑
moon test --target native -f "parse_dtype_*" # 按测试名 glob 过滤（* / ? 通配）
moon test --target native tests/reader_test.mbt  # 单文件（PATH 参数，实测 25 tests）
moon test --target native -p ShunjunGu/moon-npy/tests  # 单包
moon test --target native -i 0-2             # 单文件内按序号（含左不含右）；需配合单文件选择
moon test --target native --outline          # 只列将执行的测试清单，不跑
moon test --target native --build-only       # 只编译不跑
moon test --update                           # 刷新快照（本仓库不用快照）
```
覆盖率：
```bash
moon test --target native --enable-coverage  # 插桩跑 + 生成 trace（_build/moonbit_coverage_*.txt）
moon coverage analyze                        # 一体化：插桩跑测试 + 终端 caret 报告
moon coverage report -f summary              # 从已有数据出汇总表（flag 是 -f，不是 --format）
moon coverage report -f bisect | caret | html | coveralls | cobertura | summary
moon coverage clean                          # 清理产物（bisect.coverage 等）
```
跨语言（需 Python 3.14 + NumPy 2.3.4）：
```bash
python interoperability/generate_fixtures.py            # 重生成入库 fixture 集
python interoperability/generate_fixtures.py --check    # 只校验未漂移（CI 用）
python interoperability/roundtrip.py -v                 # 31 fixture 的 NumPy→MoonBit→NumPy 字节级往返
python interoperability/verify_moonbit_output.py out.npy --reference X.npy --byte-exact X.npy
```
- **前置条件**：`moon` 可能不在 PATH —— `C:\Users\<user>\.moon\bin` 需脚本首行显式加入
  （AGENTS.md §0/§8）。PowerShell 下 moon 的 stderr 进度会被渲染成红色 `NativeCommandError`，
  判定以 `$LASTEXITCODE` 为准（AGENTS.md §8）。
- **无 watch 模式**（`moon test --help` 无 watch flag），也**没有 npm scripts 式的命令封装层**——
  一切直接调 `moon`。
- 本机 PowerShell/Node 相关的执行路径在本仓库不存在依赖（纯 MoonBit + Python），无此类前置。

## Test File Organization

**Location:**
- **全部测试集中在仓库根 `tests/` 单一包里**——既不与源码 colocat（不是 `src/x/x_test.mbt`），
  也不在 `src/` 下另开测试树。`tests/moon.pkg` 用 `for "test"` 声明对 9 个 src 包 + moonNum + splitmix + utf8 + fs 的引用。
- 白盒测试形态（`*_wbtest.mbt`、AGENTS.md §7 记载其存在）在本仓库**未使用**：`tests/` 下没有 `_wbtest.mbt`。
  工具链仍会为每个包生成 `<pkg>.internal_test.c`（实测 `moon test` 输出可见），但那是工具链行为，不是仓库约定。
- 仓库根另有两个可执行 example（`examples/roundtrip/`、`examples/bench/`），它们是 CI 的被测对象，不是测试文件。

**Naming:**
- Blackbox 测试文件统一 `<topic>_test.mbt`，用 `@pkg.` 前缀访问被测包的**公共 API**（AGENTS.md §7）。
- `test` block 名 **snake_case、动词/名词短语开头、无 issue 编号**，例如：
  `"decode_f4_2x3_v1"`、`"reject_invalid_magic"`、`"parse_dtype_reject_object"`、
  `"edge_shape_overflow_uint64"`、`"chunk_out_of_range"`、`"writer_roundtrip_byte_exact_all_fixtures"`、
  `"fuzz_fixture_mutations"`、`"decode_encode_roundtrip_is_byte_exact"`、
  `"object_dtype_refused_all_endian_forms"`、`"adapter_rejects_big_endian_fixture"`。
  负向用例统一 `reject_*` / `*_refused*` / `*_rejects_*` 前缀。
- 每个 `test` block 前必须有 `///|` 分隔符（AGENTS.md §8 块风格；`moon fmt` 会规整）。
- 大段落用横幅注释分组，横幅内带 spec 章节号：`// ---- negative: header body errors (§12) ----`。

**Structure:**
```
moon-npy/
├── src/                      # 被测代码（9 个包，见 CONVENTIONS.md）
│   ├── error/  format/  header/  dtype/  reader/  writer/  npz/  cli/  adapter/moonnum/
├── cmd/main/main.mbt         # 可执行 CLI（无单元测试，见 Test Types）
├── examples/roundtrip/       # CI round-trip 的 emit 端（无单元测试）
├── examples/bench/           # 性能微基准（无单元测试）
└── tests/                    # 单一 blackbox 测试包
    ├── moon.pkg              # import { … } for "test"
    ├── npy_test.mbt          (15)  format + header：magic/version/prefix 偏移、header 字面量解析
    ├── dtype_test.mbt        (16)  dtype：descr 矩阵、itemsize/name/descr_code 表、complex codec
    ├── reader_test.mbt       (25)  reader：validate/decode、13 个类型化 accessor、S4 chunk 窗口
    ├── writer_test.mbt        (4)  writer：字节级 round-trip 全 fixture + descr/padding 白盒点
    ├── edge_test.mbt         (17)  边界与防御分支（合成 blob，非 Oracle）
    ├── security_test.mbt      (3)  安全边界：'|O' / void dtype 在 payload 之前被拒
    ├── fuzz_test.mbt          (3)  §18 totality：随机字节 / 随机 body / fixture 变异
    ├── property_test.mbt      (1)  decode→encode 字节级属性 + 重解码等价
    ├── npz_test.mbt          (28)  NPZ 容器：手工 ZIP 装配 + 逐字段 patch 的拒绝用例
    ├── cli_test.mbt          (34)  CLI 纯逻辑：parse_args / 渲染 / 退出码
    ├── adapter_test.mbt      (10)  moonNum 适配：shape/strides/order + 三种拒绝
    └── fixtures/
        ├── *.npy                    31 个 NumPy 2.3.4 Oracle（见 Fixtures and Factories）
        ├── *.npz                     3 个 np.savez Oracle archive
        ├── expected.json            31 条 .npy 真值（sha256 + flat_values + 偏移）
        └── npz_expected.json         3 条 archive 真值
```
- **11 个 `_test.mbt` 文件同属一个包**（重要结构后果）：helper 在一处定义即全包可见，
  无需 import，也无 `tests/helpers/` 目录。实测跨文件复用链：
  | helper | 定义处 | 被谁用 |
  |---|---|---|
  | `load_fixture(name)` | `tests/npy_test.mbt:15` | `reader_test.mbt`、`writer_test.mbt`、`property_test.mbt`、`fuzz_test.mbt` |
  | `v1_with_body(body)` | `tests/npy_test.mbt:28` | `npy_test.mbt`、`edge_test.mbt`、`security_test.mbt` |
  | `oracle_fixture_names()` | `tests/npy_test.mbt:48` | `fuzz_test.mbt`、`property_test.mbt` |
  | `v1_raw(body : Array[Byte])` | `tests/edge_test.mbt:22` | `fuzz_test.mbt`（分布 2） |
  | `v1_with_payload(body, payload)` | `tests/edge_test.mbt:40` | `cli_test.mbt`、`adapter_test.mbt` |
  | `decode_fixture(name)` / `f32_as_doubles(arr)` | `tests/reader_test.mbt:10,17` | `adapter_test.mbt` |
  因此新增 fixture 或新增 helper 时，影响半径是**整个测试包**，命名冲突会直接编译失败（这也是保护）。

## Test Structure

**Suite Organization:**
- **没有 describe/it 嵌套**——MoonBit 只有扁平的 `test "name" { … }` 块，每个块前 `///|`：
  ```moonbit
  ///|
  test "reject_invalid_magic" {
    let bad = Bytes::from_array([
      b'N', b'O', b'T', b'N', b'P', b'Y', b'\x01', b'\x00',
    ])
    match @format.parse_prefix(bad) {
      Err(@error.InvalidMagic) => ()
      _ => assert_true(false)
    }
  }
  ```
  （`tests/npy_test.mbt:149-158`）
- 逻辑分组靠**横幅注释**（不是嵌套），横幅带 spec §号：
  ```moonbit
  // ---- format: manual little-endian assembly (§9.3, AGENTS.md §3 verified) ----
  // ---- negative: format prefix errors (§12) ----
  // ---- S4 streaming chunk reads: to_f32_chunk / to_f64_chunk (§29 Demo) ----
  ```
- **参数化用 `for` 循环，不生成多个 test 块**（两种形态）：
  ```moonbit
  test "parse_dtype_signed_ints" {
    expect_dtype("|i1", @dtype.Int8, @dtype.NotApplicable)
    expect_dtype("<i2", @dtype.Int16, @dtype.Little)
    expect_dtype(">i2", @dtype.Int16, @dtype.Big)
    …
  }
  ```
  ```moonbit
  for name in ["i2_4_c_le_v1.npy", "i2_4_c_be_v1.npy"] {
    let x = decode_fixture(name)
    assert_eq(x.dtype, @dtype.Int16)
    assert_eq(x.to_i16().unwrap(), [0, 1, 2, 3])
  }
  ```
  多元素矩阵用 `for … in [ … ]`，需要索引时用 `for k = 0; k < names.length(); k = k + 1`。
- 一个 `test` 块内允许多条断言，聚焦一个行为（例：`decode_signed_ints` 一次覆盖 i1/i2/i4/i8 × LE/BE）。
- 每个测试文件顶部有**文件级 block comment**，写明「测什么层 + 对齐哪个 spec § + 为什么这样设计」，
  例如 `tests/edge_test.mbt:1-15` 说明「这些用例是 SYNTHESIZED（不新增 fixture）」以及
  「合成 blob 刻意不做 64 字节对齐，正是为了覆盖 fixture 覆盖不到的 §7.4 容忍度」。

**Patterns:**
- **没有 setup / teardown / 生命周期 hook**（MoonBit test 无 `beforeEach` / `afterEach` / `beforeAll`）。
  共享状态靠**纯函数构造器**而非可变夹具（见 Fixtures and Factories），因此测试天然可并发、无顺序依赖。
- **无 mock、无 patch、无 test double**（见 Mocking）。所有输入是内存字节，所有期望值来自 Oracle 文件。
- 断言的三种固定形态：
  1. **正向**：`assert_eq(actual, expected)`，期望值来自 Oracle 而非手写
     ```moonbit
     assert_eq(a.header.descr, "<f4")
     assert_eq(f32_as_doubles(a), [0.0, 1.0, 2.0, 3.0, 4.0, 5.0])
     ```
  2. **负向（具体枚举分支）**——这是本仓库最强的断言纪律（`docs/spec/acceptance.md` §12
     「每条 negative case 断言**具体枚举分支**，不接受泛化失败」）：
     ```moonbit
     match res {
       Err(@error.InvalidMagic) => ()
       _ => assert_true(false)
     }
     ```
     带 payload 的错误**同时断言 payload**：
     ```moonbit
     match @reader.decode(blob) {
       Err(@error.DataLengthMismatch(24L, 0L)) => ()
       _ => assert_true(false)
     }
     ```
     ```moonbit
     Err(@error.InvalidChunkRange(s, l)) => { assert_eq(s, pair.0); assert_eq(l, pair.1) }
     ```
     绑定失败时读回 payload 做二次断言：`Err(@error.MissingHeaderField(f)) => assert_eq(f, "descr")`
  3. **布尔**：`assert_true(cond)` / `assert_false(cond)`，用于 `ByteOrder`、`fortran_order` 等
- **`.unwrap()` 在测试里是刻意的**：失败即 abort 整个 run（`moon test` 变红），所以 helper 里直接 unwrap 并配注释：
  ```moonbit
  // decode() a fixture and unwrap; aborts the test on an unexpected Err.
  fn decode_fixture(name : String) -> @reader.NpyArray {
    @reader.decode(load_fixture(name)).unwrap()
  }
  ```
- **测试失败信息必须能定位问题**（大循环场景）：
  ```moonbit
  if encoded != original {
    let mut diff = -1
    for i = 0; i < original.length(); i = i + 1 {
      if diff < 0 && encoded[i] != original[i] { diff = i }
    }
    abort("\{name}: bytes differ at offset \{diff}")
  }
  ```
  （`tests/writer_test.mbt:85-93`，同时报告 fixture 名、长度差与首个差异字节偏移）
- **白盒式的点测用 `abort` 而非 `assert_eq`**（因为 helper 内不能有带 error effect 的断言），
  并在注释里写明这是有意选择（`tests/writer_test.mbt:51-53`）。

## Mocking

**Framework:**
- **不适用——本仓库没有 mock 框架，也没有任何 mock / stub / spy / fake。** MoonBit 生态无此类库，
  项目也不引入。没有 `vi.mock()` 类比物，没有依赖注入容器。

**Patterns:**
- 替代手段 1：**把 IO 参数化掉，而不是 mock 掉**。最典型的证据是 `src/cli/cli.mbt` 被设计成零 `@fs` / `@env`
  的纯函数包：
  ```moonbit
  pub fn run_inspect(path : String, data : Bytes) -> CliOutcome
  pub fn run_validate(path : String, data : Bytes) -> CliOutcome
  pub fn run_dump(path : String, data : Bytes, limit : Int) -> CliOutcome
  ```
  字节由调用方传入，因此 `tests/cli_test.mbt` 完全不需要 mock 文件系统——它同时驱动
  `run_inspect(path, load_fixture("…"))` 与 `run_inspect(path, v1_with_body("{!"))`。
  源码注释明确这是架构目标：「Nothing in this package touches @fs / @env, which keeps the CLI compilable on
  every backend (§10.3) and covered directly by tests/cli_test.mbt.」（`src/cli/cli.mbt:5-7`）
- 替代手段 2：**内存合成字节 blob** 代替一切外部夹具（`v1_with_body` / `v1_raw` / `v1_with_payload` /
  `npy_v1` / `build_zip` / `put_u16` / `put_u32`，见 Fixtures and Factories）。
- 替代手段 3：**真实 Oracle 文件** 代替期望值硬编码（`load_fixture` + `expected.json`）。

**What to Mock:**
- 无。含 `Int64` 溢出、`UInt64` 回绕、非法 UTF-8、路径穿越名、ZIP 双写、zip 炸弹等场景，
  全部通过**直接构造恶意字节**覆盖（`tests/edge_test.mbt`、`tests/security_test.mbt`、`tests/npz_test.mbt`），
  不通过 mock 造假。
- 确定性随机由**真 PRNG + 固定种子**提供，而非 mock：`@splitmix.new(seed=0x5EEDUL / 0xC0FFEEUL / 0xBADC0DEUL)`
  （`tests/fuzz_test.mbt`），注释明确「so any failure is exactly reproducible -- no flakiness,
  no wall-clock entropy, and the run is byte-identical across machines and CI」。

**What NOT to Mock:**
- **一切都不 mock**，这是刻意的设计选择：
  - 不 mock `@fs` —— `load_fixture` 真实磁盘读（`tests/npy_test.mbt:15-21`）
  - 不 mock `@env` —— argv 作为 `Array[String]` 字面量直接传 `@cli.parse_args(["moon-npy", "inspect", "a.npy"])`
  - 不 mock 外部 moonNum 包 —— `tests/adapter_test.mbt` 真实调用 `@moonnum.to_moonnum_f32` 并断言
    `nd.shape()` / `nd.strides()` / `nd.get_f32(i)`（注释还记录了先用 NumPy 2.3.4 交叉核对过
    `np.arange(6,'<f4').reshape(2,3).strides == (12,4)` 等事实）
  - 不 mock 时间 —— 无时间相关代码路径

## Fixtures and Factories

**Test Data:**
- 夹具是**字节级二进制产物**，不是代码工厂。两层：
  1. **真值清单（golden files）**：`tests/fixtures/expected.json`（31 条 `.npy`）与
     `tests/fixtures/npz_expected.json`（3 条 archive）。每条 `.npy` 记录字段：
     ```
     file, version [major, minor], descr, dtype, byteorder, shape, fortran_order, itemsize,
     element_count, header_len, header_start, data_offset, data_nbytes, file_nbytes,
     aligned_64, sha256, data_sha256, values, flat_values, note
     ```
     其中 **`flat_values` = storage-order 扁平真值**，正是 MoonBit 扁平访问器（Q2：按 storage order 返回）
     必须逐元素对齐的 Oracle（`interoperability/generate_fixtures.py:282-284`）。
     顶层另有 `oracle: { numpy, python, generator, spec_ref, deterministic, note }` 与 `count`。
  2. **二进制 fixture**：`tests/fixtures/*.npy`（31）、`tests/fixtures/*.npz`（3）。

- **`*.npy` 命名契约**（解码见 `interoperability/generate_fixtures.py:319-322` 的 f-string）：
  ```
  <dtype>_<shape>_<order>_<endian>_v<major>.npy
  ```
  | 段 | 取值规则 | 实例 |
  |---|---|---|
  | `<dtype>` | descr 去掉首字符的 kind+size | `b1` `i1` `i2` `i4` `i8` `u1` `u2` `u4` `u8` `f4` `f8` `c8` `c16` |
  | `<shape>` | 各维用 `x` 连接；0-d 用字面量 `scalar` | `4`、`2x3`、`2x2x2`、`scalar` |
  | `<order>` | `c` = C-order；`f` = Fortran（仅当 `f_contiguous and not c_contiguous` 才为 `f`） | `c`、`f` |
  | `<endian>` | descr 首字符映射 `<`→`le`，`>`→`be`，`\|`/`=`→`na` | `le`、`be`、`na` |
  | `v<major>` | version major（不是 `1.0` 而是 `v1`） | `v1`、`v2`、`v3` |
  - 全解例：`f4_2x3_c_le_v1.npy` = float32 / shape (2,3) / C-order / little-endian / v1.0；
    `b1_4_c_na_v1.npy` = bool / (4,) / C / 字节序不适用 / v1.0；
    `i4_2x3_f_be_v1.npy` = int32 / (2,3) / Fortran / big-endian / v1.0；
    `f8_scalar_c_le_v1.npy` = float64 0-d scalar / C / LE / v1.0。
  - **无 `<endian>` 可选段**——`na` 是显式值（单字节 dtype 无字节序变体），不会省略。
  - 生成器对重名 `raise ValueError(f"duplicate fixture name: {name}")`。

- **`*.npz` 命名**（3 个，手工列举而非模式展开，`npz_archive_specs()`）：
  `npz_3arr_c_le_v1.npz`（positional `arr_0/arr_1/arr_2`）、
  `npz_customkey_c_le_v1.npz`（kwargs `w`/`v`）、
  `npz_deflated_c_le_v1.npz`（`np.savez_compressed` 产物，MoonBit 侧**必须拒绝**）。

- **入库 fixture 集 = `committed_specs()` = `p0_specs()`(3) + `m2_matrix_specs()`(28) = 31 个**（§15）：
  - P0 种子集：`<f4 (2,3)` C-order × v1.0/v2.0/v3.0 —— 三版覆盖两条 header-length 路径
    （v1.0 = `uint16@8`，v2.0/v3.0 = `uint32@8`）。
  - M2 codec 矩阵：11 种 dtype × 字节序 × `(4,)` C v1.0（单字节 b1/i1/u1 无字节序变体 → 19 个）
    + 0-d `f8`、3-D `i2`、F-order `<f4 (2,3)`、F-order BE `>i4 (2,3)`（4 个）
    + S1 complex `<c8/>c8/<c16/>c16 (4,)` 与 `<c8 (2,3)`（5 个）。
  - `--full` 展开完整矩阵（dtype × shape × order × endian × version，数百文件）但**默认不入库**。

- **Oracle 值刻意非平凡**（`make_values()`，`interoperability/generate_fixtures.py:155-173`，§附录 A.5）：
  - 数值用 `arange` 铺 `0..n-1`，**刻意不用全 0**——「全 0 会掩盖字节序 / 偏移类 bug（读错也『相等』）」
  - bool 用奇偶交替 `(i % 2 == 0)`
  - complex 取 **`im = 2 * re` 且故意不等**——实部/虚部读反会立刻在 Oracle 比对中失败
  - BE fixture 与其 LE 双胞胎共享同一 `flat_values`，所以「把 0x0001 读成 0x0100 = 256」这类
    字节序错误会立刻断言失败（`tests/reader_test.mbt:1-6` 的注释记录了这条设计）

- **测试端工厂（在 `tests/` 包内就近定义，跨文件共享）**：
  ```moonbit
  // 读 fixture 字节；Oracle 文件缺失/不可读时 abort（绝不让坏路径静默通过）
  fn load_fixture(name : String) -> Bytes {
    let path = "tests/fixtures/\{name}"
    let res = try @fs.read_file_to_bytes(path) |> Ok catch { e => Err(e) }
    res.unwrap()
  }                                                              // tests/npy_test.mbt:15

  // 最小 v1.0 blob：header body 由 String 传入，header_len 写 uint16 LE，无 payload、无对齐
  fn v1_with_body(body : String) -> Bytes { … }                  // tests/npy_test.mbt:28

  // 同上但 body 是原始 Array[Byte] —— 可注入非法 UTF-8（String 做不到）
  fn v1_raw(body : Array[Byte]) -> Bytes { … }                   // tests/edge_test.mbt:22

  // 完整 v1.0 blob：header + 紧随的 payload，无对齐填充
  fn v1_with_payload(body : String, payload : Array[Byte]) -> Bytes { … }  // tests/edge_test.mbt:40

  // NPZ：手工 ZIP 装配器（local header + payload + central dir + EOCD），返回可逐字段 patch 的偏移
  struct ZipEntry { name : Bytes; comp_method : Int; gp_flags : Int; payload : Bytes }
  struct ZipImage { bytes : Bytes; eocd : Int; cd : Array[Int]; locals : Array[Int] }
  fn build_zip(entries : Array[ZipEntry]) -> ZipImage { … }      // tests/npz_test.mbt:87
  fn put_u16(buf : Array[Byte], v : Int) -> Unit { … }           // tests/npz_test.mbt:68
  fn put_u32(buf : Array[Byte], v : Int) -> Unit { … }           // tests/npz_test.mbt:74

  // Oracle fixture 清单的单一真相源 —— 新增 fixture 只改这里，fuzz / property / round-trip 全部跟随
  fn oracle_fixture_names() -> Array[String] { [ …31 项… ] }      // tests/npy_test.mbt:48
  ```

**Location:**
- 二进制夹具：`tests/fixtures/`。`.gitattributes` 把 `*.npy` / `*.npz` 标为 **`binary`**（禁止行尾转换、
  文本 diff、merge），并全局 `* text=auto eol=lf`——因为「项目核心价值是字节精确的 NPY fixture，
  CRLF 重写不可接受」。
- 真值清单：`tests/fixtures/expected.json` / `tests/fixtures/npz_expected.json`。
- 生成器（**唯一 Oracle 生成来源**）：`interoperability/generate_fixtures.py`。
  其他 Python 工具：`roundtrip.py`（跨语言 driver）、`verify_moonbit_output.py`（NumPy 侧校验，单一 Oracle 真相源）、
  `probe_npz.py`（**非交付**的一次性探针，用于 pin ZIP 字节布局事实）。
- 测试辅助函数：**就近定义在 `tests/*.mbt` 内**（因为同一测试包，跨文件自动可见）。**没有** `tests/helpers/`
  或 `tests/factories/` 目录。
- 已知夹具治理隐患（实测）：**fixture 清单有两份且不一致**——
  `tests/npy_test.mbt:48` 的 `oracle_fixture_names()` 列 **31** 个（含 5 个 complex），
  而 `tests/writer_test.mbt:15` 的 `fixture_names()` 列 **26** 个（v0.2.0 加 complex 之前的快照）。
  注释声称前者是「single source of truth for the fuzz mutations, the round-trip property test, and X2」，
  但 writer 侧仍持有独立副本。新增 fixture 时**两处都要改**，否则 writer 的字节级 round-trip 门禁会漏掉新 dtype。

## Coverage

**Requirements:**
- **CI 阻塞阈值（`docs/spec/acceptance.md` §14；源 `.github/workflows/ci.yml` 的 `Coverage gate` 步骤）**：
  | 指标 | 阈值 | 分子定义 |
  |---|---|---|
  | **core parser** | **≥ 90%** | 文件名匹配 `/(format\|lexer\|parser)\.mbt:/` 的行求和 |
  | **project overall** | **≥ 80%** | `-f summary` 输出的 `Total:` 行 |
  任一跌破 → `awk` 退出非零 → 该 step 失败 → CI 红。
- **口径说明**（CI 注释原文）：未出现在 `moon coverage report -f summary` 输出里的文件视为 **100% 覆盖**，
  所以只累加列出的 core 文件是**保守下界**（把一个 100% 的文件折进聚合只会抬高比例）。
- **本机实测数值**（仓库根 `coverage-summary.txt`，`moon coverage report -f summary` 输出，2026-09-10 生成）：
  ```
  cmd\main\main.mbt:                0/26
  examples\roundtrip\main.mbt:      0/21
  src\cli\cli.mbt:                217/230
  src\dtype\dtype.mbt:            106/109
  src\header\lexer.mbt:            70/71
  src\header\parser.mbt:           59/60
  src\npz\npz.mbt:                102/105
  Total:                          822/890
  ```
  换算：
  - **core parser**：`format.mbt` 未出现在表中 → 计 100%；求和 `lexer 70/71 + parser 59/60 = 129/131` → **98.5%** ✓（阈值 90%）
  - **overall**：`822/890` → **92.4%** ✓（阈值 80%）
  - 0 覆盖的两个文件都是**可执行体**（`cmd/main`、`examples/roundtrip`），不被 `moon test` 触达 ——
    AGENTS.md §7 明确记为「正常」，它们由 CI 的 CLI 冒烟与 round-trip 步骤覆盖（见 Test Types）。
  - 未出现在表中的源文件（`format.mbt`、`codec.mbt`、`endian.mbt`、`complex.mbt`、`error.mbt`、`reader.mbt`、
    `writer.mbt`、`header.mbt`、`adapter.mbt`）按上述口径均视为 **100%**。
- **文档数值存在小分歧（实测）**：`docs/spec/acceptance.md` §14 记 overall **91.7%**、
  `CHANGELOG.md` v0.2.0 亦记 91.7%；而 `coverage-summary.txt` 与 `README_CN.md` 记 **92.4%**。
  92.4% 是 v0.3.0（新增 `src/npz` 后分母扩大到 890）的最新实测，与 `coverage-summary.txt` 的 `822/890` 一致。
  **以 `coverage-summary.txt` 为准**；§14 的 91.7% 是未同步的旧值（阈值本身 90%/80% 不受影响）。
- **逐包覆盖（读自 summary）**：`src/npz` 102/105 = 97.1%、`src/cli` 217/230 = 94.3%、
  `src/dtype` 106/109 = 97.2%、`src/header/lexer` 70/71 = 98.6%、`src/header/parser` 59/60 = 98.3%。

**Configuration:**
- 工具：**MoonBit 内建 coverage**（无第三方、无 `nyc`/`c8` 类比物）。
- **无 exclusions 配置文件**。core parser 的判定正则**硬编码在 CI 的 awk 脚本里**：
  ```awk
  /(format|lexer|parser)\.mbt:/ { split($2, a, "/"); cc += a[1]; ct += a[2] }
  ```
- 覆盖率产物被 `.gitignore` 忽略：`*.coverage` / `bisect.coverage` / `uncovered.log` / `coverage-summary.txt`。
  实测 `git ls-files` 确认这两个文件**未被 git 跟踪**——它们只是本机工作树里的残留产物（CI 每次重新生成）。
- 仓库内另有 `bisect.coverage`（`BISECT-COVERAGE-4` 格式，`moon coverage report -f bisect` 的默认输出），
  同样未被跟踪。

**View Coverage:**
```bash
moon test --target native --enable-coverage
moon coverage analyze                       # 一体化：插桩跑测试 + 终端 caret 报告
moon coverage report -f summary             # 汇总表（AGENTS.md §7 记录：flag 是 -f 不是 --format）
moon coverage report -f caret               # 终端 caret（未覆盖行）
moon coverage report -f html                # HTML 报告
moon coverage report -f coveralls --send-to codecov   # CI 可选上报（AGENTS.md §7 记载）
moon coverage clean                         # 清理 bisect.coverage 等产物
```
- 官方 scaffold 的推荐用法是 `moon coverage analyze > uncovered.log`（AGENTS.md §7）。

**CI 门禁完整顺序（`.github/workflows/ci.yml`，单个 job `roundtrip`，`ubuntu-latest`）：**
| # | 门禁 | 命令 | 是否阻塞 |
|---|---|---|---|
| 0 | 工具链 pin | `MOONBIT_VERSION=0.10.11+6ff76a5f9` / `PYTHON_VERSION=3.14` / `NUMPY_VERSION=2.3.4` | — |
| 0 | registry index 刷新 | `moon update`（冷 runner 必需；不触碰 pin 定的工具链） | 是 |
| 0 | 版本可追溯 | `moon version` / `moonc -v` / `python --version` / `numpy.__version__` 打印进日志 | — |
| 1/3 | **fmt** | `moon fmt` + `git diff --exit-code` | 是 |
| 2/3 | **check** | `moon check --target native` | 是 |
| 3/3 | **test** | `moon test --target native` | 是 |
| 4 | **coverage 阈值** | `moon test --enable-coverage` → `moon coverage analyze` → `report -f summary` → `awk` 双阈值 | 是（awk 非零即失败） |
| 5 | **fixture 无漂移** | `python interoperability/generate_fixtures.py --check`（重算 sha256 比对 `expected.json` + `npz_expected.json`） | 是 |
| 6 | **跨语言 round-trip** | `python interoperability/roundtrip.py -v`（31 fixture：`emit` → `verify`，`np.array_equal` + 逐字节） | 是 |
| 7 | **CLI 冒烟 + 退出码** | `moon run cmd/main --target native -- {inspect,validate,dump}` + `test "$invalid" -eq 1` / `"$missing" -eq 2` / `"$bad_limit" -eq 2` | 是 |
- 触发：`push` / `pull_request` 到 `main`，加 `workflow_dispatch`；`concurrency` 按 ref 取消在跑任务。
- **§19 铁律**：README 展示的例子必须是 CI 中实际运行的例子（Demo 进 CI）。
- 本地等价三步（AGENTS.md §8）：`moon fmt` → `moon check --target native` → `moon test --target native`。
- CI 环境细节（安装脚本、`$GITHUB_PATH`、job 拓扑）属部署文档范畴，此处只记录**门禁本身**。

## Test Types

**Unit Tests:**
- 范围：单包公共 API，与 `src/<pkg>` 一一对应。无 mock，输入全是内存字节或磁盘 Oracle 文件。
- 文件映射与规模（实测）：
  | 文件 | 测试数 | 目标层 |
  |---|---|---|
  | `tests/npy_test.mbt` | 15 | `format`（magic / version / prefix 偏移 / 手工 LE 装配）+ `header`（受限 Python literal 解析） |
  | `tests/dtype_test.mbt` | 16 | `dtype`（descr 全矩阵、`itemsize`/`name`/`descr_code` 表、complex codec 与精度） |
  | `tests/reader_test.mbt` | 25 | `reader`（validate/decode、13 个类型化 accessor、S4 chunk 窗口语义） |
  | `tests/writer_test.mbt` | 4 | `writer`（31→26 fixture 字节级 round-trip + descr/padding 白盒点测） |
  | `tests/npz_test.mbt` | 28 | `npz`（容器解析 + 7 类拒绝） |
  | `tests/cli_test.mbt` | 34 | `cli`（`parse_args` / 三种命令 / 渲染格式 / 退出码映射） |
  | `tests/adapter_test.mbt` | 10 | `adapter/moonnum`（shape/strides/order 保真 + 3 种拒绝 + 错误消息） |
  | `tests/edge_test.mbt` | 17 | 跨层边界与防御分支（**合成** blob，非 Oracle） |
  | `tests/security_test.mbt` | 3 | 安全边界属性 |
  | `tests/fuzz_test.mbt` | 3 | §18 totality 模糊测试 |
  | `tests/property_test.mbt` | 1 | round-trip 属性 |
  | **合计** | **156** | |
- 速度：156 个测试在单个 native 编译单元内跑完（实测一次 `moon test --target native` 全程无失败）。

**Integration Tests:**
- **读向集成**：`tests/reader_test.mbt` 的真实数据流贯穿 `format` → `header` → `dtype` → `reader` 四层：
  `load_fixture` → `@reader.decode` → 类型化 accessor，并与 `expected.json` 的 `flat_values` 逐元素比对。
  特别覆盖 fortran_order 的语义：「fortran_order is metadata for the consumer; the flat accessor still returns
  storage order, matching the Oracle's flat_values (column-major bytes)」。
- **写向集成（M3 里程碑门禁）**：`tests/writer_test.mbt::writer_roundtrip_byte_exact_all_fixtures`
  对每个 fixture 做 `decode → encode`，断言**字节完全相同**（含长度、首个差异偏移定位）。
  注释说明这**传递性地证明了** header dict 文本形、descr 重建、shape tuple 拼写、version 字段宽度、
  最小 64 字节填充与 payload 原样拷贝。
- **属性式**：`tests/property_test.mbt::decode_encode_roundtrip_is_byte_exact` 覆盖全部 31 个 Oracle，
  断言 `encode(decode(f)) == f` 且 `decode(encode(decode(f)))` 的 dtype / shape / element_count 一致。
- **模糊式**：`tests/fuzz_test.mbt` 三种输入分布（各 2000 / 2000 / 3000 轮，固定种子）：
  1. 纯随机字节（0..128 字节）——打 magic 与截断守卫
  2. 合法 v1 prefix + 0..64 随机 body 字节——猛击 header lexer/parser
  3. Oracle fixture 变异（4 种变异模式：翻字节 / 截断 / 追加随机尾巴 / 只翻 12 字节 prefix 内的字节）
  单条不变量是 §18 **totality**：对任意 `Bytes`，`decode` 与 `validate` 必须返回 `Ok` 或结构化 `Err(NpyError)`，
  绝不 crash / hang / 越界 / 失控分配。附加两条结构保证：`decode` 与 `validate` **必须一致**；
  Ok 路径上 dtype 匹配的 accessor 返回的元素数必须等于 `element_count`。
  注释点明：「A trap (abort) anywhere aborts the whole `moon test` run, so a GREEN fuzz run is itself
  the no-crash proof.」
- **容器集成**：`tests/npz_test.mbt` 用手工 ZIP 装配器 + 逐字段 patch，覆盖 EOCD 尾匹配、CD 遍历、
  local header 的 name/extra 决定 data_start、以及 7 类拒绝（压缩成员、zip64、路径穿越名、重复名、
  加密成员、畸形容器、成员缺失）。

**E2E Tests:**
- **端到端 CLI 测试只存在于 CI**，不在 `moon test` 内——因为退出码必须由真实进程产生。
  位置：`.github/workflows/ci.yml` 末尾 "CLI inspect / validate / dump + exit codes" 步骤。
  ```bash
  # 成功路径（退出 0）+ 输出内容断言
  moon run cmd/main --target native -- inspect  tests/fixtures/f4_2x3_c_le_v1.npy
  moon run cmd/main --target native -- validate tests/fixtures/f4_2x3_c_le_v1.npy
  moon run cmd/main --target native -- dump tests/fixtures/f4_2x3_c_le_v1.npy --limit 2 | grep -F "(showing 2 of 6 elements)"
  moon run cmd/main --target native -- dump tests/fixtures/c8_4_c_le_v1.npy | grep -F "(1, 2)"
  # 三层退出码，两个非零码必须互异
  set +e
  moon run cmd/main --target native -- validate README.md              # 可读非 NPY → 1 (InvalidMagic)
  invalid=$?
  moon run cmd/main --target native -- validate does_not_exist.npy      # 不存在     → 2
  missing=$?
  moon run cmd/main --target native -- dump tests/fixtures/f4_2x3_c_le_v1.npy --limit x   # 坏用法 → 2
  bad_limit=$?
  set -e
  test "$invalid" -eq 1; test "$missing" -eq 2; test "$bad_limit" -eq 2
  ```
  注释解释了为何用 `grep -F` 而非正则：「they pin measured output, not an assumed format: Float to_string
  drops a trailing ".0", so the complex pair prints as "(1, 2)" and the element rows as "[0] 0"」。
- **跨语言 E2E**：`python interoperability/roundtrip.py -v` 驱动 `expected.json` 的 fixture 清单，
  逐 fixture 跑 `emit`（`moon run examples/roundtrip --target native -- in out`）
  + `verify`（`verify_moonbit_output.py out --reference in --byte-exact in`，
  让 NumPy `np.load(allow_pickle=False)` 后做 `np.array_equal` **且**与 Oracle 逐字节一致）。
  脚本自行打印 `N/N passed`，任一失败退出 1。这就是 `examples/roundtrip/main.mbt` 覆盖率 0/21 的正当理由。
- **框架**：无 E2E 框架——直接用 `moon run` 子进程 + shell 断言（bash `test` / `grep`）。

**未覆盖范围（实测可证实的缺口）：**
- **`cmd/main/main.mbt`（0/26）与 `examples/roundtrip/main.mbt`（0/21）在 `moon test` 下零覆盖**——
  它们只由 CI 的 CLI 冒烟与 round-trip 步骤覆盖。本地跑 `moon test` 不会发现这两处的回归。
- **CLI 的 native-only 分支未测**：`cmd/main/main.mbt:23-27` 的 `#cfg(not(any(target="native", target="llvm")))`
  降级分支（`abort`）在任何已测 backend 上都不会执行——CI 只跑 native。
- **`examples/bench/` 完全无测试**，属可接受的性能脚手架（不参与 CI）。其数字明确声明为单机微基准口径，
  「NOT cross-library comparisons and must not be quoted as such」。
- **`--full` fixture 矩阵（数百文件）默认不入库**，故 §15 完整兼容矩阵**未被 CI 穷举**；
  入库只覆盖 31 个代表性组合（shape 维度只到 `(2,3)` / `(2,2,2)` / 0-d；`(10,)`、`(2,3,4)`、`(1,1,1,1)` 仅在 `--full` 中）。
- **无多字节 UTF-8 成员名 / 非 ASCII 路径的 NPZ 用例**：`npz_test.mbt` 覆盖拒绝面，但未覆盖合法非 ASCII key。
- **无 writer 的"从类型化数组构造"入口**：`encode` 只接受来自 `reader.decode` 的 `NpyArray`
  （`src/writer/writer.mbt:6-17` 明确 Scope 限制），因此"从零构造 NPY"这条路径不存在也无测试。
- **fixture 清单双份不同步**（见 Fixtures and Factories）：`writer_test.mbt::fixture_names()` 仍是 26 项快照，
  5 个 complex fixture 的 writer 侧字节级覆盖**只通过** `property_test.mbt` 的 31 项循环获得，
  不通过 writer 自己的 26 项循环。这是真实存在的覆盖不均。
- **无覆盖率 exclusions 契约**：新增源文件若落入不覆盖区间不会被门禁发现（阈值只约束聚合与 core parser 文件名正则）。

## Common Patterns

**Async Testing:**
- **不适用——本仓库没有 async 代码**。核心层全同步；`@fs` 是同步 `raise IOError`。
- 唯一的"异步式"模式是 **`raise` → `Result` 桥接后 `unwrap()`**，在测试 helper 里固定出现：
  ```moonbit
  fn load_fixture(name : String) -> Bytes {
    let path = "tests/fixtures/\{name}"
    let res = try @fs.read_file_to_bytes(path) |> Ok catch { e => Err(e) }
    res.unwrap()
  }
  ```
  注释说明了为什么可以放心 `unwrap`：「Aborts (failing the test) if the Oracle file is missing or unreadable,
  so a broken fixture path can never silently pass.」
- 桥接写法是 AGENTS.md §2 规定的**唯一**形式（`try?` 已弃用，Warning 0020）。

**Error Testing:**
- **标准形（具体枚举分支，不泛化）**：
  ```moonbit
  test "reject_invalid_magic" {
    let bad = Bytes::from_array([
      b'N', b'O', b'T', b'N', b'P', b'Y', b'\x01', b'\x00',
    ])
    match @format.parse_prefix(bad) {
      Err(@error.InvalidMagic) => ()
      _ => assert_true(false)
    }
  }
  ```
- **带 payload 的错误同时断言 payload**：
  ```moonbit
  match @reader.decode(blob) {
    Err(@error.DataLengthMismatch(24L, 0L)) => ()
    _ => assert_true(false)
  }
  ```
  ```moonbit
  Err(@error.InvalidChunkRange(s, l)) => {
    assert_eq(s, pair.0)
    assert_eq(l, pair.1)
  }
  ```
- **错误类别矩阵常见**：一个 `test` 用 `for … in [...]` 覆盖一整类输入：
  ```moonbit
  test "parse_dtype_reject_unsupported" {
    for descr in ["<c4", "<c2", "<C16", "<S3", "<U4", "<V8", "<M8", "<m4", "<g16", "|a1", "<e2", "<f2", "<i3", "<u5"] {
      match @dtype.parse_dtype(descr) {
        Err(@error.UnsupportedDType(_)) => ()
        _ => assert_true(false)
      }
    }
  }
  ```
- **跨层错误传播**：构造能触发**深层**错误的输入，断言**顶层**返回同一变体：
  `edge_validate_propagates_header_error` 用 `@reader.validate(v1_with_body("{!"))` 断言 `InvalidHeaderSyntax`；
  `edge_validate_propagates_object_array` 断言 `parse_dtype` 的拒绝穿过 `validate`。
- **溢出 / 边界用合成 header 数字驱动**（这是唯一能覆盖这些分支的方式）：
  | 用例 | 断言 | 触发点 |
  |---|---|---|
  | `(10000000000, 10000000000)` | `ShapeOverflow` | UInt64 逐步乘积回绕守卫 |
  | `(4000000000, 4000000000)` | `ShapeOverflow` | 乘积超 Int64 后置边界 |
  | `<f8 (2000000000000000000,)` | `ShapeOverflow` | `element_count × itemsize` 前置守卫 |
  | `header_len = 0xFFFF` 但文件短 | `TruncatedHeader`（**不是** `InvalidHeaderLength`） | 不分配所声称的缓冲 |
- **退出码断言**（`tests/cli_test.mbt`，纯逻辑层）：
  ```moonbit
  test "exit_code_to_int" {
    assert_eq(@cli.Success.to_int(), 0)
    assert_eq(@cli.Invalid.to_int(), 1)
    assert_eq(@cli.Operational.to_int(), 2)
  }
  ```
  真实进程级退出码在 CI E2E 里断言（见 Test Types）。

**Snapshot Testing:**
- **完全未使用**。项目内 `.mbt` 文件中没有任何 `inspect(v, content=…)` / `debug_inspect(…)` 调用
  （全文搜索只命中 `.mooncakes/` 下 vendored 第三方测试）；无 `moon test --update` 流程，
  无 `__snapshots__/` 目录。
- **替代方案是更强的 golden file**：`tests/fixtures/expected.json` / `npz_expected.json`。
  它比常规快照强两点：
  1. **真理来源在外部**——由 `interoperability/generate_fixtures.py` 用 NumPy 2.3.4 的**真实产物字节**
     反推得出（`ast.literal_eval` 解析 header、`np.frombuffer` 取元素），不是"当前实现输出即正确"的自我确认；
  2. **可独立校验**——`generate_fixtures.py --check` 重算每个 `.npy` / `.npz` 的 sha256 与清单比对，
     CI 用它做 drift 门禁。
  这条「Oracle = NumPy 真实行为，不手写不臆测」原则写在 `interoperability/README.md` 与
  `docs/spec/acceptance.md` §21，是本仓库测试策略的核心。

---

*Testing analysis: 2026-09-11*
*Update when test patterns change*
