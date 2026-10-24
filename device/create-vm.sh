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
# The qcow2 must be registered in the file-manager index to appear in the picker: copy it
# THROUGH the hmdfs account path (not /storage or the media view) as owner 20001006 group
# 1006 mode 660, e.g.
#   D=/data/service/el2/100/hmdfs/account/files/Docs/Download
#   cp SRC $D/omarchy-stock-aarch64.qcow2 && chown 20001006:1006 $D/... && chmod 660 $D/...
# A file written by raw dd/cat to /storage/media bypasses the index and will NOT show.
DL_HAP_NAME=omarchy-stock-aarch64   # stock Omarchy 7.x (unpatched kernel); basename prefix in 下载

dui() { "$DUI" "$@"; }
next() { dui tap 下一步; sleep 1; }
pick_download() {  # pick_download NAME_PREFIX  (the fresh picker opens straight into the file list)
    sleep 2
    dui tap "$1" --contains --timeout 20; sleep 1
    dui tap 'Open|打开' --timeout 15; sleep 2
}

"$(dirname "$0")/ohsh" - <<SH
aa force-stop $BUNDLE >/dev/null 2>&1 || true
aa start -a EntryAbility -b $BUNDLE >/dev/null 2>&1 || true
SH
sleep 5
dui focus    # report which window is focused (safety: must be Aetherium, never 鸿融)

# Create the Omarchy VM: advanced setup, import the qcow2, no ISO, Linux, start as VNC.
# Each wizard page is selected EXPLICITLY (verified on-device 2026-10-25); the page titles are
# 选择架构 / 选择机器 / 选择显卡 / 选择网卡 / 声卡 / 配置内存 / 配置硬盘.
dui has '添加列表' && dui tap '添加列表' || dui tap 创建第一个虚拟机
dui tap 高级设置; sleep 1
dui tap 'ARM64' --contains; next                    # 选择架构: ARM64 (aarch64)
dui tap '通用 ARM 虚拟机平台' --contains; next       # 选择机器: virt (recommended)
dui tap 'virtio-gpu-pci'; next                      # 选择显卡 (no 3D backend in this build; 2D only)
dui tap 'virtio-net-pci'; next                      # 选择网卡
dui tap '无声卡'; next                               # 声卡: none
dui tap '4 GB'; next                                # 配置内存: 4 GB (host RAM is tight; avoids swap)
dui tap 选择                                         # 配置硬盘: 导入现有 QEMU 磁盘 (QCOW2)
pick_download "$DL_HAP_NAME"
next
# --- steps below are the Route F (emulator) flow; re-verify the exact labels on the device ---
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
