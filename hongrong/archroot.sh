#!/bin/bash
# Enter the Arch tree from deepin: archroot.sh [command...] (no command: shell).
# The tree is bind-mounted onto itself first so pacman can find its mount point.
R=${ARCH_ROOT:-/persistent/arch}
mountpoint -q $R || mount --bind $R $R
for d in proc sys dev run; do mountpoint -q $R/$d || case $d in
  proc) mount -t proc proc $R/proc ;; sys) mount --rbind /sys $R/sys ;;
  dev) mount --rbind /dev $R/dev ;; run) mount -t tmpfs tmpfs $R/run ;; esac; done
# Arch ships resolv.conf as a link into systemd-resolved, which is not running here.
rm -f $R/etc/resolv.conf; cp -L /etc/resolv.conf $R/etc/resolv.conf
exec chroot $R /usr/bin/env -i HOME=/root TERM=xterm PATH=/usr/local/sbin:/usr/local/bin:/usr/bin /bin/bash ${1:+-c "$*"}
