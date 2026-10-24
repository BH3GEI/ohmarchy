#!/bin/sh
# Read-only survey of the 铠大师 VM app (com.sanway.ecoengine) on a HarmonyOS PC.
# Run as root on the device:
#   perl -e 'alarm 180; exec @ARGV' ssh ohdev sh -s < tools/kaidashi/probe.sh
# Prints device and app versions (鸿融's too, to catch AppGallery auto-updates),
# running VMMs and their /dev/hmv use, the vm_manager per-app VM directories,
# and any StratoVirt start of 铠大师 in the hwf_service logs. Writes nothing.

B=com.sanway.ecoengine

echo "== device"
param get const.product.model; param get const.product.software.version
uname -a

echo "== apps"
for b in $B com.huawei.medivh com.oseasy1.ohvm; do
  echo "-- $b"
  bm dump -n $b 2>&1 | grep -e '"versionName"' -e '"versionCode"' -e '"vendor"' \
    -e '"appDistributionType"' -e '"installSource"' -e '"compileSdkVersion"' | sort -u
done
ls -l /data/app/el1/bundle/public/$B/

echo "== VMMs"
ps -ef | grep -e stratovirt -e vhost-device -e vm_manager -e $B | grep -v grep | cut -c1-240
echo "-- processes holding /dev/hmv"
ls -l /dev/hmv
for p in /proc/[0-9]*; do
  ls -l $p/fd 2>/dev/null | grep -q /dev/hmv && echo "${p#/proc/} $(tr '\0' ' ' < $p/cmdline | cut -c1-160)"
done

echo "== vm_manager per-app VM directories"
for d in /data/service/el0/virt_service/100/vm_manager/*/*; do echo "$d"; ls -l $d/img 2>/dev/null; done
for d in /data/service/el2/100/virt_service/vm_manager/*/*; do echo "$d"; ls $d $d/config 2>/dev/null; done

echo "== 铠大师 app data"
find /data/app/el2/100/base/$B -maxdepth 3 | head -40

echo "== StratoVirt starts for $B in vmlog*"
for f in /data/log/hwf_service/vmlog4 /data/log/hwf_service/vmlog3 /data/log/hwf_service/vmlog2 \
         /data/log/hwf_service/vmlog1 /data/log/hwf_service/vmlog; do
  [ -f $f ] && grep -c $B $f | sed "s|^|$f: |"
done

echo "== VM lock"
ls -ld /data/local/vm.lock 2>&1 && cat /data/local/vm.lock/owner 2>/dev/null
