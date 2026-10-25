#!/usr/bin/env bash
# Step 1c: (f) dlopen an unsigned .so in the sandbox; (g) execve an ELF packed into the HAP
# libs/ (libexit42.so, signed with the HAP). Decides the ".so trick" and the "bundle the
# userspace into the HAP at build time" variants of route J.
set -uo pipefail
. "$(dirname "$0")/../config.sh"
HAP=${1:?signed xpmprobe.hap}; D=$(dirname "$0")
to 120 ssh -o ConnectTimeout=20 "$OHDEV" 'cat > /data/local/tmp/xpmprobe.hap' < "$HAP"
to 90 ssh -o ConnectTimeout=20 "$OHDEV" 'cat > /data/local/tmp/libprobe.so' < "$D/bin/libprobe.so"
"$(dirname "$0")/../ohsh" -t 150 - <<'SH'
set -u
B=com.ohmarchy.xpmprobe; SB=/data/app/el2/100/base/$B/haps/entry/files
bm install -r -p /data/local/tmp/xpmprobe.hap 2>&1 | tail -1
mkdir -p "$SB"; cp -f /data/local/tmp/libprobe.so "$SB/libprobe.so"
chmod 755 "$SB/libprobe.so"; chown 20020169:20020169 "$SB/libprobe.so"; chcon u:object_r:debug_hap_data_file:s0 "$SB/libprobe.so"
echo "sandbox .so:"; ls -lnZ "$SB/libprobe.so" 2>/dev/null | awk '{print $1,$NF}'
echo "HAP-libs ELF present:"; ls -lnZ /data/app/el1/bundle/public/$B/libs/arm64/libexit42.so 2>/dev/null | awk '{print $1,$NF}' || echo "(check install path)"
aa force-stop $B >/dev/null 2>&1; hilog -r >/dev/null 2>&1 || true
aa start -a EntryAbility -b $B >/dev/null 2>&1; sleep 6
echo "== (d/f/g) results:"; hilog -x 2>/dev/null | grep -aE 'XPMPROBE' | grep -aiE '\((d|f|g)\)' | sed -E 's/.*XPMPROBE: //'
aa force-stop $B >/dev/null 2>&1
SH
