#!/usr/bin/env bash
# Install + run the XPM probe HAP once under screen.lock, capturing app-side (XPMPROBE
# hilog) AND kernel-side (new dmesg avc/xpm for the probe's pid) evidence. Read-only wrt
# other sessions; takes screen.lock because launching the ability foregrounds a window.
set -uo pipefail
. "$(dirname "$0")/../config.sh"
HAP=${1:?path to signed xpmprobe.hap}
to 120 ssh -o ConnectTimeout=20 "$OHDEV" 'cat > /data/local/tmp/xpmprobe.hap' < "$HAP"
"$(dirname "$0")/../ohsh" -t 140 - <<'SH'
set -u
if mkdir /data/local/screen.lock 2>/dev/null; then
  printf 'agent-c6 (Route J XPM probe)\npurpose: install+run com.ohmarchy.xpmprobe ~8s, read hilog+dmesg\nexpected end: <= 1 min\n' > /data/local/screen.lock/owner
else echo "screen.lock HELD:"; cat /data/local/screen.lock/owner; exit 3; fi
trap 'rm -rf /data/local/screen.lock' EXIT
B=com.ohmarchy.xpmprobe
bm install -r -p /data/local/tmp/xpmprobe.hap 2>&1 | tail -1
aa force-stop $B >/dev/null 2>&1 || true
hilog -r >/dev/null 2>&1 || true
MARK=$(dmesg 2>/dev/null | tail -1 | tr -cd '0-9.' | head -c 14)   # last dmesg ts before launch
echo "== launch (dmesg mark=$MARK)"; aa start -a EntryAbility -b $B 2>&1 | tail -1
sleep 7
echo "== APP-side XPMPROBE results:"
hilog -x 2>/dev/null | grep -aE 'XPMPROBE' | sed -E 's/.*XPMPROBE: //' | tail -40
echo "== KERNEL-side new avc/xpm for the probe (post-launch):"
PID=$(pidof $B 2>/dev/null)
dmesg 2>/dev/null | grep -aiE 'avc|xpm|exec' | grep -aiE "xpmprobe|${PID:-NOPID}|execmem|execmod|debug_hap" | tail -25
aa force-stop $B >/dev/null 2>&1 || true
SH
