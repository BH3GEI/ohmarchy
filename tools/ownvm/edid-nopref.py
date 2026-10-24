#!/usr/bin/env python3
"""Copy an EDID 1.3 block with the "preferred timing" feature bit cleared.
Usage: edid-nopref.py IN.bin OUT.bin   (IN: hongrong/edid/omarchy-120.bin)

virtio-gpu's mode_valid (drivers/gpu/drm/virtio/virtgpu_display.c) deletes a
PREFERRED mode unless its size is within 16 px of the host's scanout (or is
1024x768); other modes always pass. drm_edid marks the first detailed timing
PREFERRED when an EDID 1.3 has feature bit 0x02, so with omarchy-120.bin the
120 Hz timing (first) goes and the 59.955 Hz one (second) stays whenever the
host scanout is not 2160x1440. With the bit clear no mode is preferred and
drm_mode_sort puts the same-size 120 Hz timing first."""
import sys
e = bytearray(open(sys.argv[1], "rb").read()[:128])
assert e[:8] == bytes([0, 255, 255, 255, 255, 255, 255, 0]) and e[18:20] == b"\x01\x03"
e[24] &= ~0x02
e[127] = (-sum(e[:127])) & 0xff
open(sys.argv[2], "wb").write(e)
print(f"features {e[24]:#04x}, checksum {e[127]:#04x}, wrote {sys.argv[2]}")
