#!/usr/bin/env bash
# Install + launch the Route J loader HAP (busybox-as-signed-.so) and capture the JLOADER
# hilog (busybox sh output). Takes screen.lock (launch foregrounds); keeps it for hand-off.
set -uo pipefail
. "$(dirname "$0")/config.sh"
HAP=${1:?signed jloader.hap}
to 150 ssh -o ConnectTimeout=20 "$OHDEV" 'cat > /data/local/tmp/jloader.hap' < "$HAP"
"$(dirname "$0")/ohsh" -t 120 - <<'SH'
set -u
B=com.ohmarchy.jloader
if [ ! -d /data/local/screen.lock ]; then
  mkdir /data/local/screen.lock && printf 'agent-c6 (Route J loader)\npurpose: run busybox-as-.so ~8s\nexpected end: <=1min\n' > /data/local/screen.lock/owner
fi
cat /data/local/screen.lock/owner | head -1
bm install -r -p /data/local/tmp/jloader.hap 2>&1 | tail -1
aa force-stop $B >/dev/null 2>&1; hilog -r >/dev/null 2>&1 || true
aa start -a EntryAbility -b $B >/dev/null 2>&1; sleep 7
echo "== JLOADER output:"; hilog -x 2>/dev/null | grep -aE 'JLOADER' | sed -E 's/.*JLOADER: //'
aa force-stop $B >/dev/null 2>&1
SH
