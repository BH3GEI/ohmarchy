#!/bin/sh
# PID 1 of the 铠大师 Omarchy installer ISO (rdinit=/write-disk.sh on top of
# Debian's d-i initrd, booted with the linux-aarch64 7.2.12 HMV-quirk kernel).
# Brings up the NIC as 172.16.100.3/24 (the Windows-VM bridge, host 172.16.100.1)
# and writes what arrives on TCP 9000 to /dev/vda (raw; gzip with kds_gz=1):
#   on the host: tools/kaidashi/push-disk.sh IMAGE
# Progress goes to tty0 and to the serial port (the host's hwf_service vmlog).
export PATH=/sbin:/usr/sbin:/bin:/usr/bin
mount -t proc proc /proc; mount -t sysfs sys /sys; mount -t devtmpfs dev /dev 2>/dev/null
exec >/dev/console 2>&1
p() { echo "KDSINST $*"; }
p begin "$(uname -r)" "$(cat /proc/cmdline)"
case $(uname -r) in
  6.1.*) modprobe virtio_net && p modprobe virtio_net ;;   # d-i's own modules
  *) for m in failover net_failover virtio_net; do insmod /kmod/$m.ko && p insmod $m; done ;;
esac
IP=172.16.100.3 GZ=0
for a in $(cat /proc/cmdline); do
  case $a in kds_ip=*) IP=${a#kds_ip=};; kds_gz=1) GZ=1;; esac
done
sleep 2
ip link set lo up
ip link set eth0 up && ip addr add $IP/24 dev eth0 && p net eth0 $IP
ip addr show eth0 | sed 's/^/KDSINST   /'
[ -b /dev/vda ] || { p error "no /dev/vda"; ls /dev | tr '\n' ' '; }
p disk "/dev/vda $(cat /sys/block/vda/size) sectors"
# Network diagnostics every 10 s: NIC counters, virtio interrupts, a ping to the host.
(
  n=/sys/class/net/eth0/statistics
  while :; do
    p netstat "rx=$(cat $n/rx_packets) tx=$(cat $n/tx_packets) rx_drop=$(cat $n/rx_dropped) rx_err=$(cat $n/rx_errors)"
    grep -E 'virtio|eth0' /proc/interrupts | tr -s ' ' | sed 's/^/KDSINST irq /'
    ping -c 1 -W 1 172.16.100.1 >/dev/null 2>&1 && p ping-host ok || p ping-host fail
    sleep 10
  done
) &
while :; do
  p ready "listening on $IP:9000 (gzip=$GZ)"
  if [ $GZ = 1 ]; then
    nc -l -p 9000 | gunzip -c | dd of=/dev/vda bs=4M 2>/tmp/dd.err
  else
    nc -l -p 9000 | dd of=/dev/vda bs=4M 2>/tmp/dd.err
  fi
  rc=$?; sync
  p written rc=$rc "$(tail -1 /tmp/dd.err)"
  p gpt "$(dd if=/dev/vda bs=1 skip=512 count=8 2>/dev/null)"
  [ $rc = 0 ] && { p done "boot 'the installed Omarchy disk' from the GRUB menu next"; break; }
done
while :; do sh </dev/tty1 >/dev/tty1 2>&1; sleep 1; done
