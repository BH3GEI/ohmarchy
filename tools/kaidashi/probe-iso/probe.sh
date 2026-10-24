#!/bin/sh
# PID 1 of the 铠大师 probe ISO (rdinit=/probe.sh on top of Debian's d-i initrd).
# Prints the VM's hardware as seen by Linux to the console (tty0 and the serial
# port, which StratoVirt redirects to the hwf_service log), then gives a shell.
export PATH=/sbin:/usr/sbin:/bin:/usr/bin
mount -t proc proc /proc; mount -t sysfs sys /sys; mount -t devtmpfs dev /dev 2>/dev/null
mount -t efivarfs efivarfs /sys/firmware/efi/efivars 2>/dev/null
exec >/dev/console 2>&1
p() { echo "KDSPROBE $*"; }
p begin; p uname "$(uname -a)"; p cmdline "$(cat /proc/cmdline)"
p cpus "$(grep -c ^processor /proc/cpuinfo)"; grep -m1 -i 'CPU implementer\|Features' /proc/cpuinfo | sed 's/^/KDSPROBE cpu /'
p mem "$(grep MemTotal /proc/meminfo)"
for d in /sys/bus/pci/devices/*; do
  p pci "${d##*/} $(cat $d/vendor):$(cat $d/device) class $(cat $d/class) sub $(cat $d/subsystem_vendor):$(cat $d/subsystem_device)"
  for r in 0 1 2 3 4 5; do :; done; sed -n '1,6p' $d/resource | sed "s|^|KDSPROBE   res ${d##*/} |"
done
for v in /sys/firmware/efi/efivars/SecureBoot-* /sys/firmware/efi/efivars/SetupMode-*; do
  [ -e "$v" ] && p efivar "${v##*/} $(od -An -tx1 "$v" 2>/dev/null | tr -s ' ')"
done
[ -d /sys/firmware/efi ] && p efi yes || p efi no
ls /sys/firmware/acpi/tables 2>/dev/null | tr '\n' ' ' | sed 's/^/KDSPROBE acpi /'; echo
for m in vmwgfx virtio_gpu virtio_pci virtio_net virtio_blk efifb simpledrm; do modprobe $m 2>/dev/null && p modprobe $m ok; done
sleep 2
ls /sys/class/drm /sys/class/graphics /sys/class/net /sys/class/block 2>/dev/null | tr '\n' ' ' | sed 's/^/KDSPROBE classes /'; echo
for f in /sys/class/graphics/fb*/modes /sys/class/graphics/fb*/virtual_size /sys/class/graphics/fb*/name /sys/class/drm/*/modes /sys/class/drm/*/status; do
  [ -e "$f" ] && p sys "$f $(cat $f | tr '\n' ' ')"
done
for e in /sys/class/drm/*/edid; do [ -s "$e" ] && p edid "$e $(od -An -tx1 -v $e | tr -d '\n')"; done
dmesg | sed 's/^/KDSPROBE dmesg /'
p end
# d-i's busybox has no setsid: a plain shell on tty1 (no job control), and
# the same over the serial log for whoever reads it.
while :; do sh </dev/tty1 >/dev/tty1 2>&1; sleep 1; done
