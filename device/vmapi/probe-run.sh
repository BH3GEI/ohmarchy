#!/usr/bin/env bash
# One-shot: take screen.lock briefly, launch the VM-API probe HAP so its EntryAbility.onCreate
# calls virtualization.createVm as a debug-signed third-party app, capture the hilog verdict,
# then force-stop and release the lock. No VM is booted (create-only), so no vm.lock needed.
set -uo pipefail
. "$(dirname "$0")/../config.sh"
"$(dirname "$0")/../ohsh" -t 120 - <<'SH'
set -u
# take screen.lock (owner note)
if mkdir /data/local/screen.lock 2>/dev/null; then
  printf 'vmapi-probe (agent-c6)\nstart: %s\npurpose: launch VM-API probe HAP ~5s, read hilog\nexpected end: <= 1 min\n' "$(date)" > /data/local/screen.lock/owner
else
  echo "screen.lock HELD, aborting:"; cat /data/local/screen.lock/owner 2>/dev/null; exit 3
fi
trap 'rm -rf /data/local/screen.lock' EXIT

B=com.ohmarchy.vmtest
hilog -r >/dev/null 2>&1 || true          # clear buffer
aa force-stop $B >/dev/null 2>&1 || true
echo "== launching probe ability"
aa start -a EntryAbility -b $B 2>&1 | tail -2
sleep 6
echo "== VMPROBE hilog + any virt-service rejection:"
hilog -x 2>/dev/null | grep -iE 'VMPROBE|virtualization|vmManager|virt_service|UNTRUSTED|caller|denied|permission|0xBEEF|BEEF' | tail -60
echo "== (broader) any hilog lines mentioning the bundle or vm service in last capture:"
hilog -x 2>/dev/null | grep -iE 'com.ohmarchy.vmtest|vm_manager|libvm|VmManager' | tail -30
aa force-stop $B >/dev/null 2>&1 || true
SH
