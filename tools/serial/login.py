#!/usr/bin/env python3
# Log in on the guest's first serial console (getty on ttyAMA0), waiting for each prompt;
# under TCG every prompt can take 20-60 s. Leaves the shell logged in for run.py.
# usage: login.py USER PASSWORD   SERIAL_PORT defaults to 14321; exit 0 when a shell prompt shows
import os, re, socket, sys, time

user, password = sys.argv[1], sys.argv[2]
s = socket.create_connection(('127.0.0.1', int(os.environ.get('SERIAL_PORT', 14321))), timeout=0.5)
raw = b''
ANSI = r'\x1b\[[0-9;?!:]*[A-Za-z~]|\x1b\][^\x07\x1b]*(\x07|\x1b\\)|\x1bP[^\x1b]*\x1b\\|\x1b[78=>]'


def tail():  # strip escapes over the whole buffer: sequences can span reads
    return re.sub(ANSI, '', raw.decode(errors='replace'))[-300:]


def expect(pattern, secs):
    global raw
    end = time.time() + secs
    while time.time() < end:
        try:
            d = s.recv(65536)
        except socket.timeout:
            d = None
        if d == b'':
            sys.exit('serial port closed')
        if d:
            raw += d
            if re.search(pattern, tail()):
                return True
    return False


PROMPT = r'[❯$#][^\n]{0,12}$'
s.sendall(b'\x03\r')
if not expect(r'login: *$|' + PROMPT, 120):
    sys.exit('no login prompt or shell on the serial console')
if re.search(PROMPT, tail()):
    print('already logged in'); sys.exit(0)
raw = b''; s.sendall(user.encode() + b'\r')
if not expect(r'[Pp]assword: *$', 120):
    sys.exit('no password prompt')
raw = b''; s.sendall(password.encode() + b'\r')
if not expect(PROMPT, 180):
    sys.exit('login failed: ' + tail()[-200:].strip())
print('logged in')
