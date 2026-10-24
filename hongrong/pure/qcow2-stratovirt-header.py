#!/usr/bin/env python3
"""Rewrite a qemu-img qcow2 v3 header into the shape StratoVirt (鸿融) writes:
header_length 256 and no header extensions (qemu-img writes 112 plus a
feature-name table, which is optional). Edits the file in place; only bytes
104..255 of cluster 0 change. Usage: qcow2-stratovirt-header.py FILE.qcow2"""
import struct, sys
p = sys.argv[1]
with open(p, "r+b") as f:
    h = bytearray(f.read(512))
    assert h[:4] == b"QFI\xfb" and struct.unpack(">I", h[4:8])[0] == 3, "not a qcow2 v3 file"
    cluster = 1 << struct.unpack(">I", h[20:24])[0]
    assert cluster >= 512
    inc, comp, ac = struct.unpack(">QQQ", h[72:96])
    assert inc & ~0x1 == 0 and ac == 0, f"unexpected features {inc:#x} {ac:#x}"
    old_len = struct.unpack(">I", h[100:104])[0]
    ctype = h[104] if old_len > 104 else 0
    assert ctype == 0, "only zlib (0) is expected"
    h[100:104] = struct.pack(">I", 256)
    h[104:256] = bytes(152)          # compression_type 0 + padding, no extensions
    f.seek(0); f.write(h[:256])
print(f"{p}: header_length {old_len} -> 256, extensions removed")
