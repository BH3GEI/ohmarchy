#!/bin/sh
# PID 1 of the 铠大师 Omarchy installer ISO (rdinit=/write-disk.sh on top of
# Debian's d-i initrd, booted with the linux-aarch64 7.2.12 HMV-quirk kernel).
# Brings up the NIC as 172.16.100.3/24 (the Windows-VM bridge, host 172.16.100.1)
# and writes what arrives on TCP 9000 to /dev/vda (raw; gzip with kds_gz=1):
#   on the host: tools/kaidashi/push-disk.sh IMAGE
# With kds_src=virtiofs it instead mounts the VM's virtiofs share (tag
# shared_dir: the host's 文档 folder, which 铠大师 always exports) and writes
# ohmarchy-kds-disk.img or ohmarchy-kds-disk.img.gz from there.
# Progress goes to tty0 and to the serial port (the host's hwf_service vmlog).
export PATH=/sbin:/usr/sbin:/bin:/usr/bin
mount -t proc proc /proc; mount -t sysfs sys /sys; mount -t devtmpfs dev /dev 2>/dev/null
exec >/dev/console 2>&1
p() { echo "KDSINST $*"; }
# After a whole-disk write: put route B's vmwgfx-oseasy module and options into
# the Omarchy root (vda2) and rebuild its initramfs from inside, as route B's
# probe.install does (oseasy/probe/init): otherwise mkinitcpio's kms hook packs
# the in-tree vmwgfx, which crashes early on this device.
prep_root() {
  [ -f /kds/vmwgfx.ko ] || { p prep "no vmwgfx.ko on the ISO, skipped"; return; }
  blockdev --rereadpt /dev/vda; sleep 2
  mkdir -p /root2
  mount -t ext4 /dev/vda2 /root2 || { p prep "cannot mount /dev/vda2"; return; }
  kv=$(ls /root2/usr/lib/modules | grep -x "$(uname -r)" | head -1)
  [ -n "$kv" ] || kv=$(ls /root2/usr/lib/modules | head -1)
  mkdir -p /root2/usr/lib/modules/$kv/updates /root2/etc/modprobe.d
  cp /kds/vmwgfx.ko /root2/usr/lib/modules/$kv/updates/vmwgfx.ko
  cp /kds/vmwgfx-oseasy.conf /root2/etc/modprobe.d/vmwgfx-oseasy.conf
  for d in proc sys dev; do mount --bind /$d /root2/$d; done
  chroot /root2 /usr/bin/depmod $kv; p prep "depmod $kv rc=$?"
  chroot /root2 /usr/bin/mkinitcpio -P > /tmp/mkinitcpio.txt 2>&1
  p prep "mkinitcpio rc=$? $(grep -ci error /tmp/mkinitcpio.txt) error lines"
  grep -i -e error -e warn /tmp/mkinitcpio.txt | head -5 | sed 's/^/KDSINST   /'
  for d in dev sys proc; do umount /root2/$d; done
  umount /root2; sync
}
p begin "$(uname -r)" "$(cat /proc/cmdline)"
case $(uname -r) in
  6.1.*) modprobe virtio_net && p modprobe virtio_net ;;   # d-i's own modules
  *) for m in failover net_failover virtio_net; do insmod /kmod/$m.ko && p insmod $m; done ;;
esac
IP=172.16.100.3 GZ=0 SRC=net OFF=1
for a in $(cat /proc/cmdline); do
  case $a in kds_ip=*) IP=${a#kds_ip=};; kds_gz=1) GZ=1;; kds_src=*) SRC=${a#kds_src=};; kds_poweroff=0) OFF=0;; esac
done
if [ $SRC = virtiofs ]; then
  for m in fuse virtiofs; do insmod /kmod/$m.ko && p insmod $m; done
  mkdir -p /mnt && mount -t virtiofs shared_dir /mnt && p mounted shared_dir
  ls -la /mnt | sed 's/^/KDSINST   /'
  f=; for c in /mnt/ohmarchy-kds-disk.img.gz /mnt/ohmarchy-kds-disk.img; do [ -f $c ] && f=$c && break; done
  if [ -z "$f" ]; then p error "no ohmarchy-kds-disk.img[.gz] in the share"
  else
    p writing "$(ls -l $f)"
    # sparsecp (no libc, built from sparsecp.c) skips holes and zero blocks:
    # 9 GiB of data move instead of 64 GiB; the fresh vm.qcow2 reads as zeros.
    case $f in
      *.gz) gunzip -c $f | /kds/sparsecp - /dev/vda 2>&1 | sed 's/^/KDSINST /' ;;
      *) /kds/sparsecp $f /dev/vda 2>&1 | sed 's/^/KDSINST /' ;;
    esac
    rc=0
    [ "$(dd if=/dev/vda bs=1 skip=512 count=8 2>/dev/null)" = "EFI PART" ] || { rc=1; p error "no GPT header on vda after the write"; }
    sync
    p written rc=$rc
    p head "$(dd if=/dev/vda bs=64 count=1 2>/dev/null | tr -cd '[:print:]')"
    if [ $rc = 0 ] && ! grep -q kds_novmwgfx /proc/cmdline; then prep_root; fi
    [ $rc = 0 ] && p done "boot 'the installed Omarchy disk' from the GRUB menu next"
  fi
  umount /mnt
  # During 铠大师's install session a guest power-off is what vm_manager takes as
  # "install finished" (HandleVmStateCallback in libvm_manager); a window close
  # aborts the install and deletes the disk. So power off on our own.
  if [ "${rc:-1}" = 0 ] && [ $OFF = 1 ]; then p poweroff "in 5 s"; sleep 5; sync; poweroff -f; fi
  while :; do sh </dev/tty1 >/dev/tty1 2>&1; sleep 1; done
fi
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
    nc -l -p 9000 | gunzip -c | /kds/sparsecp - /dev/vda 2>/tmp/dd.err
  else
    nc -l -p 9000 | /kds/sparsecp - /dev/vda 2>/tmp/dd.err
  fi
  rc=$?; sync
  p written rc=$rc "$(tail -1 /tmp/dd.err)"
  p gpt "$(dd if=/dev/vda bs=1 skip=512 count=8 2>/dev/null)"
  [ $rc = 0 ] && { p done "boot 'the installed Omarchy disk' from the GRUB menu next"; break; }
done
while :; do sh </dev/tty1 >/dev/tty1 2>&1; sleep 1; done
