#!/usr/bin/env python3
# Grab one frame from a VNC server (RFB 3.8, no auth, raw encoding) and save it as PNG.
# usage: vncshot.py HOST PORT OUT.png   (route F: hdc fport tcp:15901 tcp:5901, then 127.0.0.1 15901)
import socket, struct, sys, zlib
host, port, out = sys.argv[1], int(sys.argv[2]), sys.argv[3]
s = socket.create_connection((host, port), timeout=20)
def rx(n):
    b = b''
    while len(b) < n:
        c = s.recv(n - len(b))
        if not c: raise EOFError
        b += c
    return b
rx(12); s.sendall(b'RFB 003.008\n')
n = rx(1)[0]; types = rx(n)
if 1 not in types: sys.exit('no None auth: %r' % types)
s.sendall(b'\x01'); assert struct.unpack('>I', rx(4))[0] == 0
s.sendall(b'\x01')  # shared
w, h = struct.unpack('>HH', rx(4)); rx(16); nl = struct.unpack('>I', rx(4))[0]; name = rx(nl)
# 32bpp little-endian BGRX
s.sendall(struct.pack('>BxxxBBBBHHHBBBxxx', 0, 32, 24, 0, 1, 255, 255, 255, 16, 8, 0))
s.sendall(struct.pack('>BxH i', 2, 1, 0))
s.sendall(struct.pack('>BBHHHH', 3, 0, 0, 0, w, h))
fb = bytearray(w * h * 4); got = 0
while True:
    t = rx(1)[0]
    if t != 0:
        if t == 2: continue
        if t == 3: rx(3); rx(struct.unpack('>I', rx(4))[0]); continue
        sys.exit('msg %d' % t)
    rx(1); nr = struct.unpack('>H', rx(2))[0]
    for _ in range(nr):
        x, y, rw, rh, enc = struct.unpack('>HHHHi', rx(12))
        if enc == -223:  # DesktopSize
            w, h = rw, rh; fb = bytearray(w * h * 4); s.sendall(struct.pack('>BBHHHH', 3, 0, 0, 0, w, h)); continue
        data = rx(rw * rh * 4)
        for r in range(rh):
            o = ((y + r) * w + x) * 4; fb[o:o + rw * 4] = data[r * rw * 4:(r + 1) * rw * 4]
    break
raw = b''.join(b'\0' + bytes(c for i in range(w) for c in (fb[(y*w+i)*4+2], fb[(y*w+i)*4+1], fb[(y*w+i)*4])) for y in range(h))
def chunk(t, d): return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d))
open(out, 'wb').write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b''))
print(w, h, name.decode(errors='replace'))
