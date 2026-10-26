#!/bin/bash
# Install 鸿融's guest agent (虚拟机增强服务, Debian package vm-agent) into an
# Arch root. Without it 鸿融 never moves the VM to STATE_RUNNING: the card says
# 已关机 while the VM runs and 关机 is greyed out (docs/hongrong-whole-os.md,
# "鸿融 shows the running VM as 已关机"). Tested 2026-10-26 in a running VM from
# the 鸿融 CD (ROOT /, SOURCE /dev/sr1); not run in a build yet.
#
# The package ships inside 鸿融 itself (resources/rawfile/vm_tools_<ver>.iso in
# entry.hap, also offered to the guest as a CD) and is not redistributed here;
# this script takes it from the 鸿融 installed on the HarmonyOS PC.
#
# Only agent_service and its bundled libraries are installed. The package's
# postinst handles only UOS and Kylin; the rest of the package is left out on
# purpose: its Mesa 19.2.6 would shadow Arch's Mesa (and virgl), the dkms
# drivers (virtio input/sound/fs, logdev) are for old kernels and already in
# linux-aarch64, and the clipboard, printer, file-share and desktop tools
# assume UOS/deepin.
#
# How it talks to 鸿融 (docs/findings.md): the host connects to the guest over
# vsock (CID 2000 is the host side, guest port 3300); agent_service waits in
# accept(). It needs vsock interrupts, i.e. the ITS patch in hongrong/kernel.
#
# Usage: install-vm-agent.sh ROOT [SOURCE]
#   ROOT    target root (/ for the running system)
#   SOURCE  entry.hap, vm_tools_*.iso, the .deb, or the 鸿融 CD in the guest
#           (/dev/disk/by-label/鸿融); default: the installed 鸿融,
#           /data/app/el1/bundle/public/com.huawei.medivh/entry.hap
# Needs bsdtar (libarchive).
set -euo pipefail

root=${1:?root}; src=${2:-/data/app/el1/bundle/public/com.huawei.medivh/entry.hap}
[ -r "$src" ] || { echo "cannot read $src" >&2; exit 1; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT

if [ -b "$src" ]; then iso=$src
else case "$src" in
  *.hap) bsdtar -xf "$src" -C "$t" 'resources/rawfile/vm_tools_*.iso'
         iso=$(ls "$t"/resources/rawfile/vm_tools_*.iso) ;;
  *.iso) iso=$src ;;
  *.deb) deb=$src ;;
  *) echo "unknown source $src" >&2; exit 1 ;;
esac; fi
if [ -z "${deb:-}" ]; then
  mkdir "$t/iso"; bsdtar -xf "$iso" -C "$t/iso"
  deb=$(ls "$t"/iso/*.deb)
fi
mkdir "$t/deb" "$t/data"
bsdtar -xf "$deb" -C "$t/deb"
bsdtar -xf "$t/deb/data.tar.xz" -C "$t/data" ./opt/vm-agent
bsdtar -xOf "$t/deb/control.tar.xz" ./control | grep -E '^(Package|Version):'

a=$t/data/opt/vm-agent
install -d "$root/opt/vm-agent"
cp -a "$a"/agent_service "$a"/updater "$a"/lib*.so* "$a"/config "$root/opt/vm-agent/"
echo /opt/vm-agent > "$root/etc/ld.so.conf.d/vm-agent.conf"
install -m 644 "$a/agent_service.service" "$root/etc/systemd/system/agent_service.service"
# the guest side of vsock; virtio autoloads it, this only makes it certain
echo vmw_vsock_virtio_transport > "$root/etc/modules-load.d/vm-agent.conf"

if [ "$root" = / ]; then
  ldconfig; systemctl daemon-reload; systemctl enable --now agent_service.service
else
  ldconfig -r "$root"; systemctl --root="$root" enable agent_service.service
fi
echo VM_AGENT_INSTALLED
