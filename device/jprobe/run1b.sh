#!/usr/bin/env bash
# Step 1b: can the HAP execve an unsigned ELF dropped in its own sandbox? Pushes a tiny
# static exit(42) ELF (and a dynamic one) into the sandbox, launches the probe, captures
# the unambiguous result (exit 42 = executed; 120+N = execve failed with errno N&7) + AVC.
set -uo pipefail
. "$(dirname "$0")/../config.sh"
HAP=${1:?signed xpmprobe.hap}; D=$(dirname "$0")
to 120 ssh -o ConnectTimeout=20 "$OHDEV" 'cat > /data/local/tmp/xpmprobe.hap' < "$HAP"
to 90 ssh -o ConnectTimeout=20 "$OHDEV" 'cat > /data/local/tmp/exit42' < "$D/bin/exit42"
to 90 ssh -o ConnectTimeout=20 "$OHDEV" 'cat > /data/local/tmp/exit42dyn' < "$D/bin/exit42dyn"
"$(dirname "$0")/../ohsh" -t 150 - <<'SH'
set -u
B=com.ohmarchy.xpmprobe
SB=/data/app/el2/100/base/$B/haps/entry/files
if [ ! -d /data/local/screen.lock ]; then
  mkdir /data/local/screen.lock && printf 'agent-c6 (Route J step 1b)\npurpose: sandbox-execve test ~8s\nexpected end: <=1min\n' > /data/local/screen.lock/owner
fi
cat /data/local/screen.lock/owner | head -1
bm install -r -p /data/local/tmp/xpmprobe.hap 2>&1 | tail -1
mkdir -p "$SB"
for f in exit42 exit42dyn; do
  cp -f /data/local/tmp/$f "$SB/$f" && chmod 755 "$SB/$f" && chown 20020169:20020169 "$SB/$f" && chcon u:object_r:debug_hap_data_file:s0 "$SB/$f"
done
echo "sandbox ELFs:"; ls -lnZ "$SB/exit42" "$SB/exit42dyn" 2>/dev/null | awk '{print $1,$5,$NF}'
aa force-stop $B >/dev/null 2>&1; hilog -r >/dev/null 2>&1 || true
aa start -a EntryAbility -b $B >/dev/null 2>&1; sleep 6
echo "== (e) results:"; hilog -x 2>/dev/null | grep -aE 'XPMPROBE' | grep -aiE '\(e\)' | sed -E 's/.*XPMPROBE: //'
echo "== execute/XPM avc for the sandbox ELFs:"
dmesg 2>/dev/null | grep -aiE 'avc.*execut|xpm|hmdec|hmencaps' | grep -aiE 'xpmprobe|exit42|debug_hap_data|WRITABLE_CODE' | tail -12
aa force-stop $B >/dev/null 2>&1
SH
