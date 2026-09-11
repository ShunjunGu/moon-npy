# Architecture

**Analysis Date:** 2026-09-11

## Pattern Overview

**Overall:** 分层库 + 字节级解析/序列化管线（Layered Library with Parse/Serialize Pipeline），外挂一个极薄的可执行壳。

`moon-npy` 是一个 **Pure MoonBit 的 NPY 二进制数组格式读写库**——它是 Python / NumPy / ML 数据生态与 MoonBit 数值生态之间的**格式互操作层**，不是 NumPy 的重新实现。核心层形态统一为「`Bytes` 进 → 结构出」的纯函数，没有任何文件系统 / CLI 依赖。

**Key Characteristics:**

- **分层严格单向**：依赖方向由各包 `moon.pkg` 的 `import` 唯一确定，无环、无回边。`error` 是唯一叶子包。
- **核心层纯函数、无 IO**：`src/{format,header,dtype,reader,writer,npz,cli}` 全部只处理内存中的 `Bytes` 与结构体；`@fs` / `@env` 只出现在 `cmd/main/`、`examples/*`、`tests/`。
- **失败通道唯一且显式**：全库用 `Result[T, NpyError]` 表达失败，绝不用 `Bool` 或裸 `String`。`NpyError` 是一个普通 `pub(all) enum`（19 个构造子）。
- **Oracle 驱动**：正确性以 pinned NumPy `2.3.4` 的**真实产物字节**为唯一真相源，`decode → encode` 对全部 31 个 fixture **逐字节恒等**。
- **Totality 不变式**：任意 `Bytes` 输入恒返 `Ok` 或结构化 `Err`，绝不 crash / hang / 越界 / 失控分配（确定性 fuzz，7000 次迭代，固定种子）。
- **`pub struct` 只读字段模式**：核心数据结构是 `pub struct` 而非 `pub(all) struct`，跨包**能读字段、不能构造**——把「只有本包能造出这个值」变成类型系统保证。
- **无 FFI、无 Python 运行时、无 inflate 实现**：安全性 by construction —— 危险面（pickle 执行、解压炸弹）在库里根本不存在，而非被过滤。

## Layers

**L1 错误模型层 — `src/error/`：**
- Purpose: 定义全库唯一的失败通道类型
- Contains: `pub(all) enum NpyError`，19 个构造子（13 个 NPY 层 + 6 个 NPZ 容器层），`derive(Debug)`
- Depends on: 无（叶子包，`import { }` 为空 —— `src/error/moon.pkg` 只有一行注释）
- Used by: 其余全部包（每个包的 `moon.pkg` 都 import `ShunjunGu/moon-npy/src/error`）

**L2 字节原语层 — `src/format/` 与 `src/dtype/`（两个平级包）：**

`src/format/`：
- Purpose: NPY 固定前缀的字节布局——magic、version、header-length 字段
- Contains: `NpyVersion`（`V1_0`/`V2_0`/`V3_0`）、`NpyPrefix`（`version`/`major`/`minor`/`header_len`/`header_start`/`data_offset`）、`parse_prefix`、`has_magic`、`version_of`、`read_u16_le`、`read_u32_le`、常量 `magic_len`
- Depends on: `src/error/`
- Used by: `src/header/`、`src/reader/`、`src/writer/`、`src/npz/`、`src/cli/`、`tests/`

`src/dtype/`：
- Purpose: 元素类型（descr）的解析、尺寸、以及逐元素字节解码
- Contains: `DType`（13 变体）、`ByteOrder`（4 变体）、`Complex`、`parse_dtype`、`itemsize`、`name`、`descr_code`、`endian_char`、13 个 `read_*` codec（`read_bool` / `read_i8` … `read_f64` / `read_c64` / `read_c16`）；私有 `is_big`、`parse_byte_order`、`kind_size_to_dtype`、`sext`、`read_uint`、`read_bits32`
- Depends on: `src/error/` —— **注意：`dtype` 不依赖 `format` 也不依赖 `header`**，是 L2 的独立同级
- Used by: `src/reader/`、`src/writer/`、`src/cli/`、`src/adapter/moonnum/`、`tests/`

**L3 头字典解析层 — `src/header/`：**
- Purpose: 把 header 正文这段**受限 Python literal** 词法分析 + 递归下降解析成 `NpyHeader`
- Contains: `pub fn parse_header(Bytes)`、`pub struct NpyHeader { descr, shape, fortran_order }`；私有 `priv enum Token`、`lex`、`parse_tokens`、`peek`、`decode_span`、ASCII 分类器（`is_space`/`is_digit`/`is_ident_start`/`is_ident_char`）
- Depends on: `src/error/`、`src/format/`、`moonbitlang/core/encoding/utf8`（见 `src/header/moon.pkg`）
- Used by: `src/reader/`、`src/writer/`、`src/cli/`、`tests/`

**L4 校验 / 解码层 — `src/reader/`：**
- Purpose: 把原始 NPY 字节校验成 `NpyMeta`，或解码成 `NpyArray` 并提供类型化访问器
- Contains: `pub struct NpyMeta`、`pub struct NpyArray`、`validate`、`decode`、13 个 `NpyArray::to_*` accessor、2 个 chunk accessor（`to_f32_chunk` / `to_f64_chunk`）；私有 `flat`、`flat_range`、`slice_payload`、`shape_element_count`
- Depends on: `src/error/`、`src/format/`、`src/header/`、`src/dtype/`（全部四个上游，是本仓依赖最深的包）
- Used by: `src/writer/`、`src/npz/`、`src/cli/`、`src/adapter/moonnum/`、`tests/`

**L5 序列化 / 容器 / 表现层 — `src/writer/`、`src/npz/`、`src/cli/`（三个平级包）：**

`src/writer/`：
- Purpose: 把校验过的 `NpyArray` 重新序列化成与 `np.save` 逐字节一致的 NPY 字节
- Contains: `pub fn encode(@reader.NpyArray) -> Result[Bytes, NpyError]`；私有 `py_bool`、`shape_tuple`、`version_major_minor`、常量 `array_align = 64`
- Depends on: `src/error/`、`src/format/`、`src/header/`、`src/dtype/`、`src/reader/`、`moonbitlang/core/encoding/utf8`
- Used by: `tests/`、`examples/roundtrip/`

`src/npz/`：
- Purpose: 只读、未压缩的 `np.savez` ZIP 容器读取；成员 payload 原样透传给既有 NPY decode 路径
- Contains: `pub fn decode_npz(Bytes)`、`pub struct NpzArchive { members }`、`pub(all) struct NpzMember { name, array }`、`NpzArchive::get`、`NpzArchive::names`；私有 `find_eocd`、`match_sig`、`slice_bytes`、`resolve_member_name`、`unsafe_member_name`、3 个 ZIP 签名常量
- Depends on: `src/error/`、`src/format/`（复用 `read_u16_le` / `read_u32_le`）、`src/reader/`、`moonbitlang/core/encoding/utf8`
- Used by: `tests/`

`src/cli/`：
- Purpose: 纯参数解析（IO-free）与输出渲染——`inspect` / `validate` / `dump` 三个子命令的全部决策逻辑
- Contains: `pub(all) enum Subcommand`、`pub(all) enum ExitCode`、`pub struct CliOutcome`、`parse_args`、`run_inspect`、`run_validate`、`run_dump`、`render_error`、`human_size`、`operational`、`ExitCode::to_int`；私有 `render_inspect` / `render_dump` / `render_failure` / `row` / `table_rule` / `join_lines` / `group_digits` / `dump_values` / `render_all` / `version_label` / `byte_order_label` / `shape_label` / `parse_limit` / `is_digits` / `usage`、常量 `label_width = 14` / `default_dump_limit = 10`
- Depends on: `src/error/`、`src/format/`、`src/header/`、`src/dtype/`、`src/reader/`、`moonbitlang/core/string`
- Used by: `cmd/main/`、`tests/`

**L6 边界 / 集成层 — `src/adapter/moonnum/`、`cmd/main/`、`examples/*`：**

`src/adapter/moonnum/`：
- Purpose: 读方向适配器——把 moon-npy 已解析的 `NpyArray` 交给 `amor2025/moonNum` 的 `NdArray`（f32/f64、小端、零元素解码）
- Contains: `pub(all) enum AdapterError`、`AdapterError::message`、`to_moonnum_f32`、`to_moonnum_f64`；私有 `convert`、`shape_as_ints`、常量 `int_max_as_uint`
- Depends on: `src/dtype/`、`src/reader/`、`amor2025/moonNum/src/core`、`amor2025/moonNum/src/dtypes` —— **全仓唯一引入第三方代码的包**
- Used by: `tests/`

`cmd/main/`：
- Purpose: CLI 可执行薄壳；只拥有 `cmd/main` 允许拥有的两个副作用——读文件字节、设进程退出码
- Contains: `pub fn main`（实为包内 `fn main`）、`resolve`、两个 `#cfg` 版本的 `exit_with`（native/llvm 下是 `extern "c" fn exit_with(code : Int) = "exit"`，其它目标降级为 `abort`）
- Depends on: `src/cli/`、`moonbitlang/x/fs`、`moonbitlang/core/env`（见 `cmd/main/moon.pkg`，`pkgtype(kind: "executable")`）
- Used by: 无（`pkg.generated.mbti` 为空导出）

`examples/roundtrip/` 与 `examples/bench/`：
- Purpose: M4 的 emit harness（decode → encode → 写盘，供 NumPy 侧校验）与可复现性能基准（四条读取路径）
- Depends on: `src/reader/`、`src/writer/`（roundtrip）、`src/reader/` + `core/bench` + `core/json` + `moonbitlang/x/fs`（bench）

**跨层规范文档：**
- `AGENTS.md` — M0 实测固化的工具链事实与语法约定的**权威**（文件级 `import` 非法、`try?` 已弃用、`Int` 是 32 位、`Bytes::make` 位置参数等）
- `docs/spec/acceptance.md` — 仓库内**唯一 spec owner**，所有 `§N` / `附录 A` 引用在克隆内解析到它

## Data Flow

### 读路径（`.npy` bytes → in-memory array）

1. **入口**：`cmd/main/main.mbt::resolve` 调 `@fs.read_file_to_bytes(path)` 拿到 `Bytes`（测试则由 `tests/npy_test.mbt::load_fixture` 直接读盘）
2. **分派**：`resolve` 按 `Subcommand` 调 `@cli.run_inspect` / `run_validate` / `run_dump`
3. **校验**：三者最终都走 `@reader.validate(data)`（`src/reader/reader.mbt`），依次：
   a. `@format.parse_prefix(data)`（`src/format/format.mbt`）— `has_magic` 检查 6 字节 `\x93NUMPY`；`version_of(major, minor)` 解析 1.0/2.0/3.0；按 `major` 决定 `header_start`（v1 = 10，v2/v3 = 12），从偏移 8 起**手工拼装** `read_u16_le` / `read_u32_le` 得到 `header_len`；`data_offset = header_start + header_len` → `NpyPrefix`
   b. `@header.parse_header(data)`（`src/header/parser.mbt`）— 内部**再次**调 `@format.parse_prefix`（不假设 64 字节对齐，只信 `header_len`），然后 `lex(data, start, end)`（`src/header/lexer.mbt`）直接在 `Bytes` 上逐字节扫描出 `Array[Token]`，再由 `parse_tokens` 递归下降归约为 `NpyHeader { descr, shape, fortran_order }`；三键缺失分别报 `MissingHeaderField`
   c. `@dtype.parse_dtype(header.descr)`（`src/dtype/dtype.mbt`）→ `(DType, ByteOrder)`；首字符经 `parse_byte_order`（`src/dtype/endian.mbt`）解析 `< > | =`；`|O`（object array）在**任何 payload 字节被解释之前**就以 `UnsupportedObjectArray` 拒绝
   d. `shape_element_count(header.shape)` 用 `UInt64` 逐步防回绕乘积并校验装得进 `Int64`
   e. **载荷对账**：`element_count * itemsize` 必须等于 `data.length() - data_offset`
   f. 全部通过 → `NpyMeta`
4. **解码**：`@reader.decode(data)` 在 `validate` 之上执行 `slice_payload(data, data_offset, payload_len)`，拷出一份新 `Bytes`（`Bytes` 不可变且没有返回 `Bytes` 的零拷贝子切片）并装成 `NpyArray`
5. **惰性元素解码**：`NpyArray::to_f32()` 等 13 个 accessor → 泛型 `flat` → `flat_range` → 逐元素调用 `@dtype.read_*`（`src/dtype/codec.mbt`），每个元素都按 `ByteOrder` **手工按字节拼装**
6. **窗口读取（S4）**：`to_f32_chunk(start, len)` / `to_f64_chunk(start, len)` 走同一条 `flat_range`，只把 `[start, start+len)` 内的元素物化；越界 / 负值报 `InvalidChunkRange(start, len)`，绝不 panic

### 写路径（in-memory array → `.npy` bytes）

1. **入口**：`@writer.encode(array : @reader.NpyArray)`（`src/writer/writer.mbt`）
2. **重建 descr**：`@dtype.endian_char(array.byte_order)` + `@dtype.descr_code(array.dtype)` —— Writer 只产出 `<` / `>` / `|`，`Native`（`=`）归一成 `<`，永不产出 `=`
3. **重建 header 字典**：按 NumPy 的**精确文本形式**拼接 `{'descr': '<f4', 'fortran_order': False, 'shape': (2, 3), }` —— `py_bool` 写 Python 大小写 `True`/`False`，`shape_tuple` 复刻 `()` / `(4,)` / `(2, 3)` 三种拼写，键序恒为 descr → fortran_order → shape
4. **最小对齐填充**：`@utf8.encode(dict)` 得 ASCII 字节；按 preamble（v1 = 10，v2/v3 = 12）重算 `pad = (64 - (preamble + dict_len + 1) % 64) % 64`，`header_len = dict_len + pad + 1`；无论源文件带了多少多余填充，都重算成 NumPy 的最小 64 字节对齐
5. **逐字节发射**：magic 6 字节 → major/minor → header-length 字段（v1 手工拼 uint16 LE，v2/v3 手工拼 uint32 LE）→ dict 字节 → `pad` 个空格（0x20）→ `\n`（0x0a）→ **payload 逐字节原样拷贝**（`array.data` 已是文件字节序，无需逐元素重编码）
6. `Ok(Bytes::from_array(out))`
7. **落盘验证**：`examples/roundtrip/main.mbt` 用 `@fs.write_bytes_to_file` 写出，交给 `interoperability/verify_moonbit_output.py` 让 NumPy `np.load` + `array_equal` + 逐字节比对

**关键性质**：`encode(decode(f)) == f` 对全部 31 个 Oracle fixture **逐字节成立**，由 `tests/property_test.mbt` 在 `moon test` 内钉住（Python-free），并由 `interoperability/roundtrip.py` 在 CI 里跨语言复验。

### NPZ 容器读取路径（`.npz` zip → members）

1. **入口**：`@npz.decode_npz(data)`（`src/npz/npz.mbt`）
2. **定位 EOCD**：`find_eocd(data)` 从尾部向前最多 `22 + 65535` 字节倒扫，找签名 `PK\x05\x06`，且要求 EOCD 声明的 `comment_len` **恰好**触到文件末尾（排除尾部注释里的伪签名）
3. **zip64 哨兵检查**：EOCD `+4/+6/+8/+10` 的 uint16 是否为 `0xFFFF`，`+12`（`cd_size`）/`+16`（`cd_offset`）的 uint32 是否为 `0xFFFFFFFF` → 任一命中即 `NpzZip64Unsupported`（此检查先于任何偏移运算）
4. **中央目录定位**：`cd_offset + cd_size > eocd`（`Int64` 比较）→ `NpzBadStructure("central directory out of range")`
5. **逐条读中央目录记录**：按 `total_entries` 循环，每条 = `PK\x01\x02` + 46 固定字节 + name + extra + comment；`name_len` / `extra_len` / `comment_len` 与签名不符即 `NpzBadStructure`
6. **成员名规整**：`resolve_member_name` 做 UTF-8 解码（失败即 `NpzBadStructure`，不做 `decode_lossy`）并剥掉 `.npy` 后缀作为 archive key
7. **安全拒绝（次序固定）**：`comp_method != 0` → `NpzCompressedMember`（压缩优先，deflate 成员没有任何可安全推理之处）→ `unsafe_member_name` → `NpzUnsafeMemberName` → 与已见名重复 → `NpzDuplicateMember` → `gp_flags & 0x0001`（加密位）→ `NpzBadStructure`
8. **成员载荷定位**：数据**起点**取自**本地头**（`local_offset + 30 + lname_len + lextra_len`），数据**长度**取自**中央目录** `comp_size` —— 流式写入的本地头 crc/size 字段是 `0xFFFFFFFF` 占位符，**永不信任**
9. **成员解码**：`slice_bytes` 切出成员字节 → `@reader.decode(payload)` —— 复用单文件 reader 的全部校验（含 object dtype 拒绝），**NPY 层错误原样透传**
10. → `NpzArchive { members }`（成员序 = 中央目录序），通过 `NpzArchive::get(key)` / `names()` 访问；`get` 未命中是唯一的 `NpzMemberNotFound` 生产者

### S6 适配路径（`NpyArray` → moonNum `NdArray`）

1. **入口**：`to_moonnum_f32` / `to_moonnum_f64`（`src/adapter/moonnum/adapter.mbt`）→ 共享 `convert`
2. **dtype 门（在字节序门之前）**：`arr.dtype != want` → `UnsupportedDType(arr.header.descr)`（两个入口各自声明自己的 dtype 前置条件）
3. **字节序门**：`Big` → `BigEndianNotSupported(descr)` —— moonNum 的 `NdArray::is_little_endian()` 实现是字面量 `true`，原样递 big-endian payload 会**静默读出字节序倒置的错值**而不是报错
4. **shape 映射**：`shape_as_ints` 逐维检查是否装得进 32 位 `Int` → 超界即 `ShapeDimensionTooLarge(dim)`，**拒绝而不截断**；0-d 空 shape 原样映射（moonNum 的 `[]` 即 0-D，语义一致）
5. **storage order 映射**：`header.fortran_order` → `@core.Order::F` / `@core.Order::C`
6. **载荷移交**：`@core.NdArray::from_buffer(arr.data.to_array(), nn_dtype, shape, order)` —— `Bytes::to_array()` 是**整条管线上唯一一次元素级拷贝**；`from_buffer` 自身共享缓冲区、只计算字节步长，不做逐元素解码

### CLI 执行流

1. `moon run cmd/main --target native -- <inspect|validate|dump> <file.npy> [--limit N]`
2. `cmd/main/main.mbt::main` → `resolve(@env.args())`；`argv[0]` 是 exe 路径，所以子命令是 `argv[1]`、路径是 `argv[2]`
3. `@cli.parse_args(argv)`（纯函数，可被测试直接驱动，不碰 `@env`）→ `Result[(Subcommand, String), String]`；缺参 / 未知子命令 / 多余尾参 / 非法 `--limit` 一律 `Err(usage)` → `Operational`
4. `@fs.path_exists(path)` 为假 → `@cli.operational("...no such file")`（退出 2），把「打不开」与「文件非法」彻底分开
5. `@fs.read_file_to_bytes(path)` 用 `try ... |> Ok catch { e => Err(e) }` 桥成 `Result`；读失败同样 → `Operational`
6. 分派 `@cli.run_inspect` / `run_validate` / `run_dump`，各返回 `CliOutcome { output, code }`
7. `println(outcome.output)`（`output` 不含尾换行，由 `println` 补）→ `exit_with(outcome.code.to_int())`

**State Management:**
- **完全无状态**：全库是纯函数 `Bytes → 结构` / 结构 → `Bytes`，不持有任何可变全局状态。仅有的模块级绑定都是 `let` 常量（`magic_len`、`array_align`、`label_width`、`default_dump_limit`、`int64_max`、`uint64_max`、`int_max_as_uint`、三个 ZIP 签名数组）
- **单文件、全内存**：一次性读入整个 `Bytes` 后解析；没有跨文件 I/O 的 streaming（`README.md` Limitations 明确记录）
- **值语义传递**：`NpyArray` / `NpyMeta` / `NpyHeader` 都是值类型，靠 `pub struct` 的「可读不可构造」约束保证有效性
- **唯一持久副作用**在 `cmd/main` 与 `examples/*`：读文件、写文件、设退出码

## Key Abstractions

**`NpyError`（结构化失败通道）：**
- Purpose: 全库唯一的失败表达方式；核心层决策为普通 `enum` + 内建 `Result`，不用异常、不用 `Bool`、不用裸 `String`
- Examples: 无 payload 变体 `InvalidMagic` / `TruncatedHeader` / `InvalidHeaderLength` / `InvalidHeaderSyntax` / `ShapeOverflow` / `UnsupportedObjectArray` / `NpzZip64Unsupported`；带 payload 变体 `UnsupportedVersion(Int, Int)` / `MissingHeaderField(String)` / `InvalidDType(String)` / `UnsupportedDType(String)` / `DataLengthMismatch(Int64, Int64)` / `InvalidByteOrder(Byte)` / `InvalidChunkRange(Int, Int)` 与 6 个 NPZ 变体
- Pattern: 结构化错误枚举 + `Result` 单子式传播（不是异常、不是错误码）；`derive(Debug)` 而无 `Eq`
- Location: `src/error/error.mbt`

**`DType` / `ByteOrder` / `Complex`（元素类型三件套）：**
- Purpose: `DType` 是 NumPy 元素类型的封闭枚举（13 变体：`Bool` / `Int8`–`Int64` / `UInt8`–`UInt64` / `Float32` / `Float64` / `Complex64` / `Complex128`）；`ByteOrder` 对应 descr 首字符（`Little`=`<`、`Big`=`>`、`NotApplicable`=`|`、`Native`=`=`）；`Complex { re : Double, im : Double }` 用**单一结构**同时服务 c8 与 c16
- Examples: `DType::Complex64` / `Complex128` 只标宽度，元素值一律是 `Complex`（f32 分量无损加宽进 `Double`）；`is_known_unsupported_kind` 把 `C S a U V M m g G e l L p P` 识别为「合法但不支持」→ `UnsupportedDType`，与「畸形 descr」→ `InvalidDType` 严格区分
- Pattern: 封闭枚举 + 纯函数映射表（`itemsize` / `name` / `descr_code` 三个 match 各一张）
- Location: `src/dtype/dtype.mbt`、`src/dtype/endian.mbt`、`src/dtype/complex.mbt`

**`NpyHeader`（原样保留的 descr）：**
- Purpose: header 字典的解析结果，只 3 个字段 `descr : String` / `shape : Array[UInt64]` / `fortran_order : Bool`
- Examples: `descr` 保持**逐字节原文**（如 `"<f4"`），dtype 解析结果**不写回 header**，而是并列存在 `NpyArray` 上 —— 这是 `decode → encode` 逐字节恒等的基础，也是「M1 header 不变 + M2 独立 dtype 层」的 Q1 布局决策
- Pattern: 「解析但保持原文」的并存式表示（原文用于字节级 round-trip，解析结果用于语义操作）
- Location: `src/header/header.mbt`

**`NpyPrefix` / `NpyMeta` / `NpyArray`（逐层加深的同一个文件视图）：**
- Purpose: 三级递进的表示——`NpyPrefix` 只看固定前缀（magic + version + header-length）；`NpyMeta` = 前缀 + header + dtype + 溢出校验后的 `element_count` + 载荷对账（**无 payload**）；`NpyArray` = 元数据 + 已按 `data_offset` 切好的 payload `Bytes`
- Examples: `validate()` 产出 `NpyMeta`（只校验，不解元素）；`decode()` 产出 `NpyArray`（payload 已就位，元素仍惰性）
- Pattern: 渐进式验证的不可变值对象链；`decode == validate + 一次全量切片` 是 `tests/fuzz_test.mbt` 显式断言的结构契约
- Location: `src/format/format.mbt`、`src/reader/reader.mbt`

**`pub struct` 只读字段模式（核心可见性约定）：**
- Purpose: `NpyHeader` / `NpyPrefix` / `NpyMeta` / `NpyArray` / `NpzArchive` / `CliOutcome` 全部声明为 `pub struct` 而非 `pub(all) struct`——跨包**能读字段、不能构造**
- Examples: `src/reader/reader.mbt` 注释："NpyHeader is a `pub struct` in the header package, so this package can read its fields and store the value parse_header returns, but must not construct it"；`src/cli/cli.mbt` 注释："cmd/main builds an operational outcome via `operational()` below rather than a record literal"
- Pattern: 用可见性梯度把不变式（只有校验过的代码路径能造出这个值）编码进类型系统，而不是靠文档约定
- Location: 各包的 `pkg.generated.mbti` 可见性即为此模式的证据

**`Token`（私有词法单元）：**
- Purpose: header 包内部的词法分析中间表示
- Examples: `priv enum Token { LBrace; RBrace; LParen; RParen; Colon; Comma; Str(String); KwTrue; KwFalse; Num(UInt64); Eof }`
- Pattern: 私有 ADT + 单一公开入口 `parse_header`（包外只能看到 `NpyHeader`）
- Location: `src/header/lexer.mbt`

**`AdapterError`（不侵入核心枚举的转换层错误）：**
- Purpose 表达「字节是合法 NPY，但适配器无法在 moonNum 的模型里表达它」——不是 `.npy` 文件的格式问题
- Examples: `UnsupportedDType(String)` / `BigEndianNotSupported(String)` / `ShapeDimensionTooLarge(UInt64)`
- Pattern: 刻意**不复用** `NpyError`——给 `pub(all) enum` 加变体会立刻打破 `src/cli/cli.mbt::render_error` 的穷尽 match（S4 期已踩过一次，见 `CHANGELOG.md`）；转换层自持错误类型，边界清晰
- Location: `src/adapter/moonnum/adapter.mbt`

**`Subcommand` / `ExitCode` / `CliOutcome`（CLI 三个纯值类型）：**
- Purpose: 把 CLI 的决策面变成可黑盒测试的纯数据
- Examples: `Subcommand::Dump(Int)` 直接携带已解析的 `--limit`，让纯渲染器无需重读 argv；`ExitCode` 的三值 `Success`(0) / `Invalid`(1) / `Operational`(2) 是接口契约——两个非零码必须保持互异
- Pattern: 「解析 → 决策 → 渲染」三段全在库里，`cmd/main` 只做 IO 与退出
- Location: `src/cli/cli.mbt`

## Entry Points

**Library API（无单一入口，按包暴露）：**
- Location: `src/**/*.mbt`；每个包的权威接口清单是其 `pkg.generated.mbti`（`moon info` 生成）
- Triggers: 被下游 MoonBit 模块 `moon add ShunjunGu/moon-npy` 后按包 import（v0.3.0 起已发布到 mooncakes.io）
- Responsibilities: `@format.parse_prefix` / `@header.parse_header` / `@dtype.parse_dtype` / `@reader.validate` / `@reader.decode` / `NpyArray::to_*` / `@writer.encode` / `@npz.decode_npz` / `@cli.*` / `@adapter/moonnum.to_moonnum_*`
- 文档化清单：`README.md` 的 Library API 小节、`docs/spec/acceptance.md`、`docs/s6-api-card.md`

**CLI 可执行：**
- Location: `cmd/main/main.mbt`（`pkgtype(kind: "executable")`）
- Triggers: `moon run cmd/main --target native -- <inspect|validate|dump> <file.npy> [--limit N]`
- Responsibilities: 解析 argv 与退出码副作用、读文件字节、把三方失败分成「打不开」（2）与「文件非法」（1）

**示例程序：**
- `examples/roundtrip/main.mbt` — M4 emit harness：`@fs` 读 → `decode` → `encode` → `@fs` 写，供 NumPy 侧逐字节比对（CI 的 `roundtrip.py` 驱动它）
- `examples/bench/main.mbt` — 四条读取路径的可复现微基准（进程内合成输入，不依赖 fixture）；同时打印人读行与 `[n3-json]` 机器可读行

**测试入口：**
- `tests/` — 11 个 `*_test.mbt`，共 **156** 个 `test` 块；`tests/moon.pkg` 用 `import { ... } for "test"` 声明 test-only 依赖
- `tests/fixtures/` — 31 个 `.npy` + 3 个 `.npz` Oracle fixture + `expected.json` / `npz_expected.json`

**跨语言 driver：**
- `interoperability/roundtrip.py`（emit + verify 聚合，`expected.json` 驱动）与 `interoperability/verify_moonbit_output.py`（单一 Oracle 真相源，`--byte-exact` 走逐字节比对）

**CI 入口：**
- `.github/workflows/ci.yml` — `docs/spec/acceptance.md` §19 pipeline 的落地：fmt / check / test / coverage 门禁 / fixture drift / round-trip / CLI 退出码

## Error Handling

**Strategy:** 核心层**不使用异常表达失败**——所有 core 函数返回 `Result[T, NpyError]`（`AGENTS.md` §2 的 E1 决策）。异常只在 IO 边界出现（`@fs` 抛 `IOError`，它是 `suberror`），且必须在调用处立刻桥成 `Result`。

**Patterns:**

- **具体变体 + 精确断言**：每条 negative 分支返回**具体枚举变体**，测试断言具体变体而非泛化失败（`docs/spec/acceptance.md` §12）。edge / fuzz / security 测试的注释都明确写了 "asserts the exact `NpyError` variant so a branch that fails for the wrong reason cannot pass"。
- **raise → Result 的唯一桥接写法**：`try may_raise(x) |> Ok catch { e => Err(e) }`。`try?` 在本工具链 pin 上已弃用（Warning 0020），`AGENTS.md` §2 明确作废了旧写法。出现处：`cmd/main/main.mbt`、`examples/roundtrip/main.mbt`、`examples/bench/main.mbt`、`src/header/lexer.mbt::decode_span`、`src/cli/cli.mbt::parse_limit`。
- **退出码而非堆栈**：`cmd/main` 把错误映射成 `ExitCode` —— `validate()` 产出的任一 `NpyError` → `Invalid`(1)；文件打不开 / 用法错误 → `Operational`(2)。两个非零码必须保持**互不相同**，便于脚本区分「坏文件」与「坏调用」。
- **穷尽 match 作为错误面单点**：`src/cli/cli.mbt::render_error` 对全部 19 个 `NpyError` 变体做穷尽 match。加变体会立刻编译失败——这是刻意的，`docs/s6-api-card.md` §6 记录 S4 期因此吃过一次教训，S6 的适配器错误因此另立 `AdapterError`。
- **不做「对可描述输入 trap」**：库代码不对能描述的输入 `abort`。`parse_limit` 对溢出 `Int` 的 `--limit` 用 `try ... catch` 包住 `@string.parse_int` 并返回 `None` → 用法错误，而不是让库 trap。`abort()` 只出现在 `examples/*` 与非 native 目标的 `exit_with` 兜底。
- **错误文本不 sanitize**：`render_error` 里 `UnsupportedDType(descr)` / `Npz*Member(name)` / `NpzBadStructure(msg)` 一律原样渲染成员名与 descr，不做转义或截断（与 `UnsupportedDType(descr)` 同一策略）。
- **Totality 保证**：确定性 fuzz（`tests/fuzz_test.mbt`，splitmix PRNG，固定种子，7000 次迭代）断言任意 `Bytes` 恒返 `Ok` 或结构化 `Err(NpyError)`——**绝不** crash / hang / 越界 / 失控分配。同时断言 `decode` 与 `validate` **一致**（`decode == validate + 一次全量切片`），且 Ok 路径上 dtype 匹配的 accessor 返回恰好 `element_count` 个元素。GREEN 的 fuzz 运行本身就是 no-crash 证明（一次 trap 会中止整个 `moon test`）。
- **安全边界在 dtype 层前置**：`|O` / `<O` / `>O` 三种 object descr 形式都在 size 解析**之前**被 `UnsupportedObjectArray` 拒绝，与 shape 和 payload 字节无关（`tests/security_test.mbt` 把这条钉成全端形式一致的性质）。

## Cross-Cutting Concerns

**Logging:**
- 全库**无日志框架**，库层零输出。
- `cmd/main/main.mbt` 用 `println(outcome.output)` 输出命令结果（`output` 不含尾换行，由 `println` 补）。
- `examples/roundtrip/main.mbt` 用 `println` 打一行摘要（`roundtrip OK: <in> -> <out> | N bytes | M elements`）。
- `examples/bench/main.mbt` 打人读行（`[n3] <name> | mean ...`）+ 一行 `[n3-json] {...}` 机器可读 JSON（`Summary` 是不透明类型，字段经其 `ToJson` 表示读回——这是官方设计的公开出口）。

**Validation:**
- 集中在 `src/reader/reader.mbt::validate` 一处，顺序为：magic → version → header 字典语法 → 三键存在性 → descr（含 object 拒绝）→ shape 乘积溢出 → `element_count * itemsize` 与实存字节数对账。
- `decode` **复用** `validate` 而不是复制校验逻辑，两者契约由 fuzz 测试断言一致。
- 解析侧全部使用安全访问：`String::get_char` 越界返 `None`（→ `InvalidDType`）；parser 的 `peek` 越界当 `Eof`（→ `InvalidHeaderSyntax`）；`npz` 的 `match_sig` 自己先做边界检查（`base < 0 || base + sig.length() > data.length()` → `false`）。
- header 字典是**封闭集**：只认 `descr` / `fortran_order` / `shape` 三个键，未知键直接 `InvalidHeaderSyntax`（不忽略），缺失键报 `MissingHeaderField(field)`。

**Byte order / Endianness:**
- `ByteOrder` 4 变体对应 descr 首字符；Reader 接受 `<` `>` `|` `=`，Writer 只产出 `<` `>` `|`。
- `=`（`Native`）与 `|`（`NotApplicable`）**按小端读**——这是对自身运行时的**平台假设**（native / wasm / js / wasm-gc 各后端都是小端），不是对 NPY spec 的主张（源码注释明确区分了这两件事）。
- `is_big(order)` 只对 `Big` 为真；`read_uint` 对 big 走 `acc = (acc << 8) | b`、对 little/na/native 走 `acc | (b << (8 * i))`。
- 所有多字节元素在 `src/dtype/codec.mbt` **手工拼装** —— 本工具链没有跨后端可用的「按字节序读 u16/u32/float」内建（`AGENTS.md` §3），手工拼装是所有后端的安全基线。
- Writer 侧 `endian_char(Native) == "<"`：`=` 被归一成小端，保证产物可复现。
- 适配器把 big-endian **做成硬性前置拒绝**，因为 moonNum 的缓冲模型只有小端（`docs/s6-api-card.md` §3.6）。

**Bounds checking:**
- **边界处一次校验**策略：`validate` 一次性对账 `element_count * itemsize == payload_len`，之后 accessor 沿已校验 payload 以 `i * itemsize` 步进——越界在算术上不可能。`codec.mbt` 的顶部注释把「`off + itemsize <= Bytes::length(data)` 是调用方前置条件，由 decode 一次性保证」写成了显式契约。
- lexer / parser 不用 `unsafe_get`，全部走 `data[i]`（返回 `Byte`，配合显式长度检查）与 `get_char`（返回 Option）。
- `npz` 的每处偏移在收窄成 `Int` 之前，都先在 `Int64` 里证明 `<= 文件长度`。

**Overflow discipline:**
- MoonBit `Int` 是 **32 位有符号、溢出回绕**（`AGENTS.md` §4 实测 `1000000 * 1000000 = -727379968`）。因此字节数 / 元素总数 / shape 乘积 / 偏移**一律用 `Int64` 或 `UInt64`**。
- `shape_element_count` 在 `UInt64` 里逐步检查 `count > uint64_max / dim` 再乘，最后校验装得进 `Int64`；`validate` 再检查 `element_count > int64_max / itemsize` 才乘 `itemsize`。任一步失败即 `ShapeOverflow`，**绝不静默截断**。
- ZIP 的 u32 字段先以 `Int64` 比较、证明安全后才 `.to_int()`（u32 偏移可以超过 `Int` 的正区间）。
- 适配器的 `shape_as_ints` 对 `UInt64` 维度查 `Int` 上界 → `ShapeDimensionTooLarge`，同样是拒绝而非截断。

**Zero-copy vs copy:**
- `Bytes` 在 MoonBit 里**不可变，且没有返回 `Bytes` 的零拷贝子切片**（只有 `BytesView`），所以 payload 必然被拷一次：`reader.slice_payload` 与 `npz.slice_bytes` 各有一份实现。这份**故意的重复**有明确理由——`npz` 包够不到 `reader` 的私有 helper，为共享它引入循环依赖不值得（`src/npz/npz.mbt` 注释写明）。
- header lexer **不把整个 header 转成 `String`**，直接在 `Bytes` 上逐字节扫描 ASCII；只有单个 token 的 span 才经 `@utf8.decode` 物化成 `String`（`decode` 而非 `decode_lossy`——正确性优先）。
- **元素解码是惰性的**：`decode` 只存 payload 切片，`to_*` accessor 才物化元素。
- 适配器里 `Bytes::to_array()` 是**全流程唯一一次元素级拷贝**；moonNum 的 `from_buffer` 自身共享缓冲区、只算字节步长。
- Writer 的 payload 是**逐字节原样拷贝**，不做逐元素重编码——这是它能做到字节级恒等的前提。

**Memory allocation:**
- **单文件、全内存**：整个文件一次读成一个 `Bytes`，没有跨文件 I/O 的 streaming（`README.md` Limitations 明确记录；真正的 mmap / 文件 seek 不在范围内）。
- 切片模式统一：`Array::make(len, b'\x00')` + 逐字节写 + `Bytes::from_array(arr)`。
- Writer 输出走可增长 `Array[Byte]` + `push` + `Bytes::from_array`（`Array` 在本 pin 没有 `create`，定长初始化靠 `Array::make`）。
- `flat_range`（S4）只分配**窗口大小**的输出数组——省的是输出数组而不是 payload，是 **bounded-allocation 而非惰性**（`src/reader/reader.mbt` 与 README Performance 小节都量化说明了这点：逐行 100×`to_f32_chunk(768)` 与全量 `to_f32` 同数量级）。
- 溢出防护同时是**分配防护**：`ShapeOverflow` 在分配之前就挡住了恶意 shape 导致的失控分配。

**`moonbitlang/x` 边界：**
- 库的 `src/**` **完全不碰** `@fs` / `@env`——这让核心库在每个后端都能编译（`docs/spec/acceptance.md` 的 §10.3 意图）。
- `moonbitlang/x/fs` 只出现在 `cmd/main/moon.pkg`、`examples/roundtrip/moon.pkg`、`examples/bench/moon.pkg` 与 `tests/moon.pkg`（后者在 `for "test"` 块里）。
- `moonbitlang/core/*` 子包按包各自 import（`core/env`、`core/string`、`core/encoding/utf8`、`core/quickcheck/splitmix`、`core/bench`、`core/json`），core 是隐式依赖、不必写进 `moon.mod`。
- 模块级第三方依赖只有两个：`moonbitlang/x@0.5.1` 与 `amor2025/moonNum@0.1.0`（见 `moon.mod`）。

**`moonNum` 适配边界：**
- `src/adapter/moonnum/` 是**全仓唯一引入第三方代码**的包。选型经 go/no-go gate（moonNum GO，numbt NO-GO 因需系统 BLAS + 只有 f32 2-D + 校验一律 `panic`），全部实测数据在 `docs/s6-api-card.md`。
- 只做**读方向**（`NpyArray → NdArray`）、只做 **float32 / float64**、只做**小端**；写方向明确推迟。
- 失败用包内自己的 `AdapterError`，**不扩展 `NpyError`**（加变体即打破 `render_error` 的穷尽 match）。
- 不替换 moonNum（它自带 npy 读写）——本仓的差异点是「以 NumPy 2.3.4 产物为 Oracle 的**字节级恒等纪律**」，`docs/s6-api-card.md` §3.7 明确要求文档措辞不得越界。

**`§N` 引用解析：**
- 仓库内所有 `§7.2` / `§13` / `§19` / `附录 A` 形式的引用都指向 `docs/spec/acceptance.md`（in-repo spec owner）。工具链与语法事实的唯一权威是 `AGENTS.md`。`docs/spec/acceptance.md` 的 §0 有一张完整的引用解析索引表。

---

*Architecture analysis: 2026-09-11*
*Update when major patterns change*
