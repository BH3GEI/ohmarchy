#!/usr/bin/env bash
# Create the Omarchy VM in Aetherium on the DEVICE and start it (TCG, VNC), driving the
# app window by visible text with device/dui (on top of tools/ohdev/ohui). Mirrors the
# emulator flow (emulator/40-create-vm.sh) that was verified end to end, but on ohdev.
#
# Safety: Aetherium opens as a normal window; before any keystroke the caller/helper
# checks focus (dui never types into the 鸿融 window). Run only when the VM lock is free
# and agent-53 is not measuring. This starts a TCG VM — nice it and cap threads via
# Aetherium's config; it does NOT use HMV, so no /data/local/vm.lock is required for TCG.
#
# UNTESTED on the device yet (the disk transfer must finish first); the labels and order
# are the same Aetherium build as the emulator, so this follows the validated flow.
set -euo pipefail
. "$(dirname "$0")/config.sh"
DUI="$(dirname "$0")/dui"
DL_HAP_NAME=omarchy-aarch64-virt   # the imported qcow2's basename prefix in 下载

dui() { "$DUI" "$@"; }
next() { dui tap 下一步; sleep 1; }
pick_download() {  # pick_download NAME_PREFIX
    dui wait 'Quick access|快速访问' --timeout 30; sleep 3
    for _ in 1 2 3; do dui tap 'Downloads|下载'; dui wait "$1" --prefix --timeout 10 && break; done
    dui tap "$1" --prefix; sleep 1
    dui tap 'Open|打开' --nth -1; sleep 3
}

"$(dirname "$0")/ohsh" - <<SH
aa force-stop $BUNDLE >/dev/null 2>&1 || true
aa start -a EntryAbility -b $BUNDLE >/dev/null 2>&1 || true
SH
sleep 5
dui focus    # report which window is focused (safety: must be Aetherium, never 鸿融)

# Create the Omarchy VM: advanced setup, import the qcow2, no ISO, Linux, start as VNC.
dui has '添加列表' && dui tap '添加列表' || dui tap 创建第一个虚拟机
dui tap 高级设置
next; next; next                 # aarch64, virt, virtio-gpu-pci
dui tap virtio-net-pci; next
next                             # no sound card
dui tap '8 GB'; next
dui tap 选择                      # 导入现有 QEMU 磁盘 (QCOW2)
pick_download "$DL_HAP_NAME"
next
dui tap Linux; next
next                             # no ISO
dui has 'My Linux' && dui tap 'My Linux'
next
dui tap 创建并启动 --timeout 30
echo "copying the disk into the sandbox (this can take minutes on the device)..."
dui gone 创建并启动 --timeout 1200
sleep 5
dui has '普通启动 (VNC)' --contains || dui tap 启动虚拟机 --timeout 30
dui tap '普通启动 (VNC)' --contains --timeout 30
echo "VM starting under TCG. Measure on the device directly:"
echo "  frame rate / refresh:  oseasy/measure-fps.sh 8   (hidumper on ohdev; Aetherium window in front)"
echo "  host CPU / temp:       device/baseline.sh 10"
echo "  first-boot wizard:     drive the Aetherium VM window with tools/ohdev/ohui (verify focus first)"
