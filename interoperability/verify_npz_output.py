"""
verify_npz_output.py — 验证 MoonBit NPZ Writer 产物（N7 MoonBit → NumPy）

N7 阶段工具：``examples/npz_write`` 写出 ``.npz`` 后，本脚本用 NumPy +
标准库 zipfile 作 Oracle 校验四件事：

  1. ``zipfile.ZipFile.testzip()`` 逐成员 CRC-32 校验——自实现 crc32.mbt
     的外部验收（对照 numpy / zlib 的真值）；
  2. 每个成员都是 ZIP_STORED（不压缩，N7 的范围声明）且存储名以 ".npy"
     结尾（np.savez 的 "<key>.npy" 约定）；
  3. ``np.load(..., allow_pickle=False)`` 能读归档，且每个成员都能解出
     数组（注意：带 UTF-8 名的成员在这里会以正确的 str 出现，不会变成
     cp437 mojibake——这正是写侧 GP bit 11 的端到端验收）；
  4. ``--reference [KEY=]REF.NPY``（可重复）：npz 成员键**顺序**与给定
     引用完全一致，且逐成员 dtype / shape / ``np.array_equal`` 与参考
     ``.npy``（numpy 产出）一致。

退出码：0 = PASS；1 = 校验 FAIL；2 = 用法 / 文件错误。

用法：
    python interoperability/verify_npz_output.py out.npz
    python interoperability/verify_npz_output.py out.npz \
        --reference f4_2x3_c_le_v1=tests/fixtures/f4_2x3_c_le_v1.npy
    python interoperability/verify_npz_output.py out.npz \
        --reference "数据=tests/fixtures/f4_2x3_c_le_v1.npy" -v
"""

from __future__ import annotations

import argparse
import sys
import zipfile
from pathlib import Path

import numpy as np


def _load_npy(path: Path) -> np.ndarray:
    """安全读取 .npy：allow_pickle=False 拒绝 object/pickle 数组（§5 / §12）。"""
    return np.load(str(path), allow_pickle=False)


def _parse_reference(spec: str) -> tuple[str, Path]:
    """解析 --reference：``[KEY=]REF.NPY``；缺省 KEY 用参考文件名的 stem。"""
    if "=" in spec:
        key, _, raw = spec.partition("=")
        if not key:
            raise argparse.ArgumentTypeError(f"empty key in reference: {spec!r}")
        return key, Path(raw)
    ref = Path(spec)
    return ref.stem, ref


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(
        description="Verify a MoonBit-generated .npz against NumPy (Oracle)"
    )
    ap.add_argument("moonbit_npz", type=Path, help="MoonBit NPZ Writer 产出的 .npz")
    ap.add_argument(
        "--reference",
        action="append",
        default=[],
        type=_parse_reference,
        metavar="[KEY=]REF.NPY",
        help="参考 .npy（numpy 产出）；KEY= 显式指定成员键，缺省用文件名 stem",
    )
    ap.add_argument("-v", "--verbose", action="store_true", help="打印成员内容")
    args = ap.parse_args(argv)

    if not args.moonbit_npz.exists():
        print(f"[verify-npz] file not found: {args.moonbit_npz}", file=sys.stderr)
        return 2

    failures = 0

    # 1. ZIP 层：CRC / 压缩方法 / 命名约定 ----------------------------------
    try:
        with zipfile.ZipFile(args.moonbit_npz) as zf:
            bad = zf.testzip()
            infos = zf.infolist()
    except Exception as e:  # noqa: BLE001 - Oracle 需报告任何拒读原因
        print(f"[verify-npz] FAIL — zipfile rejected the archive: {e}",
              file=sys.stderr)
        return 1
    if bad is not None:
        print(f"[verify-npz] FAIL — CRC-32 mismatch in member: {bad}")
        failures += 1
    else:
        print(f"[verify-npz] CRC-32 OK ({len(infos)} member(s) pass zipfile.testzip)")
    methods = {info.compress_type for info in infos}
    if methods - {zipfile.ZIP_STORED}:
        print(f"[verify-npz] FAIL — non-stored member(s): {sorted(methods)} "
              "(N7 writes the stored profile only)")
        failures += 1
    else:
        print("[verify-npz] method OK (all members ZIP_STORED)")
    non_npy = [info.filename for info in infos
               if not info.filename.endswith(".npy")]
    if non_npy:
        print(f"[verify-npz] FAIL — stored name(s) without .npy suffix: {non_npy}")
        failures += 1
    else:
        print("[verify-npz] member names OK (every stored name ends with .npy)")

    # 2. NumPy 层：np.load 可读 + 每个成员可解出 ----------------------------
    try:
        with np.load(args.moonbit_npz, allow_pickle=False) as data:
            keys = list(data.files)
            loaded = {k: data[k] for k in keys}
    except Exception as e:  # noqa: BLE001
        print(f"[verify-npz] FAIL — np.load rejected the file: {e}", file=sys.stderr)
        return 1
    print(f"[verify-npz] np.load OK: {len(keys)} member(s) {keys}")
    if args.verbose:
        for k in keys:
            print(f"  {k}: dtype={loaded[k].dtype} shape={loaded[k].shape}")
            print(loaded[k])

    # 3. 与参考 .npy 逐成员一致（键顺序是 N7 契约的一部分）------------------
    if args.reference:
        ref_keys = [k for k, _ in args.reference]
        if keys != ref_keys:
            print(f"[verify-npz] FAIL — member keys {keys} != reference keys "
                  f"{ref_keys}")
            failures += 1
        else:
            for key, ref_path in args.reference:
                if not ref_path.exists():
                    print(f"[verify-npz] reference missing: {ref_path}",
                          file=sys.stderr)
                    return 2
                try:
                    ref = _load_npy(ref_path)
                except Exception as e:  # noqa: BLE001
                    print(f"[verify-npz] reference unreadable: {e}", file=sys.stderr)
                    return 2
                got = loaded[key]
                if got.dtype != ref.dtype:
                    print(f"[verify-npz] FAIL — {key}: dtype {got.dtype} != {ref.dtype}")
                    failures += 1
                elif got.shape != ref.shape:
                    print(f"[verify-npz] FAIL — {key}: shape {got.shape} != {ref.shape}")
                    failures += 1
                elif not np.array_equal(got, ref):
                    print(f"[verify-npz] FAIL — {key}: values differ "
                          "(np.array_equal == False)")
                    failures += 1
                else:
                    print(f"[verify-npz] {key}: array_equal OK vs "
                          f"{ref_path.as_posix()}")

    if failures:
        print(f"[verify-npz] {failures} check(s) FAILED", file=sys.stderr)
        return 1
    print("[verify-npz] PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
