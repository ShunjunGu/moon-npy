#!/usr/bin/env python3
"""
probe_npz.py — moon-npy v0.3.0 C1 Task 0 探针（非交付 Oracle）

dump `np.savez` 与 `np.savez_compressed` 产物的 ZIP 字节布局，用于 pin：
  1. EOCD 字段位置与数值（本盘条数 / total_entries / cd_size / cd_offset / comment_len）
  2. 每条 central directory 记录的 method / comp_size / name_len / extra_len / local_offset
  3. local header 的 method / GP flags / name_len / extra_len，以及
     crc / comp_size / uncomp_size 是否为 0（bit-3 data descriptor 陷阱）
  4. zip64 extra field（id 0x0001）是否出现（出现 ≠ zip64 归档）

用法：python interoperability/probe_npz.py
"""

from __future__ import annotations

import struct
import sys
import tempfile
from pathlib import Path

import numpy as np

MAGIC_PREFIX = b"\x93NUMPY"


def hexs(b: bytes) -> str:
    return b.hex(" ")


def probe(path: Path) -> None:
    raw = path.read_bytes()
    print(f"=== {path.name} ({len(raw)} bytes, numpy {np.__version__}) ===")

    # --- EOCD: 从末尾回扫 PK\x05\x06 ---
    eocd_pos = raw.rfind(b"PK\x05\x06")
    print(f"EOCD found at offset {eocd_pos} (tail distance {len(raw) - eocd_pos})")
    (disk_no, cd_disk, disk_entries, total_entries, cd_size, cd_offset,
     comment_len) = struct.unpack_from("<HHHHIIH", raw, eocd_pos + 4)
    print(f"EOCD: disk_no={disk_no} cd_disk={cd_disk} disk_entries={disk_entries}")
    print(f"      total_entries={total_entries} cd_size={cd_size} cd_offset={cd_offset}")
    print(f"      comment_len={comment_len} (0xFFFF sentinels? "
          f"total_entries=={total_entries == 0xFFFF}, "
          f"cd_size==0x{cd_size:08X}, cd_offset==0x{cd_offset:08X})")

    # --- central directory ---
    pos = cd_offset
    for n in range(total_entries):
        sig = raw[pos:pos + 4]
        assert sig == b"PK\x01\x02", f"CD entry {n} bad sig {sig!r}"
        (ver_made, ver_need, gp_flags, method, mtime, mdate, crc32,
         comp_size, uncomp_size, name_len, extra_len, comment_len2,
         dstart, iattr, eattr, local_offset) = struct.unpack_from(
            "<HHHHHHIIIHHHHHII", raw, pos + 4)
        name = raw[pos + 46:pos + 46 + name_len].decode("utf-8")
        extra = raw[pos + 46 + name_len:pos + 46 + name_len + extra_len]
        print(f"CD[{n}] name={name!r} method={method} gp_flags=0x{gp_flags:04X}")
        print(f"      comp_size={comp_size} uncomp_size={uncomp_size} "
              f"crc32=0x{crc32:08X}")
        print(f"      name_len={name_len} extra_len={extra_len} "
              f"comment_len={comment_len2} local_offset={local_offset}")
        if extra:
            print(f"      CD extra: {hexs(extra)}")
            # zip64 extra field id 0x0001: 内含 8 字节字段时是真正的 zip64 尺寸
            p = 0
            while p + 4 <= len(extra):
                fid, fsz = struct.unpack_from("<HH", extra, p)
                print(f"      CD extra field id=0x{fid:04X} size={fsz} "
                      f"data={hexs(extra[p + 4:p + 4 + fsz])}")
                p += 4 + fsz
        # --- local header ---
        lsig = raw[local_offset:local_offset + 4]
        assert lsig == b"PK\x03\x04", f"CD[{n}] local_offset bad sig {lsig!r}"
        (lver, lgp, lmethod, lmt, lmd, lcrc, lcomp, luncomp,
         lname_len, lextra_len) = struct.unpack_from("<HHHHHIIIHH", raw,
                                                     local_offset + 4)
        lname = raw[local_offset + 30:local_offset + 30 + lname_len].decode("utf-8")
        lextra = raw[local_offset + 30 + lname_len:
                     local_offset + 30 + lname_len + lextra_len]
        data_start = local_offset + 30 + lname_len + lextra_len
        print(f"  LH: name={lname!r} method={lmethod} gp_flags=0x{lgp:04X} "
              f"bit3={bool(lgp & 0x0008)}")
        print(f"      crc32=0x{lcrc:08X} comp_size={lcomp} uncomp_size={luncomp} "
              f"(zero-fields? {lcrc == 0 or lcomp == 0 or luncomp == 0})")
        print(f"      name_len={lname_len} extra_len={lextra_len} "
              f"data_start={data_start}")
        if lextra:
            print(f"      LH extra: {hexs(lextra)}")
            p = 0
            while p + 4 <= len(lextra):
                fid, fsz = struct.unpack_from("<HH", lextra, p)
                print(f"      LH extra field id=0x{fid:04X} size={fsz} "
                      f"data={hexs(lextra[p + 4:p + 4 + fsz])}")
                p += 4 + fsz
        payload = raw[data_start:data_start + comp_size]
        is_npy = payload[:6] == MAGIC_PREFIX
        print(f"      payload[0:8]={hexs(payload[:8])} "
              f"(NPY magic? {is_npy})")
        pos += 46 + name_len + extra_len + comment_len2


def main() -> int:
    with tempfile.TemporaryDirectory() as td:
        td_path = Path(td)
        f4 = np.arange(6, dtype=np.float32).reshape(2, 3)
        i4 = np.arange(4, dtype=np.int32)
        b1 = np.array([True, False, True])
        p = td_path / "savez.npz"
        np.savez(p, f4, i4, b1, w=np.arange(2, dtype=np.float32))
        probe(p)
        print()
        p = td_path / "compressed.npz"
        np.savez_compressed(p, f4)
        probe(p)
    return 0


if __name__ == "__main__":
    sys.exit(main())
