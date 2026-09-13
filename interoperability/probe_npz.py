#!/usr/bin/env python3
"""
probe_npz.py — moon-npy v0.3.0 C1 Task 0 探针（非交付 Oracle）

dump `np.savez` 与 `np.savez_compressed` 产物的 ZIP 字节布局，用于 pin：
  1. EOCD 字段位置与数值（本盘条数 / total_entries / cd_size / cd_offset / comment_len）
  2. 每条 central directory 记录的 method / comp_size / name_len / extra_len / local_offset
  3. local header 的 method / GP flags / name_len / extra_len，以及
     crc / comp_size / uncomp_size 是否为 0（bit-3 data descriptor 陷阱）
  4. zip64 extra field（id 0x0001）是否出现（出现 ≠ zip64 归档）
  5. 完整 CD / LH 字段真值（ver_made/ver_need/mdate/mtime/attrs）。注：
     numpy 2.3.4 的时间戳固定 1980-01-01（zipfile 默认，确定性）；
     N7 Writer 仍以"干净 ZIP"形态对照（真实 crc/尺寸、无占位符、无 extra）
  6. CRC-32 测试向量（zlib.crc32 真值），N7 自实现 CRC-32 的核对基准

用法：python interoperability/probe_npz.py
"""

from __future__ import annotations

import struct
import sys
import tempfile
import zlib
from pathlib import Path

import numpy as np

MAGIC_PREFIX = b"\x93NUMPY"


def hexs(b: bytes) -> str:
    return b.hex(" ")


def crc32_vectors() -> None:
    """CRC-32 (poly 0xEDB88320) vectors for the N7 Writer's self-implemented
    CRC.

    `zlib.crc32` is the exact routine `zipfile` verifies member CRCs with,
    so these values decide whether `np.load` accepts a written archive. The
    MoonBit unit test freezes the same inputs/values ("逐值核对").
    """
    print("=== CRC-32 vectors (zlib.crc32, poly 0xEDB88320) ===")
    cases = [
        ("", b""),
        ('"a"', b"a"),
        ('"hello"', b"hello"),
        ('"123456789"', b"123456789"),
        ("bytes(range(256))", bytes(range(256))),
        ("32 x 0x00", b"\x00" * 32),
        ("8 x 0xff", b"\xff" * 8),
        ("NPY magic + v1.0", MAGIC_PREFIX + b"\x01\x00"),
    ]
    for label, c in cases:
        print(f"  crc32({label}) = 0x{zlib.crc32(c):08X}")
    print()


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
        print(f"      ver_made={ver_made} ver_need={ver_need} "
              f"mdate=0x{mdate:04X} mtime=0x{mtime:04X} "
              f"(fixed 1980-01-01 -- zipfile default, deterministic)")
        print(f"      comp_size={comp_size} uncomp_size={uncomp_size} "
              f"crc32=0x{crc32:08X}")
        print(f"      name_len={name_len} extra_len={extra_len} "
              f"comment_len={comment_len2} local_offset={local_offset}")
        print(f"      dstart={dstart} iattr=0x{iattr:04X} eattr=0x{eattr:08X}")
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
        print(f"  LH: ver_need={lver} name={lname!r} method={lmethod} "
              f"gp_flags=0x{lgp:04X} bit3={bool(lgp & 0x0008)} "
              f"mdate=0x{lmd:04X} mtime=0x{lmt:04X}")
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
    print()
    crc32_vectors()
    return 0


if __name__ == "__main__":
    sys.exit(main())
