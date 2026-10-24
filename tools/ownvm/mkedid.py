#!/usr/bin/env python3
"""Write an EDID 1.4 block for the guest's virtio-gpu connector with 120 Hz modes.

The host's vhost-device-gpu reports a 60 Hz EDID; the guest overrides it with
  drm.edid_firmware=Virtual-1:edid/ohmarchy-120.bin
(CONFIG_DRM_LOAD_EDID_FIRMWARE=y in linux-aarch64 7.2.12). Timings are CVT
reduced blanking v2 (80-pixel horizontal blank, >= 460 us vertical blank).
  tools/ownvm/mkedid.py OUT.bin
"""
import math, struct, sys

def cvt_rb2(w, h, hz):
    hblank, vfront, vsync, vback_min = 80, 1, 8, 6
    vblank_lines = max(math.ceil(460e-6 * hz * h / (1 - 460e-6 * hz)), vfront + vsync + vback_min)
    vtotal = h + vblank_lines
    htotal = w + hblank
    clk_khz = math.ceil(htotal * vtotal * hz / 1000)
    return dict(w=w, h=h, hb=hblank, hfp=8, hs=32, vb=vblank_lines, vfp=vfront, vs=vsync, clk=clk_khz)

def dtd(t, mm_w=294, mm_h=196):
    c = t['clk'] // 10                      # 10 kHz units
    assert c < 65536, "pixel clock too high for a DTD"
    b = struct.pack('<H', c)
    b += bytes([t['w'] & 0xff, t['hb'] & 0xff, ((t['w'] >> 8) << 4) | (t['hb'] >> 8)])
    b += bytes([t['h'] & 0xff, t['vb'] & 0xff, ((t['h'] >> 8) << 4) | (t['vb'] >> 8)])
    b += bytes([t['hfp'] & 0xff, t['hs'] & 0xff, ((t['vfp'] & 0xf) << 4) | (t['vs'] & 0xf),
                ((t['hfp'] >> 8) << 6) | ((t['hs'] >> 8) << 4) | ((t['vfp'] >> 4) << 2) | (t['vs'] >> 4)])
    b += bytes([mm_w & 0xff, mm_h & 0xff, ((mm_w >> 8) << 4) | (mm_h >> 8), 0, 0])
    b += bytes([0x1a])                      # digital separate sync, +h +v
    return b

def text(tag, s):
    s = s.encode()[:13]
    return bytes([0, 0, 0, tag, 0]) + s + (b'\n' + b' ' * 12)[:13 - len(s)]

def range_limits(vmin, vmax, hmin_khz, hmax_khz, max_clk_mhz):
    return bytes([0, 0, 0, 0xfd, 0, vmin, vmax, hmin_khz, hmax_khz, math.ceil(max_clk_mhz / 10), 0x01]) + b'\n' + b' ' * 6

modes = [cvt_rb2(2160, 1440, 120), cvt_rb2(1920, 1280, 120), cvt_rb2(2160, 1440, 60)]
e = bytearray(b'\x00\xff\xff\xff\xff\xff\xff\x00')
e += struct.pack('>H', (ord('O') - 64) << 10 | (ord('H') - 64) << 5 | (ord('M') - 64))  # vendor "OHM"
e += struct.pack('<HI', 0x0120, 1) + bytes([1, 36])      # product, serial, week 1, year 2026
e += bytes([1, 4])                                         # EDID 1.4
e += bytes([0xa5, 29, 20, 0x78, 0x02])                     # digital 8 bpc DP, 29x20 cm, gamma 2.2, preferred = DTD 1, continuous
e += bytes([0xee, 0x91, 0xa3, 0x54, 0x4c, 0x99, 0x26, 0x0f, 0x50, 0x54])  # sRGB-ish chromaticity
e += bytes([0, 0, 0]) + b'\x01\x01' * 8                     # no established/standard timings
e += dtd(modes[0]) + dtd(modes[1])
e += range_limits(48, 120, 30, 200, max(m['clk'] for m in modes) / 1000)
e += text(0xfc, 'OHMARCHY 120')
e += bytes([0])                                            # no extensions
e += bytes([(-sum(e)) & 0xff])
assert len(e) == 128
open(sys.argv[1], 'wb').write(e)
for m in modes:
    htot, vtot = m['w'] + m['hb'], m['h'] + m['vb']
    print(f"{m['w']}x{m['h']} @ {m['clk']*1000/htot/vtot:.3f} Hz, clock {m['clk']/1000:.1f} MHz")
