#!/usr/bin/env bash
# One-shot: take screen.lock, launch the VM-API probe HAP (create-only), capture BOTH the
# app-side VMPROBE verdict and the vm_manager SERVICE-side decision, then release the lock.
set -uo pipefail
. "$(dirname "$0")/../config.sh"
"$(dirname "$0")/../ohsh" -t 140 - <<'SH'
set -u
if mkdir /data/local/screen.lock 2>/dev/null; then
  printf 'vmapi-probe (agent-c6)\npurpose: launch VM-API probe HAP ~8s, read app+service hilog\nexpected end: <= 1 min\n' > /data/local/screen.lock/owner
else
  echo "screen.lock HELD, aborting:"; cat /data/local/screen.lock/owner 2>/dev/null; exit 3
fi
trap 'rm -rf /data/local/screen.lock' EXIT
B=com.ohmarchy.vmtest
aa force-stop $B >/dev/null 2>&1 || true
hilog -r >/dev/null 2>&1 || true
echo "== launch"; aa start -a EntryAbility -b $B 2>&1 | tail -1
sleep 8
echo "== APP-side (A0BEEF/VMPROBE):"
hilog -x 2>/dev/null | grep -aE 'A0BEEF' | tail -16
echo "== SERVICE-side (vm_manager / virt_service / VM caller checks):"
hilog -x 2>/dev/null | grep -aiE 'vm_manager|virt_service|VmManager|libvm|GetAppId|caller identit|UNTRUST|not permit|permission denied|validation fail|createVm|authoriz|appid' | tail -40
aa force-stop $B >/dev/null 2>&1 || true
SH
