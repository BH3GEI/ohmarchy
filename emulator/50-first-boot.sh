#!/usr/bin/env bash
# Answer Omarchy's tty1 first-boot wizard over VNC (no HarmonyOS IME involved).
# usage: 50-first-boot.sh USER PASSWORD
# Waits for the boot (serial getty), then: keyboard English (US), USER, PASSWORD twice,
# git name/email skipped, hostname omarchy, timezone default, confirm.
# The setup that follows takes about 50 minutes under TCG; 60-desktop.sh waits for it.
set -euo pipefail
. "$(dirname "$0")/config.sh"
U=$1 P=$2
VK="python3 -I $ROOT/tools/vnc/vnckey.py 127.0.0.1 15901"
export VNCKEY_DELAY=0.3

echo "waiting for the guest to boot (serial login prompt)..."
python3 -I - <<'EOF'
import socket, time
end = time.time() + 1800
while time.time() < end:
    try:
        s = socket.create_connection(('127.0.0.1', 14321), timeout=1)
        buf = b''; t = time.time()
        s.sendall(b'\r')
        while time.time() - t < 20:
            try: buf += s.recv(65536)
            except socket.timeout: pass
            if b'login:' in buf: raise SystemExit(0)
        s.close()
    except OSError:
        time.sleep(5)
raise SystemExit('guest did not reach the login prompt')
EOF
sleep 20
$VK '{Return}'; sleep 20                       # Press Return to Start Setup
$VK '{Return}'; sleep 15                       # English (US)
$VK "$U" '{sleep:2}' '{Return}'; sleep 15
$VK "$P" '{sleep:2}' '{Return}'; sleep 15
$VK "$P" '{sleep:2}' '{Return}'; sleep 15
$VK '{Return}'; sleep 12                       # full name: skip
$VK '{Return}'; sleep 12                       # email: skip
$VK '{Return}'; sleep 15                       # hostname: omarchy
$VK '{Return}'; sleep 40                       # timezone: default
python3 -I "$ROOT/tools/vnc/vncshot.py" 127.0.0.1 15901 "$WORK/wizard-summary.png"
$VK '{Return}'                                 # Does this look right? Yes
echo "wizard answered (summary: $WORK/wizard-summary.png); setup runs now, then emulator/60-desktop.sh $U PASSWORD"
