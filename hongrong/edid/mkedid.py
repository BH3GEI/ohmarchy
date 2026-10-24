#!/usr/bin/env python3
"""Make an EDID 1.3 block for the 鸿融 virtio-gpu display with a 120 Hz
preferred mode, to load with drm.edid_firmware=Virtual-1:edid/<name>.bin.
Timings use CVT reduced blanking (CVT-RB v1): hblank 160, hsync 32,
hfront 48, vfront 3, vsync 10 (for 3:2), min vblank 460 us.
Usage: mkedid.py OUT.bin [WxH@HZ ...]   (first mode is preferred)"""
import sys, math

def cvt_rb(w, h, hz):
    hblank, hfp, hsync = 160, 48, 32
    vfp, vsync, vbp_min = 3, 10, 6
    htotal = w + hblank
    hperiod = (1e6 / hz - 460) / h            # us per line, estimate
    vbi = max(math.floor(460 / hperiod) + 1, vfp + vsync + vbp_min)
    vtotal = h + vbi
    clk = htotal * vtotal * hz                 # Hz
    clk10k = int(math.floor(clk / 250000) * 25)  # 0.25 MHz steps, in 10 kHz
    return dict(w=w, h=h, hb=hblank, hfp=hfp, hs=hsync, vb=vbi, vfp=vfp, vs=vsync,
                clk10k=clk10k, hz=clk10k * 1e4 / (htotal * vtotal))

def dtd(m, mm_w=286, mm_h=191):
    b = bytearray(18)
    b[0:2] = m["clk10k"].to_bytes(2, "little")
    b[2] = m["w"] & 0xff; b[3] = m["hb"] & 0xff; b[4] = ((m["w"] >> 8) << 4) | (m["hb"] >> 8)
    b[5] = m["h"] & 0xff; b[6] = m["vb"] & 0xff; b[7] = ((m["h"] >> 8) << 4) | (m["vb"] >> 8)
    b[8] = m["hfp"] & 0xff; b[9] = m["hs"] & 0xff
    b[10] = ((m["vfp"] & 0xf) << 4) | (m["vs"] & 0xf)
    b[11] = ((m["hfp"] >> 8) << 6) | ((m["hs"] >> 8) << 4) | ((m["vfp"] >> 4) << 2) | (m["vs"] >> 4)
    b[12] = mm_w & 0xff; b[13] = mm_h & 0xff; b[14] = ((mm_w >> 8) << 4) | (mm_h >> 8)
    b[17] = 0x1a  # digital separate sync, +h +v
    return b

def descriptor(tag, text=b"", data=None):
    b = bytearray(18); b[3] = tag
    if data is not None:
        b[5:5 + len(data)] = data
    else:
        t = text[:13] + (b"\n" if len(text) < 13 else b""); t = t + b" " * (13 - len(t)); b[5:18] = t
    return b

def edid(modes):
    e = bytearray(128)
    e[0:8] = bytes([0, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0])
    e[8:10] = (((ord("O") - 64) << 10) | ((ord("M") - 64) << 5) | (ord("A") - 64)).to_bytes(2, "big")
    e[10:12] = (0x0120).to_bytes(2, "little"); e[12:16] = (1).to_bytes(4, "little")
    e[16] = 43; e[17] = 36                     # week 43, 2026
    e[18], e[19] = 1, 3                        # EDID 1.3
    e[20] = 0x80; e[21] = 29; e[22] = 19; e[23] = 120; e[24] = 0x0a  # digital, 29x19 cm, gamma 2.2, RGB, preferred timing
    e[25:35] = bytes([0xee, 0x91, 0xa3, 0x54, 0x4c, 0x99, 0x26, 0x0f, 0x50, 0x54])  # sRGB-ish chromaticity
    e[35:38] = bytes([0, 0, 0])
    e[38:54] = bytes([1, 1] * 8)
    ds = [dtd(m) for m in modes[:2]]
    hz = [round(m["hz"]) for m in modes]
    ds.append(descriptor(0xfd, data=bytes([min(hz) - 1, max(hz) + 1, 30, 250, max(m["clk10k"] for m in modes) // 1000 + 1, 0, 0x0a, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20])))
    ds.append(descriptor(0xfc, b"Omarchy 120"))
    while len(ds) < 4: ds.append(descriptor(0x10, data=b""))
    for i, d in enumerate(ds[:4]): e[54 + 18 * i:72 + 18 * i] = d
    e[126] = 0
    e[127] = (-sum(e[:127])) & 0xff
    return bytes(e)

out = sys.argv[1]
specs = sys.argv[2:] or ["2160x1440@120", "2160x1440@60"]
modes = []
for s in specs:
    wh, hz = s.split("@"); w, h = wh.split("x")
    m = cvt_rb(int(w), int(h), float(hz)); modes.append(m)
    print(f"{s}: clock {m['clk10k']/100:.2f} MHz, htotal {m['w']+m['hb']}, vtotal {m['h']+m['vb']}, refresh {m['hz']:.3f} Hz")
open(out, "wb").write(edid(modes))
print(f"wrote {out}")
