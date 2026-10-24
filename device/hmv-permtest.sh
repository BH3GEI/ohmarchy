#!/usr/bin/env bash
# Route H HMV permission test — the decisive piece of the acceleration investigation.
# RUN ONLY with /data/local/vm.lock held and the 鸿融 main VM stopped (no stratovirt running).
# Answers: can a NON-system binary (su domain, /data path, no ohsw_stratovirt_exec label)
# create an HMV VM, or does a domain/label/signature gate restrict it to the system VMM?
#
# agent-2a showed the SYSTEM stratovirt (/system/..., labeled ohsw_stratovirt_exec) boots a
# VM on HMV from a root shell (hongrong/pure/testvm.sh). Launching a labeled binary may
# transition into the ohsw_stratovirt domain, so that does not prove the su domain can do it.
# This isolates path/label by (B) running a /data COPY of stratovirt (label lost -> su domain).
set -uo pipefail
. "$(dirname "$0")/config.sh"
"$(dirname "$0")/ohsh" -t 180 - <<'SH'
set -u
echo "== preconditions"
[ -d /data/local/vm.lock ] || { echo "FAIL: /data/local/vm.lock not held"; exit 1; }
pidof stratovirt >/dev/null 2>&1 && { echo "FAIL: a stratovirt is running (鸿融?)"; exit 1; }
echo "lock held, no stratovirt running; caller domain: $(cat /proc/self/attr/current 2>/dev/null)"

R=/data/local/tmp/routeh
echo
echo "== experiment A: own probe (su domain, /data, no label) opens /dev/hmv and tries create-VM ioctl"
if [ -x $R/hmvcreate ]; then $R/hmvcreate /dev/hmv; else echo "SKIP: $R/hmvcreate not pushed"; fi

echo
echo "== experiment B: /data COPY of stratovirt (exec label lost -> stays su domain) tries accel=hmv"
SV=/system/bin/virt_service/vm_engine/stratovirt/stratovirt
FW=/system/opt/virt_service/virtualized_hwf/stratovirt-uefi-linux
cp -f $SV $R/stratovirt-copy 2>/dev/null && chmod 755 $R/stratovirt-copy || { echo "copy failed"; }
echo "copy label: $(ls -Z $R/stratovirt-copy 2>/dev/null | awk '{print $1}')"
# minimal HMV machine, no disk/net; it will fail later, but the HMV VM/vCPU creation is what we test.
nohup $R/stratovirt-copy -machine virt,gic-version=3,mem-share=on,accel=hmv \
  -cpu host -smp 1 -m 512 -qmp unix:$R/copy.qmp,server,nowait \
  -D $R/copy.log -disable-seccomp > $R/copy.stdout 2>&1 &
cp=$!; sleep 3
echo "copy pid $cp domain: $(cat /proc/$cp/attr/current 2>/dev/null || echo '(exited)')"
echo "-- copy.log (HMV init / errors):"
grep -iE 'hmv|accel|permission|denied|EPERM|EACCES|vcpu.*running|failed to|create' $R/copy.log $R/copy.stdout 2>/dev/null | head -20
kill $cp 2>/dev/null; sleep 1; kill -9 $cp 2>/dev/null
rm -f $R/stratovirt-copy $R/copy.qmp
echo
echo "== reference: the system VMM's domain is ohsw_stratovirt (labeled exec)."
echo "Interpretation: if A or B creates a VM -> any root code can use HMV (accel feasible);"
echo "if both are blocked (EPERM/EACCES) while the labeled binary works -> domain/label gate."
SH
