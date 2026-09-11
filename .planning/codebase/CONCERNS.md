# Codebase Concerns

**Analysis Date:** 2026-09-11

> 分析范围：`moon-npy` 仓库本体（commit `c4f5ef8`）。方法为读全文 + 在 `moon 0.1.20260827` /
> native target 上实跑验证（`moon test --target native` → `Total tests: 159, passed: 159`）。
> 文中标 **[实测]** 的结论均已在本机跑出证据；标 **[读码]** 的为纯静态推断，已给出 file:line。
>
> **修复记录（2026-09-11，与本文件入库同批）**：Known Bugs 两条 High 缺陷（descr size 回绕 /
> shape 回绕）已修复并各自固化回归测试（`tests/dtype_test.mbt` ×2、`tests/edge_test.mbt` ×1），
> 仓库测试基线 156 → **159** 全绿。（文首 `159` 是分析当日连 3 条临时探针一起跑的计数；仓库
> 真实基线当时为 156。）另以 NumPy 2.3.4 实测更正下方一处判断：带前导零的 descr 是 NumPy
> **合法**输入，缺陷判据仅数值回绕本身，详见各条目的 Fixed 注记。其余与本批直接相关的发现
> （acceptance §12/§14 未同步、`AGENTS.md` 证据指针指向仓库外）亦已随本批或前序 commit
> 处置，见对应条目的 Fixed / Partially fixed 注记。

## Tech Debt

**`NpyError` 未实现 `Eq`，全仓负面断言退化为 `match` + `assert_true(false)` [实测]:**
- Issue: `src/error/error.mbt:20` 只有 `} derive(Debug)`，没有 `Eq`；`Result[T, NpyError]` 因此不可比较。
- Why: 推测是 enum 带 payload（`InvalidByteOrder(Byte)`、`DataLengthMismatch(Int64, Int64)`）时顺手只 derive 了 Debug，但所有 payload 其实都可 `Eq`。
- Impact: 写探针时 `assert_eq(@dtype.parse_dtype(...), Err(...))` 直接编译失败（`[4018] Type @ShunjunGu/moon-npy/src/error.NpyError does not implement trait Eq: no 'impl' is defined`）。后果是全仓约 100+ 条负面断言只能写成 `match … { Err(X) => (); _ => assert_true(false) }`（如 `tests/security_test.mbt:20-24`、`tests/dtype_test.mbt:113-125`、`tests/edge_test.mbt:108-115`），失败时**看不到 actual value**，只能看到 `assert_true(false)`。这也正是「每条 negative case 断言具体枚举分支」这条 §12 纪律需要人肉维持的原因。
- Fix approach: 改 `derive(Debug, Eq)`（payload 全部支持 Eq），随后可把既有断言逐步收敛为 `assert_eq` 并获得可读 diff。

**`slice_payload` / `slice_bytes` 逐字节拷贝循环重复两份 [读码]:**
- Issue: `src/reader/reader.mbt:73-79` 与 `src/npz/npz.mbt:110-116` 是同一段循环的两个副本（`Array::make` + `for` 逐字节 + `Bytes::from_array`）。
- Why: `src/npz/npz.mbt:105-109` 注释明确承认是刻意重复——npz 包够不到 reader 的私有 helper，为避免循环依赖而复制。
- Impact: 同一处热路径性能问题要在两个文件各修一次；`Bytes` 无零拷贝子切片（注释所述）这一约束被固化了两遍。
- Fix approach: 把该 helper 提升到 `src/format/`（或新的 `src/bytes_util/`）成为 `pub`，两包共同 import；纯重构，无行为变更，可被既有 156 个测试整体兜住。

**「绝不静默截断」纪律在 descr size 解析路径上完全缺席 [实测]:**
- Issue: `src/dtype/dtype.mbt:208-222` 用 32 位 `Int` 累加 descr 的 size 数字，**没有任何溢出守卫、也没有任何注释**；同类算术在 `src/header/lexer.mbt:130-139`（UInt64）至少被 `tests/fuzz_test.mbt:116-117` 显式记录为「wraps rather than traps」。
- Why: 两处都按「不会 trap 就安全」的 fuzz 不变式取舍，忽略了「回绕后返回 `Ok` 是错误答案」这一维度。
- Impact: 见下方 Known Bugs 两条——聚合文件被接受为合法 dtype，而 §9.2/B2「乘 `itemsize` 前先做溢出预检，绝不静默截断」只被落实在 `src/reader/reader.mbt:57` 与 `:105`。
- Fix approach: 在 `dtype.mbt` 的累加循环里加 `if size > 0xFFFF { return Err(InvalidDType(descr)) }`（NumPy itemsize 不会超过 3 位）；lexer 侧同理加 `if n > UINT64_MAX/10` 守卫。

**`docs/spec/acceptance.md`（自称「仓库内唯一权威 spec owner」）自 v0.2.0/v0.3.0 起未同步 [实测]:**
- Issue: §12（`docs/spec/acceptance.md:127-133`）仍写「CLI 渲染/测试断言的 **13** 个变体」并列举到 `InvalidChunkRange` 为止，而 `src/error/error.mbt:6-25` 现在是 **19** 个变体（含 6 个 `Npz*`，`src/cli/cli.mbt:428-433` 已有对应穷尽分支）。§14（`:145`）写「overall **91.7%**」，而仓库根的 `coverage-summary.txt` 末行是 `Total: 822/890` = **92.4%**（与 `CHANGELOG.md:30-31` 的 v0.3.0 数字一致）。§15 的 fixture 契约仍只说 31 个 `.npy`，未提 v0.3.0 新增的 3 个 `.npz` / `npz_expected.json`。
- Why: C1（NPZ）落地时改了代码与 CHANGELOG，但没有回改 spec owner。
- Impact: 文件第 13-14 行自己规定「若代码与本文件冲突，以代码为准并同步修订本文件」——规则存在但未执行。任何按 spec owner 行事的 agent/新人会拿到**错误的错误模型**与**过期的覆盖率基线**。
- Fix approach: 把 §12 变体清单补齐到 19、§14 数字改为 92.4%（或改为「以 CI 实际输出为准」不再写死数字）、§15 补 `.npz` 契约；并把「改代码同 commit 改 acceptance.md」写进 PR 纪律。
- **Fixed (2026-09-11):** 三项已闭环——§12 补齐 19 变体、§14 更新为含日期的准确快照（core parser 98.5% / overall 81.7%，并标注 Total 分母含入口零覆盖与 `src/` 口径），随解析器修复 commit 落库；§15 的 NPZ 归档门禁段（`:190-192`）与 §19 的 fixture-drift 范围（`:222-223`）由 `b3c4969` 先行补齐。

**验收证据产物不入库，但被 spec 当作事实源 [实测]:**
- Issue: `docs/spec/acceptance.md:145` 明确引用 `coverage-summary.txt` 作为「当前实测」来源，但 `git ls-files --error-unmatch bisect.coverage coverage-summary.txt` 报 `did not match any file(s) known to git`——两者都被 `.gitignore`（`.gitignore:19-22`）排除，克隆里不存在。`coverage-summary.txt` 还是 UTF-16LE + BOM 编码（`file` 报 `Unicode text, UTF-16, little-endian`），只有 8 条记录，且**不含任何 provenance**（无命令、无日期、无工具链版本、无 commit）。
- Why: 按 `.gitignore` 把 `moon coverage` 产物当本地垃圾处理，但 spec 又按「文档」引用它。
- Impact: 克隆后无法复现 spec 里写死的那两个覆盖率数字；数字与代码只能靠 CI 日志对齐。另：该文件只有 8 条记录（7 个文件行 + Total），读者极易误判「只测了 7 个文件」——实际原因是 `moon coverage report -f summary` **只列未满覆盖的文件**（`CHANGELOG.md:171` 有旁证：「`adapter.mbt` 26/26 全覆盖，从 `coverage report -f summary` 的未满行清单消失」；`bisect.coverage` 里 `reader/writer/codec/codec/endian/adapter` 等 9 个文件点全非零，故被省略）。这条语义在 `ci.yml:105-107` 只是一句注释。
- Fix approach: 要么把 `coverage-summary.txt` 入库并附生成命令 + commit + 工具链版本（首行加注释），要么删掉 spec 里对它的引用、改为「数字以 CI 日志为准」；并在 `ci.yml` 注释里把「未列出 ≠ 未测」写清。

## Known Bugs

**descr 的 size 数字用 32 位 `Int` 累加、溢出回绕 → 畸形 descr 被接受为合法 dtype [实测]（已修复，见条目末 Fixed 注记）:**
- Symptoms: `@dtype.parse_dtype("<f4294967300")` 返回 `Ok((Float32, Little))`；`@dtype.parse_dtype("<i0000000004")` 返回 `Ok((Int32, Little))`。两者都不是 NumPy 的合法 descr，`np.load` 会拒绝。
  > **更正（NumPy 2.3.4 实测，2026-09-11）**：`<f4294967300` 确为非法（`TypeError: data
  > type not understood`），但 `<i0000000004` / `<i04` 等带前导零的 descr 是**合法**输入
  > （NumPy 分别解析为 `int32`；29 个前导零的 `<f0…04` 亦解析为 `float32`）。缺陷判据仅为
  > 数值回绕；修复后 `<i0000000004` 保持 `Ok(Int32)`，与 NumPy 一致。
- Trigger: 用探针测试实跑（`moon test --target native` 全绿 = 预测被证实）。等价的最小触发是任何 `"<{kind}{前导零}{合法宽度}"` 或数字部分 ≥ 2^32 的 descr，例如 `<i0000000004`。
- Root cause: `src/dtype/dtype.mbt:208-222`：
  ```moonbit
  let mut size = 0
  while i < n {
    let code = c.to_int()
    if code >= 48 && code <= 57 {
      size = size * 10 + (code - 48)   // Int 是 32 位、溢出回绕 (AGENTS.md §4)
  ```
  回绕后落进 `kind_size_to_dtype` 的 `1/2/4/8/16` 分支即被判为合法。`4294967300 % 2^32 == 4` → `Float32`。
- Impact: **不是内存安全问题**（itemsize 仍被限制在 1/2/4/8/16，`src/reader/reader.mbt:105-113` 的 payload 长度对账仍成立），但是「畸形文件被静默接受」的正确性缺陷：与 §21「Oracle = NumPy 实际行为」矛盾，且 `writer.encode` 会用 `@dtype.descr_code` 重建 descr（`src/writer/writer.mbt:85`），因此这类文件一旦被接受就会以**被归一化后的 descr** 重新写出，破坏字节级 round-trip 可比性。
- Workaround: 无（调用方无法区分）。
- Fix approach: 在循环内加宽度上界（如 `if size > 9999 { return Err(InvalidDType(descr)) }`），并补 2 条 `tests/dtype_test.mbt` 负例。
- **Fixed (2026-09-11):** 累加循环内加幅值守卫（`src/dtype/dtype.mbt`，乘前检查 `size > 0xFFFF` → `InvalidDType`）；回归 `tests/dtype_test.mbt::parse_dtype_reject_size_overflow`（`<f4294967300`、24 位数字串），并以 `parse_dtype_leading_zeros_stay_legal` 钉住「只限数值、不限位数」边界。

**shape 维度用 `UInt64` 累加、溢出回绕 → shape 静默截断 [实测]（已修复，见条目末 Fixed 注记）:**
- Symptoms: `shape: (18446744073709551617,)`（即 2^64 + 1）的文件被解码成**长度为 1 的 f4 数组**，`to_f32()` 返回 `[1.0]`，而不是 `ShapeOverflow`。
- Trigger: 实跑探针构造 v1 文件（body 用 `shape: (18446744073709551617,)`，payload 4 字节 `00 00 80 3F`）→ `@reader.decode` 返回 `Ok`，`element_count == 1`。
- Root cause: `src/header/lexer.mbt:130-139` 的 `Num` 扫描无溢出守卫：
  ```moonbit
  while j < end && is_digit(data[j]) {
    n = n * 10UL + (data[j].to_int() - 48).to_uint64()   // UInt64 回绕，无检查
  ```
  回绕后的值再交给 `src/reader/reader.mbt:53-67` 的 `shape_element_count`，那里的守卫只对**已经回绕过的**数做乘法检查，救不回来。2^64+1 → 1。
- Impact: 与 §9.2/B2 的「绝不静默截断」正面冲突（该纪律在 `reader.mbt:57` 被认真实现，却在更上游的 lexer 被绕过）。**这是本项目唯一被显式记录在案的已知回绕点**——`tests/fuzz_test.mbt:116-117` 写「long digit runs (lexer.mbt:135 wraps rather than traps, per the §21 UInt64 probe)」——即团队知道它，但把它当作「不 trap 即可接受」，因为 §18 的不变式只要求「不 crash」。
- Workaround: 无。
- Fix approach: 在 digit 循环里加 `if n > (UINT64_MAX - digit) / 10 { return Err(@error.ShapeOverflow) }`；同时把 §18 不变式从「不 trap」升级为「不 trap **且** 不回绕」（见 Test Coverage Gaps）。
- **Fixed (2026-09-11):** 守卫按原方案落在 digit 循环内（`src/header/lexer.mbt`，`n > (UINT64_MAX - digit) / 10` → `ShapeOverflow`，在最早可证明点抛出）；回归 `tests/edge_test.mbt::edge_shape_overflow_lexer_wrap`（2^64+1 报错，且 `UInt64::max` 本身不误伤、由下游 Int64 守卫拒绝）；`tests/fuzz_test.mbt` 不变式注释已升级为「no trap **AND** no wrap」。

**`.npz`：`cd_size` 读入后从未用于校验 central directory 遍历的结束位置 [读码]:**
- Symptoms: 一个 EOCD 声明 `cd_size = X` 但 CD 记录实际延伸到 `cd_offset + X` 之后的容器会被接受。
- Trigger: 手改 `cd_size` 字段（`src/npz/npz.mbt:188` 的 `eocd + 12`）为一个偏小值，其余不动；遍历边界只有 `file_len`（`:203`/`:210`）与 `total_entries`（`:192`）。
- Root cause: `src/npz/npz.mbt:188-265` 只在 `:195` 用 `cd_offset + cd_size > eocd` 做了一次粗检，之后 `cd_size` 不再参与；循环结束也没有 `pos == cd_offset + cd_size` 的后置断言。
- Impact: 声明的 CD 大小不构成被验证的不变式，解析器比 zip 规范更宽松（同类问题在 zip64 拒绝路径上是被认真处理的，见 `:181-191`）。
- Fix approach: 循环后加 `if pos.to_int64() != cd_offset + cd_size { return Err(@error.NpzBadStructure("central directory size mismatch")) }`，并在 `tests/npz_test.mbt` 加一条负例。

**`.npz`：成员名 `.npy`（去掉后缀后为空串）会被接受为空 key [读码]:**
- Symptoms: `resolve_member_name`（`src/npz/npz.mbt:149-163`）对名字 `".npy"` 走 `:158` 的 `n >= 4 && name[n-4:] == ".npy"` 分支，返回 `""`，于是 `NpzArchive::get("")` 可命中。
- Trigger: 构造成员名为 `.npy` 的容器。
- Root cause: 后缀剥离后未检查剩余部分非空。
- Impact: 极低（只读 API，不写盘，无穿越）；但 `unsafe_member_name`（`:274-284`）的拒绝语义因此出现一个空洞——它按名字字符判定，空串穿过所有检查。
- Fix approach: `if n == 4 { return Err(@error.NpzUnsafeMemberName(name)) }` 或统一对剥离后的 key 做非空校验。

## Security Considerations

**无输入大小上限 / 无流式：untrusted `.npy` 可触发「相对输入放大」的内存占用 [读码]:**
- Risk: `validate`/`decode` 接受任意长度的 `Bytes`，全程无 `max_bytes` 之类的参数。`src/format/format.mbt:93-96` 只要求 `header_len` 不超出文件长度，**没有对 header 区域或 token 数量设上界**；`src/header/lexer.mbt:78-164` 每个标点字节产一个 `Token`、`src/header/parser.mbt:110-117` 每个维度产一个 `UInt64`。实测（`coverage-summary.txt` 对应的 `bisect.coverage`）显示 lexer.mbt 有 71 个插桩点、按块计数，说明这条路径确实被驱动过，但没有规模上界测试。
- 量化：放大是**小常数倍**（标点类 token 无 payload，约 4 字节/字节；`Num` token 一个 run 才产一个），且攻击者必须真的提供那些字节（`:94` 的 `total < data_offset → TruncatedHeader` 保证 header 不能凭空声明）。所以这**不是** zip-bomb 级放大，而是「1 MB 恶意文件换几 MB 内存」的线性放大 —— 若库被用在服务端解析上传，需要调用方自己设限。
- Current mitigation: `decode` 只在 `validate` 通过后才分配 payload（`src/reader/reader.mbt:129-147`），且 `expected = element_count * itemsize` 必须先与真实 payload 字节数**精确相等**（`:111-113`），所以「小文件声明大数组」这条经典 DoS 路径已被封死。
- Recommendations: ① 给 `header_len` 或 token/dim 数量加上界（NumPy 侧对 header 也不是无上限信任的）；② 考虑公开一个 `validate_with_limit(data, max_bytes)` 或在 `NpyMeta` 里回传 `header_len` / `ndim` 供调用方自行设限；③ 在 `tests/security_test.mbt` 补一条「畸形超大 header 不导致失控分配」的回归用例。

**`tests/security_test.mbt` 只覆盖 dtype 边界（3 个用例），解析器加固面基本没有安全测试 [实测]:**
- Risk: 该文件全文 54 行、`grep -c "^test "` = **3**，只断言 `|O`/`<O`/`>O` 三种 object descr 与 `|V8` void 的前置拒绝（`tests/security_test.mbt:13-54`）。上述两条溢出/回绕缺陷（都会被 fuzz 判为「通过」）、header 长度信任、维度数无上限，全部没有安全向回归资产。
- Current mitigation: 容器层的安全拒绝**是有测试的**，且覆盖不错：`tests/npz_test.mbt`（775 行）里 `NpzUnsafeMemberName` 出现 5 次、`NpzDuplicateMember` 3 次、`NpzZip64Unsupported` 5 次、`NpzCompressedMember` 4 次、`NpzBadStructure` 11 次、`NpzMemberNotFound` 4 次。dtype 层的 `|O` 拒绝也在 `tests/edge_test.mbt:188-196` + `tests/security_test.mbt` 双处钉住。
- Recommendations: 把 `tests/security_test.mbt` 扩成「解析器加固」清单：整数回绕、header 长度信任、无界 ndim、空 key，每条一个用例。这样「Security by construction」的README 叙述（`README.md:530-585`）才有与容器层同等强度的证据。

**`.npz` 路径穿越防护是「字符黑名单」而非「允许列表」[读码]:**
- Risk: `unsafe_member_name`（`src/npz/npz.mbt:274-284`）只拒绝含 `/`、`\`、等于 `..`、以及第二字符为 `:` 的名字，其余一律放行（含 `.`、空串、以及 `..foo`、`C%3A` 这类编码变体）。若下游消费者把这些 key 当文件名使用，防护边界由消费者决定而非本库。
- Current mitigation: 本库**从不写盘**（`src/npz/npz.mbt` 全文无 `@fs` 调用，`@fs` 只出现在 `cmd/main/`），成员名只作为字典 key 返回，所以「by construction 不存在穿越」这一声明成立；拒绝逻辑是为下游预留的深度防御。
- Recommendations: 由于 key 从不成为路径，可考虑在 `NpzArchive::get` 的文档里显式写「返回的 key 不得当作文件路径使用」，或把黑名单换成允许列表（如 `[A-Za-z0-9_.-]` + 长度上限），语义更好定义也更好测试。

**`endian.mbt` 的「所有后端都是小端」是一个未经验证的平台假设 [读码]:**
- Risk: `src/dtype/endian.mbt:3-6` 与 `:46-52` 两处把 `=`（native）读作小端，理由写成「every MoonBit backend (native/wasm/js/wasm-gc) is little-endian … a documented platform assumption about our own runtimes」。`src/adapter/moonnum/adapter.mbt:79-83` 把 `Little | Native | NotApplicable` 一并按小端处理，`src/dtype/codec.mbt` 的整条 decode 路径都建立在此之上。
- Current mitigation: 假设本身合理（现有后端确实都跑在 LE 硬件/VM 上），且 `=` 只在 `tests/edge_test.mbt:251` 一个用例里出现。
- Recommendations: 这是**可测试的**：`.github/workflows/ci.yml` 目前只跑 `--target native`，加一个 wasm-gc / js 的 `moon check`（至少 `moon check --target wasm-gc`）就能把「跨后端」从断言变成证据。工作树里 `_build/wasm-gc/release/format/` 显示本地曾做过 wasm-gc 构建，但 CI 里没有对应门禁。

## Performance Bottlenecks

**元素解码路径：`decode + to_f32` 比 `decode` 慢约 2.2×（377 MB/s vs 1152 MB/s）[实测 / 引用仓库自带基准]:**
- Problem: 307328 B（100×768 f4）的实测四条路径：fs read（热缓存）53.0 µs / 5804 MB/s、decode（validate + payload 拷贝）266.7 µs / 1152 MB/s、decode + `to_f32`（76800 floats）816.1 µs / 377 MB/s、逐行 100 × `to_f32_chunk(768)`（预解码数组）602.3 µs / 510 MB/s（数字源：`CHANGELOG.md:13-19`，`examples/bench/main.mbt` 可复现）。
- Cause: 两条：① `src/reader/reader.mbt:186-188` 用 `out.push(read(...))` 往空 `Array[T]` 里逐个追加，**没有按 `len` 预留容量**；② `src/dtype/codec.mbt:19-31` 的 `read_uint` 是「每字节一次循环 + 每字节一次 `is_big` 分支」的手工拼装（AGENTS.md §3 确认无跨后端内建按字节序读，所以这是唯一可行基线，但可为 f32/f64 单开快路径）。
- Improvement path: ① 把 `out` 改为 `Array::make(len, seed)` + 下标赋值（或至少 `reserve`），去掉增长重分配；② 为 `read_f32`/`read_f64`/`read_i32` 走 `read_bits32`/`read_uint` 已存在的定长直读（4/8 字节），跳过循环；③ 对 LE 且 `itemsize∈{1,2,4,8}` 的场景做整段 memcpy 视图（需要先解决 `data` 是 `Bytes` 无法零拷贝的问题，见下条）。

**每次 `decode` 至少一次全量 payload 拷贝，S6 适配路径要三次 [读码]:**
- Problem: `src/reader/reader.mbt:73-79` 的 `slice_payload` 先 `Array::make(len, b'\x00')` 再逐字节填，最后 `Bytes::from_array(arr)` —— 一次填 + 一次装箱 = 两次分配、两次全量写。`src/npz/npz.mbt:110-116` 同构。随后 `src/adapter/moonnum/adapter.mbt:96` 的 `arr.data.to_array()` 是第三次全量拷贝。
- Measurement: 上述拷贝的代价包含在 decode 的 266.7 µs / 1152 MB/s 里；适配路径的额外一次 `to_array()` 在 `docs/s6-api-card.md:148-150` 被明确记录为「全流程唯一一次元素级拷贝」——但读者容易忽略此前 reader 已经拷过一次。
- Cause: `NpyArray::data : Bytes`（`src/reader/reader.mbt:45`）是无偏移的完整 `Bytes`，而 `Bytes` 在本 pin 下没有「返回 Bytes 的零拷贝子切片」API（只有 `BytesView`，见 `reader.mbt:70-72` 注释），所以切片只能拷贝。
- Improvement path: 把 `NpyArray::data` 换成 `BytesView`（或 `(Bytes, offset, len)` 三元组），`decode` 即可零拷贝；代价是所有 accessor 与 writer 的 `data[...]` 索引要改为相对视图。这是一次跨 `reader`/`writer`/`adapter`/`npz` 的接口变更，收益是省掉整段 payload 拷贝（decode 的 1152 MB/s 里拷贝占大头）。

**`find_eocd` 最坏情况逐字节回扫 65557 个位置 [读码]:**
- Problem: `src/npz/npz.mbt:124-141` 从 `file_len - 22` 每次退 1 直到 `scan_start`（最多退 65535），每个位置做一次 4 字节签名比对 + 一次 `read_u16_le`。
- Measurement: 未单独测量；上界 65557 × ~5 次字节访问 ≈ 3×10^5 次操作，属亚毫秒量级，只有把 `.npz` 读放进紧循环才可观测。
- Cause: 为兼容「EOCD 尾部可有最长 65535 字节注释」而做的保守回扫，且要求 `pos + 22 + comment_len == file_len` 精确吻合（正确性优先的写法）。
- Improvement path: 先按 4 字节步长扫 `PK\x05\x06` 或从后向前扫 `\x06\x05\x0bP`，再回退验证；或直接把 `scan_start` 收窄到典型注释长度。优先级低——当前形态是刻意的保守设计。

## Fragile Areas

**`src/adapter/moonnum/adapter.mbt` 是唯一第三方边界，且它建立在对方的实现细节上 [读码]:**
- Why fragile: `src/adapter/moonnum/adapter.mbt` 全文 119 行、26 个插桩点、10 个测试（`tests/adapter_test.mbt` 194 行），却把正确性押在两个**没有稳定性承诺**的前提上：① 调用 `@core.NdArray::from_buffer(arr.data.to_array(), dtype, shape, order)`（`adapter.mbt:96`），依赖它「按 order 自己算字节步长」这一行为；② 依赖 `NdArray::strides` 是**字节步长**这一约定（`docs/s6-api-card.md:117-118`）。更脆的是对方连字节序都没有建模——`NdArray::is_little_endian()` 的实现是**字面量 `true`**（`docs/s6-api-card.md:158-171` 抄录了 `src/core/core.mbt:359` 原文），所以 `adapter.mbt:77-83` 只能在**自己的**一侧把 big-endian 硬拒。
- Common failures: 对方发补丁版改 `from_buffer` 的 stride 语义或 `Dtype` 变体名 → `moon check` 失败或（更糟）静默算出错误 stride；BE 文件若绕过 dtype 门就会「静默变成一堆天文数字」（`docs/s6-api-card.md:170` 原话），而不是报错。
- Safe modification: 改动一律限制在 `convert`（`adapter.mbt:69-100`）之内，保持「先 dtype 门、再字节序门、再 shape 门」的顺序（现有测试 `tests/adapter_test.mbt:167` 明确钉住了「dtype 门先于字节序门」）；任何 `moonNum` 版本变动后必须重跑 `moon check` + `moon test --target native`，并把新签名回抄进 `docs/s6-api-card.md` §3.4。
- Test coverage: 好（`tests/adapter_test.mbt` 覆盖 C/F order、0-d、三条拒因逐条、`message()` 三臂），但**只覆盖 f32/f64**；适配器对 11 个其它 dtype 的行为只有「拒绝」一条路径。

**工具链 pin 用两个不一致的标识符，且语言本身处于快速变动期 [读码]:**
- Why fragile: 装机版本显示为日期制 `0.1.20260827 (d0aaa07)`（`AGENTS.md:12`），CI 却 pin 在 `MOONBIT_VERSION: "0.10.11+6ff76a5f9"`（`.github/workflows/ci.yml:40`）——因为安装 CDN 只认 semver、date-form 会返回 403（`ci.yml:31-39` 记录了这次实测）。二者指同一个构建，但**多了一处需要人工同步的事实**。更根本的风险是这个语言仍在高速演进：`AGENTS.md` 逐条记录了 6 处「计划 vs 实测」的语言/库变更（`try?` 弃用、`@sys.get_cli_args` 弃用、`Bytes::make` 命名参数作废、`Array` 无 `create`、`+=` 语法不被接受、`.mbt` 文件级 `import` 非法），并明确标注「禁止基于旧假设或博客版本臆写」。
- Common failures: `curl … | bash -s "0.10.11+6ff76a5f9"` 在 CDN 撤包后 404 → 整条 CI 在第 5 步就红，且失败信息指向网络而非代码；或升级工具链后 `AGENTS.md` 的语法/API 事实整份失效。
- Safe modification: 任何涉及「MoonBit 语法/API 事实」的改动，先在 `moon check --target native` + `moon test --target native` 下实跑再落笔；`AGENTS.md` §0/§8 与 `ci.yml:31-42` 必须同 commit 更新。
- Test coverage: 不适用（无 CI matrix，单版本 pin）。

**`docs/spec/acceptance.md` 与其它治理文档之间存在「引用不可解析」的破口 [实测]:**
- Why fragile: 该文件的立身之本（`:1-9`）是「使仓库各处 `§N` / 附录 A 引用**能在克隆内解析到真实小节**」，但至少两处指到仓库外：`docs/s6-api-card.md:3` 声称自己是 `docs/plans/2026-09-09-moon-npy-v0.2.0-stretch.md` Task 12 的唯一交付物，而 `ls docs/` 只有 `s6-api-card.md` 与 `spec/`——该计划文档不在克隆内；`AGENTS.md:5` 的证据链指向 `../m0smoke/`（不存在的兄弟目录）。
- Common failures: 更实质的一处是**生成的 fixture 契约里带脏引用**：`tests/fixtures/npz_expected.json` 的 `spec_ref` 字段值是 `"docs/plans/2026-09-10-moon-npy-v0.3.0-npz.md §4 Task 4"`（来源 `interoperability/generate_fixtures.py:568`），即入库的 `.npz` Oracle 契约把「验收依据」指向一个克隆里不存在的路径，且 `--check` 只比对 sha256、不比对 `spec_ref`（`docs/spec/acceptance.md:171`），所以这条脏引用不会被漂移门禁发现。对比之下 `tests/fixtures/expected.json` 的同类字段已改为 `"docs/spec/acceptance.md §15/§16, 附录 A"`（正确）。
- Safe modification: 修改 fixture 生成器时，`spec_ref` 只能指向仓库内路径；补一条 `--check` 断言或一次性手工修正 `npz_expected.json` 并重跑生成器确认确定性输出。
- Test coverage: 无（没有「文档引用可解析性」的检查）。
- **Partially fixed (2026-09-11):** `AGENTS.md` 的 `../m0smoke/` 证据指针已由 `6e2c425` 替换为仓库内 `§9` + `acceptance.md` 交叉引用；`docs/s6-api-card.md` 的计划文档引用与 `npz_expected.json` 的 `spec_ref` 脏引用仍待处理（后者为生成器输出，修正须同步重跑 `--check` 确认确定性）。

**双语文档（`README.md` / `README_CN.md`）手工维护、无自动一致性门禁 [实测]:**
- Why fragile: 两个文件各 ~37 KB（36873 / 36914 bytes），项目承诺「与英文版双向链接、技术事实与 API 签名逐条一致」（`CHANGELOG.md:194`），且每个 release 都同步更新两份（v0.1.0/v0.2.0/v0.3.0 的 Changed 段都列了两者）。但 `.github/workflows/ci.yml` 的全部 8 个步骤里没有任何一步校验二者一致。
- Common failures: 单边修改后（尤其「Limitations」「Security」「Compatibility Matrix」这类断言性段落）出现英文版声称支持、中文版没说或反之；`CHANGELOG.md:89-90` 就出现过英文数字（91.3%）与相邻段落数字（91.7%）自相矛盾的先例。
- Safe modification: 改动 README 的断言段落时同 commit 改两份，并在 PR 描述里点名；长期方案是加一个「标题层级 + 代码块数量一致」的廉价结构校验。
- Test coverage: 无。

**`pub(all) enum NpyError` 加变体会立刻打破 CLI 的穷尽 match [读记档]:**
- Why fragile: `src/error/error.mbt:6` 是 `pub(all) enum`，`src/cli/cli.mbt:405-434` 的 `render_error` 是穷尽匹配。这条已经踩过一次：S4 加 `InvalidChunkRange` 时必须同 commit 改 CLI（`CHANGELOG.md:131-133`），S6 因此**放弃**加变体、改用适配器自己的 `AdapterError`（`src/adapter/moonnum/adapter.mbt:19-24`、`docs/s6-api-card.md:227-229`）。现在有 19 个变体。
- Common failures: 只在 `src/` 加变体 → 编译失败（好）；或只在一处补分支而漏了 `tests/cli_test.mbt` 的渲染断言（坏，静默丢覆盖）。
- Safe modification: 加变体的同一 commit 必须同时改 `src/error/error.mbt`、`src/cli/cli.mbt:render_error`、以及 `tests/cli_test.mbt`；把这条写进 `AGENTS.md` 的纪律区（目前只散落在 CHANGELOG 与 api-card 里）。
- Test coverage: `render_error` 的每个分支由 `tests/cli_test.mbt`（440 行）与 `tests/npz_test.mbt` 覆盖，`src/cli/cli.mbt` 实测 217/230 = 94.3%（`coverage-summary.txt`）。

## Scaling Limits

**全内存模型：payload 常驻 + 至少一次整段拷贝，峰值内存约 2–4× 文件大小 [读码]:**
- Current capacity: `decode` 需要同时持有调用方的原始 `Bytes`、`slice_payload` 临时构造的 `Array[Byte]`、以及冻结后的 payload `Bytes`（`src/reader/reader.mbt:73-79`、`:134-138`）；随后 `to_f32` 之类 accessor 再产出 4–8 B/元素的输出数组（`:186-188`，无容量预留）。仓库自己的基准口径是 307328 B 输入 → decode 后 76800 floats（`CHANGELOG.md:13-19`）。
- Limit: `Bytes::length()` 是 `Int`（32 位），`src/reader/reader.mbt:110` 用 `data.length().to_int64()` 把上界抬到 Int64，但 `decode` 在 `:135-137` 又 `meta.payload_len.to_int()` 收窄回 Int —— 单文件可用上界受 32 位 `Int` 寻址约束（约 2 GB 量级）。此外 `flat` 在 `:158` 把 `element_count`（Int64）`.to_int()` 收窄，超界时会以 `InvalidChunkRange` 报错而非给出准确诊断。
- Symptoms at limit: 显存/内存 OOM 后 abort（无 graceful 失败路径）；或对大数组调用全量 accessor 得到看起来像「参数错误」的 `InvalidChunkRange`。
- Scaling path: ① `NpyArray::data` 改 `BytesView`（省一次拷贝，见 Performance 第 2 条）；② 把 payload 懒切片/按窗口读取（README `Limitations` 已明确「真正的按页惰性读不在本轮范围」，`README.md:530-545`）；③ 公开 `max_bytes` 参数让调用方设限。

**`.npz` 拒绝 zip64 → >4 GB 归档 / >65535 成员一律不可读 [读码]:**
- Current capacity: EOCD 与 central directory 的 sentinel 检查（`src/npz/npz.mbt:181-191`）一旦命中 `0xFFFF` / `0xFFFFFFFF` 立即 `NpzZip64Unsupported`。
- Limit: 4 GB 归档体积、65535 个成员、以及 zip64 为了绕开 4 GB 而写的任何字段。
- Symptoms at limit: 结构化错误 `NpzZip64Unsupported`（不是崩溃），但**无任何 workaround**——用户必须先在 Python 侧解包。
- Scaling path: 实现 zip64 EOCD locator/record 的读取与 u64 字段解析；由于解析器已全程用 Int64 比对偏移（`src/npz/npz.mbt:28-31` 注释说明该纪律），扩展成本主要在新增字段解析与测试 fixture。

**`.npz` 压缩成员拒绝 → `np.savez_compressed` 产物完全不可读 [读码]:**
- Current capacity: `comp_method != 0` 即 `NpzCompressedMember`（`src/npz/npz.mbt:225-227`），且本仓**没有 inflate 实现**（README Security 小节把这一点当成 by-construction 的安全优势）。
- Limit: 任何使用 deflate 的归档；`tests/fixtures/npz_deflated_c_le_v1.npz` 就是为钉住这条拒绝而存在的 fixture。
- Symptoms at limit: 结构化错误；用户需先在 Python 侧转存为未压缩 `.npz`。
- Scaling path: 引入 inflate（会同时引入解压炸弹攻击面，届时 README 的 by-construction 叙述必须同步改写）或明确把压缩支持列为永久 out-of-scope。

## Dependencies at Risk

**`amor2025/moonNum@0.1.0`（第三方数组库，本仓唯一非官方依赖）:**
- Risk: 版本号 `0.1.0` 且**至今仅此一版**（发布 2026-07-06，`docs/s6-api-card.md:33`）；registry index 里 `repository` 是**空串**——上游没有登记仓库地址，意味着**没有可达的 issue tracker、没有 changelog、没有升级沟通渠道**（`docs/s6-api-card.md:36`）。它自身依赖 `moonbitlang/x@0.4.46` 下界（被本仓的 0.5.1 满足，`moon.mod:18-21`）。
- Impact: 任何 0.1.x 补丁都可能改 `from_buffer` / `Dtype` / `strides` 语义；本仓无法提前得知，只能在 `moon check` 红掉时被动发现。更隐蔽的是它没有字节序维度（`is_little_endian()` 返回字面量 `true`，`docs/s6-api-card.md:158-171`），所以 BE 支持永远不会从对方那边补上。
- Migration plan: 保持适配器极薄（2 个公开函数、119 行）以便整块替换或直接 vendor；`docs/s6-api-card.md` §5 已记录 4 个备选（`tonyfettes/narray`、`walkzzz/owl_mbt`、`tonyfettes/torch`、`Luna-Flow/linear-algebra` 等）——注意其中 3 个其文档判定为 stale 或范围过大，真正可迁移的目标并不现成。

**`moonbitlang/x@0.5.1`（精确 pin）:**
- Risk: 精确 pin 到 0.5.1（`moon.mod:19`），属 0.x 版本，签名可变。
- Impact: **实际影响面比看上去小**——`grep` 确认 `moonbitlang/x/fs` 只被 `cmd/main/moon.pkg`、`examples/bench`、`examples/roundtrip`、`tests/moon.pkg` 引用，**没有任何 `src/` 包引用它**；库核心（`src/header`、`src/npz`、`src/writer`）的 UTF-8 解码走的是 `moonbitlang/core/encoding/utf8`（核心库，隐式依赖，已在 `src/header/moon.pkg:4` 等显式声明）。所以 `x` 挂掉会打断 CLI 与测试/示例，不会打断库本身。
- Migration plan: CLI 层的 `@fs` 调用点很少（`cmd/main/main.mbt` 65 行），必要时可换 `@fs` 的等价实现或直接走 `native` extern；库侧无需迁移。也可借机把 `x` 从 `moon.mod` 降级为「仅 executable 包需要」的更清晰表达。

**MoonBit 工具链 `0.1.20260827` / `0.10.11+6ff76a5f9`（日期制版本 + 快速演进）:**
- Risk: 见 Fragile Areas 第 2 条。补充一点：`AGENTS.md` 是本仓**唯一**的约定来源（bus factor 见下），它整份绑定在这一个构建上；工具链升级会让其中「实测固化」的全部事实需要重验，而 CI 只有单版本、无 matrix（`ci.yml:40`）。
- Impact: 升级成本不是「改一行 pin」，而是「重跑 AGENTS.md 的 7 项 M0 gate 并回填」。
- Migration plan: 保留 `AGENTS.md` §9 的 M0 gate 表作为可重跑的升级检查清单；升级时按该表逐项实跑。可选加固：CI 增加一个不阻塞的 `moon check --target wasm-gc`，把 §3/§4 的跨后端断言变成证据。

**NumPy 2.3.4 / Python 3.14（跨语言 Oracle，仅测试期）:**
- Risk: `interoperability/generate_fixtures.py --check` 与 `roundtrip.py` 是「字节级 + `np.array_equal`」的唯一来源，二者都要求精确的 Python + NumPy（`ci.yml:41-42`）。若某天该组合在 runner 上不可安装，最强的正确性证据链会断。
- Impact: §16/§23 的验收（NumPy → MoonBit → NumPy 逐字节一致）无法复现。
- Migration plan: **已有缓解，风险低**——`tests/property_test.mbt`（33 行）把「decode → encode 逐字节恒等」搬到纯 MoonBit 内，`moon test` 即可强制，不再依赖 Python 环境（`CHANGELOG.md:79-85` 明确写了「与 `roundtrip.py` 互补，非替代」）。

## Missing Critical Features

**没有「从 typed array 构造 NPY」的写入 API（Writer 只能重序列化 decode 产物）:**
- Problem: `writer.encode(array : @reader.NpyArray)`（`src/writer/writer.mbt:83`）只接受 `NpyArray`，而 `NpyArray` 的字段不是 `pub(all)`（`src/reader/reader.mbt:39-46` 是 `pub struct`），外部**无法构造**一个 `NpyArray`——唯一的生产者是 `@reader.decode`。writer 的注释 `:76-82` 把这一点写成显式前置条件。
- Current workaround: 先手写/借道 NumPy 造一个 `.npy`，再 `decode` → `encode`。`examples/roundtrip/main.mbt` 正是这个绕法的示范。
- Blocks: 本库无法作为「把任意数据写成 NPY」的写入器；Demo（§29）也只能做「读进来再写回去」。任何想从 `Array[Float]` + shape 直接产出 `.npy` 的消费者必须自己拼 header 字节（而 header 的 64 字节对齐 + 空格填充 + `\n` 收尾规则只在 `src/writer/writer.mbt:98-137` 实现过一遍）。
- Implementation complexity: 中。需要新增构造入口（如 `NpyArray::from_f32(shape, data, order)`）并处理 element_count / itemsize 一致性校验——`encode` 的 `Result` 错误槽位已为此预留（`src/writer/writer.mbt:80-82`）。

**`.npz` 只有读方向，且只支持未压缩：写方向、deflate、zip64 全缺席:**
- Problem: `decode_npz` 是唯一入口（`src/npz/npz.mbt:172`），没有 `encode_npz`；压缩成员（`:225-227`）与 zip64（`:181-191`）都是硬拒绝。
- Current workaround: 全部依赖 Python 侧 `numpy.savez` / 解压。
- Blocks: ① 无法产出 `np.savez` 兼容归档；② 无法读 `np.savez_compressed` 产物（真实世界最常见的压缩 `.npz` 来源）；③ >4 GB 归档完全不可用。
- Implementation complexity: 写方向低-中（复用既有 NPY writer + 手写 ZIP stored record）；deflate 高（需 inflate 且会引入解压炸弹面，必须同步改写 README Security 的 by-construction 叙述）；zip64 中（解析器已全程 Int64）。

**无跨文件 I/O 的 streaming / mmap 惰性读（刻意缺席）:**
- Problem: `decode` 要求整个文件已在 `Bytes` 里；`to_f32_chunk` 只限制**输出数组**大小，payload 仍全量驻留（`src/reader/reader.mbt:270-283` 注释与 README `Limitations` 都诚实标注了这一点，`CHANGELOG.md:142-146` 还专门改写措辞避免「惰性」误导）。
- Current workaround: 调用方自己按 offset 读文件片段——但 `.npy` 无自描述索引，做不到。
- Blocks: 大于可用内存的数组。
- Implementation complexity: 高（需要文件 seek / mmap 抽象，且当前 `payload_len != expected` 的严格对账逻辑（`src/reader/reader.mbt:111-113`）是为全量读设计的）。

## Test Coverage Gaps

**两个已实测确认的整数回绕缺陷不在任何测试的射程内（fuzz 不变式天然看不见它们）:**
- What's not tested: `@dtype.parse_dtype("<f4294967300")` / `"<i0000000004"` 应被拒却返回 `Ok`；shape `(18446744073709551617,)` 应 `ShapeOverflow` 却解码为长度 1 的数组。
- Risk: 这两条已在下方 Known Bugs 中作为事实给出（**[实测]** 全绿确认）。之所以逃过全部 156 个测试，是因为 `tests/fuzz_test.mbt:6-14` 声明的唯一不变式是 **§18 totality：「不 crash / 不 hang / 不越界 / 不失控分配」**——回绕后返回一个**错误的 `Ok`** 完全满足该不变式。分布 (1)(2)(3) 的输入也都是 ≤128 字节随机 / 64 字节随机 body / 单字节变异（`:96-146`），不产生长数字串或超大维度。
- Priority: High
- Difficulty to test: 低（各 2 条 `assert_true` 风格负例即可，实跑已证明可写）。附带建议：把 §18 不变式从「totality」升级为「totality + 不回绕 + `Ok` 路径的 `element_count` 与 `shape` 乘积一致」，否则同类缺陷会持续对 fuzz 免疫。

**`decode_npz`（v0.3.0 最新的 284 行解析器）完全没有 fuzz 覆盖:**
- What's not tested: `grep -c "npz\|Npz" tests/fuzz_test.mbt` = **0**。三个 fuzz 分布全部只打 `@reader.decode` / `validate`。`tests/npz_test.mbt`（775 行）用的是手工构造的容器，不是随机/变异输入。
- Risk: `src/npz/npz.mbt:12-15` 在代码注释里明确宣称「Total invariant (§18 style): for any Bytes input, decode_npz returns Ok(NpzArchive) or Err(NpyError) -- never a panic, never an inflate, never an execution of container bytes」，但**这条声明目前只有静态读码与手工用例支撑，没有与 `decode` 同等级的 fuzz 证据**。`decode_npz` 是攻击面最大、最新、且做了最多手写偏移算术（EOCD 回扫、CD 遍历、local header 二次定位、Int64→Int 收窄）的一层。`README.md:530-585` 的「Security by construction」叙述同样只把 7000 次迭代的 fuzz 结论挂在 NPY 层。
- Priority: High
- Difficulty to test: 低-中。同一套 splitmix + `check_total` 结构可直接复用：把 `decode_npz` 纳入 `check_total`，再加一个「合法 fixture 打包成伪 npz 后随机变异 EOCD / CD 字段」的分布即可。注意 `decode_npz` 的 Ok 分支要断言 `names()` / `get()` 的自洽（而非元素数量）。

**覆盖率门禁的 core-parser 聚合实际只测量 2 个文件中的 2 个（`format.mbt` 被静默排除）:**
- What's not tested: `.github/workflows/ci.yml:119` 的正则是 `/(format|lexer|parser)\.mbt:/`，注释与输出都写「core parser (format+lexer+parser)」。但由于 `moon coverage report -f summary` **只列出未满覆盖的文件**，而 `bisect.coverage` 显示 `format.mbt` 的 46 个插桩点计数**全非零**（100%），`format.mbt` 根本不出现在 `coverage-summary.txt`（该文件仅 8 条记录：`cmd\main`、`examples\roundtrip`、`src\cli`、`src\dtype\dtype`、`src\header\lexer`、`src\header\parser`、`src\npz`、`Total`）。因此 CI 打出的 `core parser: 129/131 = 98.5%` 只等于 lexer(70/71) + parser(59/60)。
- Risk: 结果偏保守（把 100% 的文件折进聚合只会拉高），所以**门禁本身没被绕过**；真正的风险是「标签与实测对象不符」+「未列出 = 100% 覆盖」这条**只写在注释里、未被断言**的语义（`ci.yml:105-107`）。一旦某个 core 文件因为插桩异常而整个从 summary 消失（而非因为 100%），门禁会把它当成满分放行，没有任何检测。
- Priority: Medium
- Difficulty to test: 低。加一条 awk 断言：要求 summary 里同时出现 `lexer.mbt` 与 `parser.mbt`（core 的两个预期未满文件），并把 `format.mbt` 从聚合正则与标签里去掉、或改为显式要求它出现即视为回归。

**`.github/workflows/ci.yml` 只有 `--target native` 一条路径，「所有后端都是小端」的断言无证据:**
- What's not tested: `src/dtype/endian.mbt:3-6`、`src/adapter/moonnum/adapter.mbt:79-83`、`src/dtype/codec.mbt:19-48` 的字节序正确性全部建立在一个跨后端平台上（native / wasm / wasm-gc / js）。CI 的每一步都是 `--target native`（`ci.yml:97/101/112/156-165`）。工作树里存在 `_build/wasm-gc/release/format/` 说明本地做过 wasm-gc 构建，但**没有入库的、可重复执行的非 native 门禁**。
- Risk: 若某个后端并非小端（或 `Int` 位宽/回绕语义不同），`=`（native）descr 与全部手工 LE 拼装的正确性会在该后端静默失效；`AGENTS.md` §4「Int = 32 位有符号、溢出回绕」这类前提也是后端相关的。
- Priority: Medium
- Difficulty to test: 低-中。最低成本是加一个非阻塞的 `moon check --target wasm-gc`（验证编译期成立性），更进一步是把 `tests/dtype_test.mbt` / `tests/reader_test.mbt` 在 wasm-gc 下跑一遍（需要 CI 支持 wasm 运行时）。

**确定性 fuzz 的语料浅：输入上界 128 B、body 上界 64 B、只做单点变异:**
- What's not tested: 分布 (1) 长度 ∈ [0,128]、分布 (2) body ∈ [0,64]、分布 (3) 每次只改 1 个字节 / 截断 / 追加 ≤16 字节（`tests/fuzz_test.mbt:96-146`）。因此**没有**：多字节结构化破坏、超大/超长 header（§14 的 v2/v3 header_len 是 uint32 路径，fuzz 里只覆盖 v1 帧）、`total_entries` 较大的 `.npz`、以及跨字段组合破坏（如同时改 `descr` 与 `shape`）。总迭代 7000 次，全部由固定种子驱动——可复现性极好，但覆盖面受种子与语料规模限制。
- Risk: 深层解析路径（v2/v3 的 uint32 header_len、dtype size 长数字串、多字段交互）主要靠手写用例覆盖，fuzz 只贡献「不 trap」这一类信号。
- Priority: Medium
- Difficulty to test: 低。加分布 (4)：v2/v3 前缀 + 随机 header_len；加分布 (5)：多字节块变异（每次改 2–8 个连续字节）。

**无外部 fuzz / 无 sanitizer / 无 property-based testing 框架:**
- What's not tested: 仓库内不存在 libFuzzer/AFL 类 harness、没有 ASan/UBSan 配置、没有 PBT 库（`tests/property_test.mbt` 虽名为 property，实际是「对全部 31 个 fixture 断言 `decode → encode` 逐字节恒等」的定点枚举，不是生成式性质测试）。
- Risk: 内存安全问题（越界读、悬垂）在本 pin 的 MoonBit 下无工具可直接探测，只能靠 §18 的「不 trap」间接推断。`README.md:530-585` 的 Security 叙述已诚实限定边界（「不宣称通用沙箱」），所以这条是**已知并已声明的局限**，不是隐藏风险。
- Priority: Low（在 MoonBit 生态里缺乏现成工具链，且当前设计（先对账 payload 长度再逐元素读）已把越界读从算术上排除——`src/dtype/codec.mbt:8-12` 写明了这个 caller-enforced 前置条件）
- Difficulty to test: 高（需要生态工具支持）。

---

*Concerns audit: 2026-09-11*
*Update as issues are fixed or new ones discovered*
