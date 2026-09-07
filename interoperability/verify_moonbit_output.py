#!/usr/bin/env python3
"""
verify_moonbit_output.py — 验证 MoonBit Writer 产物（§16 MoonBit → NumPy）

M3 / M4 阶段工具：MoonBit 侧 write 出 ``.npy`` 后，本脚本用 NumPy 作 Oracle
校验三件事（对应 §19 CI 的后三步 "MoonBit Generates NPY → NumPy Reads →
byte-level round-trip"）：

  1. ``np.load`` 能成功读取（格式合法、非 object/pickle）；
  2. ``--reference <ref.npy>``：与 numpy 参考数组 ``np.array_equal``
     （dtype / shape / 元素值一致）；
  3. ``--byte-exact <ref.npy>``：与 numpy 产物**逐字节一致**
     （§7.4 的 64 字节对齐 + 空格填充 + ``\\n`` 收尾回归，B1）。

退出码：0 = PASS；1 = 校验 FAIL；2 = 用法 / 文件错误。

在 Writer 落地前本工具不会被触发；先就位以固定 Oracle 契约，避免 M3/M4 阶段
临时拼凑校验逻辑（§20 Correctness/Compatibility first）。

用法：
    python interoperability/verify_moonbit_output.py out.npy
    python interoperability/verify_moonbit_output.py out.npy --reference tests/fixtures/f4_2x3_c_le_v1.npy
    python interoperability/verify_moonbit_output.py out.npy --byte-exact  tests/fixtures/f4_2x3_c_le_v1.npy -v
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np


def _load(path: Path) -> np.ndarray:
    """安全读取 .npy：allow_pickle=False 拒绝 object/pickle 数组（§5 / §12）。"""
    return np.load(str(path), allow_pickle=False)


def _is_fortran(arr: np.ndarray) -> bool:
    return bool(arr.flags.f_contiguous and not arr.flags.c_contiguous)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(
        description="Verify a MoonBit-generated .npy against NumPy (Oracle)"
    )
    ap.add_argument("moonbit_npy", type=Path, help="MoonBit Writer 产出的 .npy")
    ap.add_argument("--reference", type=Path,
                    help="参考 .npy（numpy 产出），做 dtype/shape/values 比对")
    ap.add_argument("--byte-exact", type=Path,
                    help="参考 .npy，做逐字节比对（§7.4 对齐回归，B1）")
    ap.add_argument("-v", "--verbose", action="store_true", help="打印数组内容")
    args = ap.parse_args(argv)

    if not args.moonbit_npy.exists():
        print(f"[verify] file not found: {args.moonbit_npy}", file=sys.stderr)
        return 2

    # 1. 可被 NumPy 读取 -----------------------------------------------------
    try:
        got = _load(args.moonbit_npy)
    except Exception as e:  # noqa: BLE001 - Oracle 需报告任何拒读原因
        print(f"[verify] FAIL — np.load rejected the file: {e}", file=sys.stderr)
        return 1
    print(f"[verify] np.load OK: dtype={got.dtype} shape={got.shape} "
          f"fortran_order={_is_fortran(got)}")
    if args.verbose:
        print(got)

    failures = 0

    # 2. 值 / shape / dtype 与参考一致 --------------------------------------
    if args.reference:
        if not args.reference.exists():
            print(f"[verify] reference missing: {args.reference}", file=sys.stderr)
            return 2
        try:
            ref = _load(args.reference)
        except Exception as e:  # noqa: BLE001
            print(f"[verify] reference unreadable: {e}", file=sys.stderr)
            return 2
        if got.dtype != ref.dtype:
            print(f"[verify] FAIL — dtype {got.dtype} != reference {ref.dtype}")
            failures += 1
        elif got.shape != ref.shape:
            print(f"[verify] FAIL — shape {got.shape} != reference {ref.shape}")
            failures += 1
        elif not np.array_equal(got, ref):
            print("[verify] FAIL — values differ (np.array_equal == False)")
            failures += 1
        else:
            print("[verify] array_equal OK (dtype / shape / values match reference)")

    # 3. 逐字节一致（B1：Writer 对齐实现回归）--------------------------------
    if args.byte_exact:
        if not args.byte_exact.exists():
            print(f"[verify] byte-exact reference missing: {args.byte_exact}",
                  file=sys.stderr)
            return 2
        got_bytes = args.moonbit_npy.read_bytes()
        ref_bytes = args.byte_exact.read_bytes()
        if got_bytes == ref_bytes:
            print(f"[verify] byte-exact OK ({len(got_bytes)}B identical to numpy output)")
        else:
            n = min(len(got_bytes), len(ref_bytes))
            diff = next((i for i in range(n) if got_bytes[i] != ref_bytes[i]), n)
            print(f"[verify] FAIL — bytes differ at offset {diff} "
                  f"(len {len(got_bytes)} vs {len(ref_bytes)})", file=sys.stderr)
            failures += 1

    if failures:
        print(f"[verify] {failures} check(s) FAILED", file=sys.stderr)
        return 1
    print("[verify] PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
