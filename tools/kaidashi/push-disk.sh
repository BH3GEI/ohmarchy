#!/bin/sh
# Stream a disk image into the 铠大师 installer (write-disk.sh) from the
# HarmonyOS host. Run as root on the device:
#   perl -e 'alarm 3600; exec @ARGV' ssh ohdev sh -s IMAGE [GUEST_IP] < tools/kaidashi/push-disk.sh
# IMAGE is a raw disk (sent as is: the VM's disk has detect-zeroes=unmap, so the
# zero runs stay sparse in vm.qcow2) or a .gz.
img=${1:?image}; ip=${2:-172.16.100.3}
[ -r "$img" ] || { echo "no $img"; exit 1; }
echo "sending $img ($(ls -l "$img" | awk '{print $5}') bytes) to $ip:9000"
start=$(toybox date +%s)
toybox nc -q 5 $ip 9000 < "$img" || toybox nc $ip 9000 < "$img"
echo "nc rc=$? after $(( $(toybox date +%s) - start )) s"
