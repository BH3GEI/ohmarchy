#!/usr/bin/env python3
# Drive the guest's first serial console (UEFI/Limine menu, getty) and render the ANSI screen.
# usage: limine.py ITEM...   ITEM = keys with python escapes, optionally prefixed "@SECS:" (wait after sending)
# e.g. limine.py "@2:e" (edit entry)   limine.py "@3:\x18" (Ctrl-X: boot)   SERIAL_PORT defaults to 14321
import os, socket, sys, time, re
W, H = 100, 30
scr = [[' '] * W for _ in range(H)]; cy = cx = 0
def feed(b):
    global cy, cx
    i = 0; t = b.decode('latin1')
    while i < len(t):
        c = t[i]
        if c == '\x1b' and i + 1 < len(t) and t[i+1] == '[':
            m = re.match(r'\x1b\[([0-9;?]*)([A-Za-z])', t[i:])
            if not m: i += 1; continue
            p, f = m.group(1), m.group(2); i += m.end()
            n = [int(x) if x.isdigit() else 0 for x in p.replace('?', '').split(';')] if p else []
            if f in 'Hf': cy = max((n[0] if n else 1) - 1, 0); cx = max((n[1] if len(n) > 1 else 1) - 1, 0)
            elif f == 'J': 
                for r in range(H): scr[r] = [' '] * W
            elif f == 'K': scr[min(cy,H-1)][cx:] = [' '] * (W - cx)
            elif f == 'A': cy = max(cy - (n[0] or 1), 0)
            elif f == 'B': cy = min(cy + (n[0] or 1), H - 1)
            elif f == 'C': cx = min(cx + (n[0] or 1), W - 1)
            elif f == 'D': cx = max(cx - (n[0] or 1), 0)
            continue
        if c == '\x1b': i += 2; continue
        if c == '\r': cx = 0
        elif c == '\n':
            cy += 1
            if cy >= H: scr.pop(0); scr.append([' '] * W); cy = H - 1
        elif c == '\b': cx = max(cx - 1, 0)
        elif c >= ' ':
            if cx < W and cy < H: scr[cy][cx] = c
            cx += 1
        i += 1
s = socket.create_connection(('127.0.0.1', int(os.environ.get('SERIAL_PORT', 14321))), timeout=0.3)
buf = b''
def drain(w):
    global buf
    end = time.time() + w
    while time.time() < end:
        try:
            d = s.recv(65536)
            if not d: break
            buf += d
        except socket.timeout: pass
for a in sys.argv[1:]:
    w = 1.5
    if a.startswith('@'): w, a = float(a[1:].split(':', 1)[0]), a.split(':', 1)[1]
    s.sendall(a.encode().decode('unicode_escape').encode('latin1')); drain(w)
feed(buf)
print('\n'.join(''.join(r).rstrip() for r in scr).strip('\n'))
