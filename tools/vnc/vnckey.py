#!/usr/bin/env python3
# Send keystrokes to a VNC server (RFB 3.8, no auth); no IME on the HarmonyOS side is involved.
# usage: vnckey.py HOST PORT ITEM...   ITEM = text | {Return} | {Tab} | {Down} | {Up} | {BackSpace} | {Escape} | {sleep:SECS}
import socket, struct, sys, time, re
host, port = sys.argv[1], int(sys.argv[2])
s = socket.create_connection((host, port), timeout=20)
def rx(n):
    b = b''
    while len(b) < n:
        c = s.recv(n - len(b))
        if not c: raise EOFError
        b += c
    return b
rx(12); s.sendall(b'RFB 003.008\n'); n = rx(1)[0]; rx(n); s.sendall(b'\x01'); rx(4); s.sendall(b'\x01')
rx(20); rx(struct.unpack('>I', rx(4))[0])
NAMED = {'Return': 0xff0d, 'Tab': 0xff09, 'BackSpace': 0xff08, 'Escape': 0xff1b, 'Up': 0xff52,
         'Down': 0xff54, 'Left': 0xff51, 'Right': 0xff53, 'space': 0x20, 'Delete': 0xffff}
SHIFTED = '~!@#$%^&*()_+{}|:"<>?ABCDEFGHIJKLMNOPQRSTUVWXYZ'
def key(sym, shift=False):
    if shift: s.sendall(struct.pack('>BBxxI', 4, 1, 0xffe1))
    s.sendall(struct.pack('>BBxxI', 4, 1, sym)); time.sleep(0.04)
    s.sendall(struct.pack('>BBxxI', 4, 0, sym))
    if shift: s.sendall(struct.pack('>BBxxI', 4, 0, 0xffe1))
    time.sleep(0.06)
for item in sys.argv[3:]:
    for tok in re.findall(r'\{[^}]+\}|[^{]+', item):
        if tok.startswith('{'):
            name = tok[1:-1]
            if name.startswith('sleep:'): time.sleep(float(name[6:])); continue
            key(NAMED[name])
        else:
            for ch in tok: key(ord(ch), ch in SHIFTED)
time.sleep(0.3); s.close()
