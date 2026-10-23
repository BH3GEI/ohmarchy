#!/usr/bin/env python3
# Run a command in a shell that is already logged in on the guest's first serial console
# (getty login as the Omarchy user, or the systemd.debug_shell root shell) and print its output.
# The command's output goes to /tmp in the guest first, so slow echo does not mix with it.
# Input is sent in small chunks: a busy guest drops serial input sent in one burst.
# usage: run.py 'COMMAND' [MAX_WAIT_SECS]   SERIAL_PORT defaults to 14321
import os,socket,sys,time,re,random
cmd=sys.argv[1]; maxw=float(sys.argv[2]) if len(sys.argv)>2 else 180
tag='Q%05d'%random.randint(0,99999)
s=socket.create_connection(('127.0.0.1',int(os.environ.get('SERIAL_PORT',14321))),timeout=0.5)
s.sendall(b'\x03'); time.sleep(3)
try:
    while s.recv(65536): pass
except socket.timeout: pass
line=('{ %s ; } > /tmp/%s.out 2>&1; echo; echo %s; cat /tmp/%s.out; echo %s\r'%(cmd,tag,tag+'B',tag,tag+'E')).encode()
for i in range(0,len(line),32):  # a busy guest drops serial input sent in one burst
    s.sendall(line[i:i+32]); time.sleep(0.05)
out=b''; end=time.time()+maxw
while time.time()<end:
    try:
        d=s.recv(65536)
        if not d: break
        out+=d
        if out.count((tag+'E').encode())>=2: break
    except socket.timeout: pass
t=out.decode(errors='replace')
t=re.sub(r'\x1b\[[0-9;?!:]*[A-Za-z~]|\x1b\][^\x07\x1b]*(\x07|\x1b\\)|\x1b[78=>]','',t).replace('\r','')
m=re.findall(tag+r'B\n(.*?)'+tag+'E',t,re.S)
print(m[-1] if m else '[no result]\n'+t[-800:])
