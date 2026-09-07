#!/usr/bin/env python3
"""
generate_fixtures.py — moon-npy 兼容性 Oracle fixture 生成器

用当前 NumPy（pinned: 2.3.4）通过 ``numpy.lib.format`` 生成 ``.npy`` fixture，
并从 numpy **实际写出的字节**反推 ``expected.json``（version / descr / shape /
fortran_order / header_len / data_offset / checksum / values），作为 MoonBit
Reader / Writer 测试与 CI 的 ground-truth Oracle。

设计原则（对应计划 §15 / §16 / §19 / §21，字节证据见附录 A）：
  * Oracle = NumPy 真实行为。expected.json 的一切字段都从产物解析得来，不手写、
    不臆测（§21：以 NumPy 实现行为为准，而非机械照搬早期 NEP）。
  * 确定性输出。不嵌入时间戳；相同 numpy 版本重跑 → 字节一致的 .npy 与
    expected.json。CI 可用「重生成 + git diff 为空」或 ``--check`` 校验未漂移。
  * 数据驱动。默认生成入库集：P0 种子集（float32 2×3 C-order × v1.0/v2.0/v3.0）
    + M2 codec 定向矩阵（全 dtype × 字节序 × 小 shape × v1.0）；``--full`` 展开
    §15 完整矩阵（dtype × shape × order × endian × version）。

用法：
    python interoperability/generate_fixtures.py             # 生成入库集(P0+M2 矩阵)
    python interoperability/generate_fixtures.py --full      # 生成 §15 完整矩阵
    python interoperability/generate_fixtures.py --check     # 只校验现有 fixture 未漂移
    python interoperability/generate_fixtures.py --out DIR   # 自定义输出目录

生成器同时自校验每个产物满足 §7.4：magic 正确、数据偏移 64 字节对齐、header 以
单个 ``\\n`` 收尾、解析出的 fortran_order 与 numpy 写盘规则一致。
"""

from __future__ import annotations

import argparse
import ast
import hashlib
import json
import platform
import sys
from dataclasses import dataclass
from pathlib import Path

import numpy as np
import numpy.lib.format as fmt

# --- NPY 格式常量（附录 A.1，实测自 numpy.lib.format） ----------------------
MAGIC_PREFIX = b"\x93NUMPY"
MAGIC_LEN = 8            # magic(6) + version(2)；header 长度字段恒从偏移 8 起
ARRAY_ALIGN = 64         # 数据起始偏移对齐到 64 的倍数

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_OUT = REPO_ROOT / "tests" / "fixtures"


# --- Fixture 规格 -----------------------------------------------------------
@dataclass(frozen=True)
class Spec:
    """一个 fixture 的构造意图。真实记录值以 numpy 产物解析结果为准。"""

    descr: str                 # numpy dtype descr，如 '<f4'、'>f4'、'|b1'
    shape: tuple[int, ...]     # () 表示 0-d scalar
    fortran_order: bool        # 构造意图；1-D/0-D 会被 numpy 记为 C（见下）
    version: tuple[int, int]   # (1,0) / (2,0) / (3,0)
    note: str = ""


def p0_specs() -> list[Spec]:
    """P0 种子集：float32 (2,3) C-order，横跨 v1.0 / v2.0 / v3.0。

    直接对应 §31 首批任务（最小 float32.npy）与 §8.4 的 v3.0 覆盖策略
    （v3.0 + 原始 dtype，验证 uint32 header 长度解析，不引入 structured dtype）。
    三版覆盖两条 header-length 路径：v1.0 = uint16@8，v2.0/v3.0 = uint32@8。
    """
    return [
        Spec("<f4", (2, 3), False, (1, 0), "P0 主用例；np.save 恒产出 v1.0"),
        Spec("<f4", (2, 3), False, (2, 0), "v2.0：uint32 header 长度字段"),
        Spec("<f4", (2, 3), False, (3, 0), "v3.0：uint32 header 长度 + UTF-8 header"),
    ]


def full_specs() -> list[Spec]:
    """§15 完整矩阵：dtype × shape × memory order × byte order × version。

    注意：会产生数百个文件，供本地 / CI 穷举兼容性扫描；默认不全部提交入库。
    单字节 dtype（bool / i1 / u1）无字节序变体（descr 前缀 '|'）。
    """
    kind_sizes = [
        ("b", 1), ("i", 1), ("i", 2), ("i", 4), ("i", 8),
        ("u", 1), ("u", 2), ("u", 4), ("u", 8), ("f", 4), ("f", 8),
    ]
    shapes = [(), (1,), (10,), (2, 3), (2, 3, 4), (1, 1, 1, 1)]
    orders = [False, True]
    versions = [(1, 0), (2, 0), (3, 0)]

    specs: list[Spec] = []
    for kind, size in kind_sizes:
        endians = ["|"] if size == 1 else ["<", ">"]
        for endian in endians:
            descr = f"{endian}{kind}{size}"
            for shape in shapes:
                for order in orders:
                    for version in versions:
                        specs.append(Spec(descr, shape, order, version))
    return specs


def m2_matrix_specs() -> list[Spec]:
    """M2 codec 定向矩阵子集：每 dtype × 字节序 × 小 shape × v1.0。

    目标是让 MoonBit 逐元素 codec（i8..u64 / f32 / f64 × LE/BE）对真实 NumPy
    字节做验证（计划 §9.2 / §15 / Q3 决策）。刻意保持小规模、可提交入库：
      * 1-D (4,) C-order v1.0 覆盖全部 11 种 dtype 的字节序两态
        （单字节 b1/i1/u1 无字节序变体，descr 前缀 '|'）。
      * 追加 0-d scalar / 3-D / F-order 2-D（含 BE）各一，覆盖 element_count
        计算、扁平访问器与 storage-order 元数据。
    float 用 arange → 均为精确可表示值；bool 用奇偶交替（见 make_values）。
    """
    kind_sizes = [
        ("b", 1), ("i", 1), ("i", 2), ("i", 4), ("i", 8),
        ("u", 1), ("u", 2), ("u", 4), ("u", 8), ("f", 4), ("f", 8),
    ]
    specs: list[Spec] = []
    for kind, size in kind_sizes:
        endians = ["|"] if size == 1 else ["<", ">"]
        for endian in endians:
            descr = f"{endian}{kind}{size}"
            specs.append(
                Spec(descr, (4,), False, (1, 0), f"M2 codec 矩阵：{descr} 1-D")
            )
    # 追加：element_count / order / 维度覆盖（不与上面 (4,) 命名冲突）
    specs += [
        Spec("<f8", (), False, (1, 0), "M2：0-d scalar float64（element_count=1）"),
        Spec("<i2", (2, 2, 2), False, (1, 0), "M2：3-D int16（element_count=8）"),
        Spec("<f4", (2, 3), True, (1, 0), "M2：F-order 2-D float32"),
        Spec(">i4", (2, 3), True, (1, 0), "M2：F-order 2-D BE int32"),
    ]
    return specs


def committed_specs() -> list[Spec]:
    """入库 fixture 集 = P0 种子集 + M2 codec 定向矩阵。

    generate() 覆盖写 expected.json，故必须把 p0_specs 一并纳入，避免丢失
    M1 依赖的三条 f4 (2,3) v1/v2/v3 记录。这是默认（无 --full）生成集。
    """
    return p0_specs() + m2_matrix_specs()


# --- 构造确定性、非平凡的数组值 --------------------------------------------
def make_values(descr: str, shape: tuple[int, ...], fortran_order: bool) -> np.ndarray:
    """生成可复现且非平凡的元素值。

    刻意不用全 0：全 0 会掩盖字节序 / 偏移类 bug（读错也「相等」）。用
    ``arange`` 铺 0..n-1（bool 用奇偶交替），float 下均为精确可表示值。
    """
    dt = np.dtype(descr)
    count = int(np.prod(shape, dtype=np.int64)) if len(shape) else 1
    if dt.kind == "b":
        flat = np.array([(i % 2 == 0) for i in range(count)], dtype=dt)
    else:
        flat = np.arange(count, dtype=dt)
    order = "F" if fortran_order else "C"
    return flat.reshape(shape if shape else (), order=order)


def effective_fortran_order(arr: np.ndarray) -> bool:
    """复现 numpy.lib.format 的写盘规则：仅当 F 连续且非 C 连续才记 True。

    1-D / 0-D / (1,1,1,1) 等同时 C+F 连续的数组会被记为 fortran_order=False，
    与 numpy 产物一致（expected.json 记录的是解析后的真实值）。
    """
    return bool(arr.flags.f_contiguous and not arr.flags.c_contiguous)


# --- 写盘 -------------------------------------------------------------------
def write_npy(path: Path, arr: np.ndarray, version: tuple[int, int]) -> None:
    """v1.0 走 np.save（现实世界最常见路径）；v2/v3 必须显式 write_array。

    §8.4 / 附录 A.4：np.save 对简单数组恒产出 1.0，不能用来生成 2.0/3.0。
    """
    if version == (1, 0):
        np.save(str(path), arr)          # path 已以 .npy 结尾 → 不会重复加扩展名
    else:
        with open(path, "wb") as f:
            fmt.write_array(f, arr, version=version)


# --- 解析产物（Oracle 真值来源） -------------------------------------------
def parse_npy(raw: bytes) -> dict:
    """按 NPY 二进制布局解析原始字节，返回 header/offset/data 真值。

    这段逻辑刻意镜像 MoonBit Reader 将要做的事（magic → version → header_len →
    header dict → data），使 expected.json 成为字节级 ground truth。
    header 是受限 Python literal（非 JSON，附录 A.5）→ 用 ast.literal_eval。
    """
    if raw[:6] != MAGIC_PREFIX:
        raise ValueError(f"bad magic: {raw[:6]!r}")
    major, minor = raw[6], raw[7]
    if major == 1:
        header_len = int.from_bytes(raw[8:10], "little")
        header_start = MAGIC_LEN + 2       # 10
    elif major in (2, 3):
        header_len = int.from_bytes(raw[8:12], "little")
        header_start = MAGIC_LEN + 4       # 12
    else:
        raise ValueError(f"unsupported version {major}.{minor}")

    header_bytes = raw[header_start:header_start + header_len]
    if not header_bytes.endswith(b"\n"):
        raise ValueError("header does not end with '\\n' (§7.4 violation)")
    header = ast.literal_eval(header_bytes.decode("utf-8"))
    for key in ("descr", "fortran_order", "shape"):
        if key not in header:
            raise ValueError(f"header missing key {key!r}")

    data_offset = header_start + header_len
    data = raw[data_offset:]
    return {
        "major": major,
        "minor": minor,
        "header_len": header_len,
        "header_start": header_start,
        "header_bytes": header_bytes,
        "header": header,
        "data_offset": data_offset,
        "data": data,
    }


def _shape_tag(shape: tuple[int, ...]) -> str:
    return "x".join(str(d) for d in shape) if shape else "scalar"


def _endian_tag(descr: str) -> str:
    return {"<": "le", ">": "be", "|": "na", "=": "na"}[descr[0]]


def build_entry(spec: Spec, path: Path, raw: bytes) -> dict:
    """解析一个已写出的 fixture，组装 expected.json 的一条记录。"""
    p = parse_npy(raw)
    descr = p["header"]["descr"]
    shape = tuple(p["header"]["shape"])
    fortran_order = bool(p["header"]["fortran_order"])
    dt = np.dtype(descr)
    data = p["data"]

    element_count = int(np.prod(shape, dtype=np.int64)) if shape else 1
    expected_nbytes = element_count * dt.itemsize
    if len(data) != expected_nbytes:
        raise ValueError(
            f"{path.name}: data {len(data)}B != element_count*itemsize {expected_nbytes}B"
        )

    flat = np.frombuffer(data, dtype=dt)
    order = "F" if fortran_order else "C"
    values = flat.reshape(shape if shape else (), order=order).tolist()
    # storage-order 扁平真值：reshape 之前的缓冲顺序，正是 MoonBit 扁平
    # 访问器（Q2：按 storage order 返回）必须逐元素对齐的 Oracle。
    flat_values = flat.tolist()

    return {
        "file": path.name,
        "version": [p["major"], p["minor"]],
        "descr": descr,
        "dtype": dt.name,
        "byteorder": descr[0],
        "shape": list(shape),
        "fortran_order": fortran_order,
        "itemsize": dt.itemsize,
        "element_count": element_count,
        "header_len": p["header_len"],
        "header_start": p["header_start"],
        "data_offset": p["data_offset"],
        "data_nbytes": len(data),
        "file_nbytes": len(raw),
        "aligned_64": p["data_offset"] % ARRAY_ALIGN == 0,
        "sha256": hashlib.sha256(raw).hexdigest(),
        "data_sha256": hashlib.sha256(data).hexdigest(),
        "values": values,
        "flat_values": flat_values,
        "note": spec.note,
    }


# --- 生成 / 校验 ------------------------------------------------------------
def generate(specs: list[Spec], out_dir: Path) -> dict:
    out_dir.mkdir(parents=True, exist_ok=True)
    entries: list[dict] = []
    seen: set[str] = set()

    for spec in specs:
        arr = make_values(spec.descr, spec.shape, spec.fortran_order)
        eff_f = effective_fortran_order(arr)
        name = (
            f"{spec.descr[1:]}_{_shape_tag(spec.shape)}_"
            f"{'f' if eff_f else 'c'}_{_endian_tag(spec.descr)}_v{spec.version[0]}"
        )
        if name in seen:
            raise ValueError(f"duplicate fixture name: {name}")
        seen.add(name)

        path = out_dir / f"{name}.npy"
        write_npy(path, arr, spec.version)
        raw = path.read_bytes()

        # 自校验（§7.4）
        entry = build_entry(spec, path, raw)
        assert entry["aligned_64"], f"{name}: data_offset not 64-aligned"
        assert entry["fortran_order"] == eff_f, f"{name}: fortran_order mismatch"
        entries.append(entry)

    doc = {
        "oracle": {
            "numpy": np.__version__,
            "python": platform.python_version(),
            "generator": "interoperability/generate_fixtures.py",
            "spec_ref": "moon-npy-plan-v0.2.md §15/§16, 附录 A",
            "deterministic": True,
            "note": "字段全部解析自 numpy 真实产物；重跑（同 numpy 版本）字节一致。",
        },
        "count": len(entries),
        "fixtures": entries,
    }

    expected_path = out_dir / "expected.json"
    expected_path.write_text(
        json.dumps(doc, indent=2, ensure_ascii=True) + "\n", encoding="utf-8"
    )
    return doc


def check(out_dir: Path) -> int:
    """校验磁盘上现有 fixture 与 expected.json 一致（未漂移）。返回退出码。"""
    expected_path = out_dir / "expected.json"
    if not expected_path.exists():
        print(f"[check] missing {expected_path}", file=sys.stderr)
        return 2
    doc = json.loads(expected_path.read_text(encoding="utf-8"))
    drift = 0
    for entry in doc["fixtures"]:
        path = out_dir / entry["file"]
        if not path.exists():
            print(f"[check] MISSING file: {entry['file']}")
            drift += 1
            continue
        raw = path.read_bytes()
        actual = hashlib.sha256(raw).hexdigest()
        if actual != entry["sha256"]:
            print(f"[check] DRIFT: {entry['file']} sha256 {actual} != {entry['sha256']}")
            drift += 1
    if drift:
        print(f"[check] {drift} fixture(s) drifted — rerun generator", file=sys.stderr)
        return 1
    print(f"[check] OK — {doc['count']} fixture(s) match expected.json "
          f"(numpy {doc['oracle']['numpy']})")
    return 0


def _print_summary(doc: dict) -> None:
    print(f"numpy {doc['oracle']['numpy']} / python {doc['oracle']['python']}")
    print(f"{'file':32} {'ver':5} {'descr':6} {'shape':10} {'F':2} "
          f"{'hlen':5} {'doff':5} {'nbytes':7}")
    for e in doc["fixtures"]:
        ver = f"{e['version'][0]}.{e['version'][1]}"
        shape = "(" + ",".join(str(d) for d in e["shape"]) + ")"
        print(f"{e['file']:32} {ver:5} {e['descr']:6} {shape:10} "
              f"{'T' if e['fortran_order'] else 'F':2} "
              f"{e['header_len']:5} {e['data_offset']:5} {e['file_nbytes']:7}")
    print(f"\n{doc['count']} fixture(s) written.")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="moon-npy NumPy fixture Oracle generator")
    ap.add_argument("--full", action="store_true",
                    help="生成 §15 完整矩阵（数百文件），而非 P0 种子集")
    ap.add_argument("--check", action="store_true",
                    help="只校验现有 fixture 与 expected.json 是否一致")
    ap.add_argument("--out", type=Path, default=DEFAULT_OUT,
                    help=f"输出目录（默认 {DEFAULT_OUT}）")
    args = ap.parse_args(argv)

    if args.check:
        return check(args.out)

    specs = full_specs() if args.full else committed_specs()
    doc = generate(specs, args.out)
    _print_summary(doc)
    print(f"expected.json → {args.out / 'expected.json'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
