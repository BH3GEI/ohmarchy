#!/bin/sh
# Read-only survey of the Oseasy VM app on a HarmonyOS PC (run as root on the device):
#   perl -e 'alarm 180; exec @ARGV' ssh ohdev sh -s < oseasy/probe.sh
# Prints the device and app versions, running VMMs and their /dev/hmv use, the
# per-app VM directories kept by vm_manager, and Oseasy's last StratoVirt config.
# Writes nothing outside /data/local/oseasy.

B=com.oseasy1.ohvm
OUT=/data/local/oseasy
mkdir -p $OUT

echo "== device"
param get const.product.model; param get const.product.software.version; param get const.ohos.fullname
uname -a

echo "== app"
bm dump -n $B 2>&1 | grep -e '"versionName"' -e '"versionCode"' -e '"vendor"' \
  -e '"appDistributionType"' -e '"installSource"' -e '"compileSdkVersion"' | sort -u

echo "== VMMs (stratovirt, vhost-device-gpu, vm_manager)"
ps -ef | grep -e stratovirt -e vhost-device -e vm_manager | grep -v grep | cut -c1-200

echo "== processes holding /dev/hmv"
ls -l /dev/hmv
for p in /proc/[0-9]*; do
  # a dead process's cmdline can block forever on HongMeng: check, then bound the read
  [ -d $p ] && ls -l $p/fd 2>/dev/null | grep -q /dev/hmv &&
    echo "${p#/proc/} $(timeout 3 tr '\0' ' ' < $p/cmdline | cut -c1-120)"
done

echo "== per-app VM directories (app id -> bundle)"
for d in /data/service/el0/virt_service/100/vm_manager/*/*; do
  echo "$d"; ls -l $d/img 2>/dev/null
done
for f in /data/service/el2/100/virt_service/vm_manager/*/$B/config/*; do
  echo "-- $f"; cat $f; echo
done

echo "== Oseasy StratoVirt starts in vmlog* (newest last)"
for f in /data/log/hwf_service/vmlog4 /data/log/hwf_service/vmlog3 /data/log/hwf_service/vmlog2 \
         /data/log/hwf_service/vmlog1 /data/log/hwf_service/vmlog; do
  [ -f $f ] && grep 'VmConfig is' $f | grep $B | cut -c1-32
done
