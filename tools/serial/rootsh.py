#!/usr/bin/env python3
# Run a command in a root shell on the guest's first serial console (systemd.debug_shell=ttyAMA0).
# usage: rootsh.py 'COMMAND' [WAIT_SECS]   SERIAL_PORT defaults to 14321
import os, socket, sys, time, re
cmd = sys.argv[1]; wait = float(sys.argv[2]) if len(sys.argv) > 2 else 15
s = socket.create_connection(('127.0.0.1', int(os.environ.get('SERIAL_PORT', 14321))), timeout=0.5)
s.sendall(b'\x03'); time.sleep(1)
try:
    while s.recv(65536): pass
except socket.timeout: pass
s.sendall(("echo @@B; " + cmd + "; echo @@E\r").encode())
out = b''; end = time.time() + wait
while time.time() < end:
    try:
        d = s.recv(65536)
        if not d: break
        out += d
        if b'\n@@E' in out or b'\r@@E' in out: break
    except socket.timeout: pass
t = out.decode(errors='replace')
t = re.sub(r'\x1b\[[0-9;?!]*[A-Za-z~]|\x1b\][^\x07]*\x07|\x1b[78=>]', '', t).replace('\r', '')
i = t.find('\n@@B'); j = t.rfind('\n@@E')
print(t[i+4:j] if i >= 0 and j > i else t[-3000:])
