#!/usr/bin/env bash
# Create the Omarchy VM in Aetherium by driving its UI (text matches via uitest dumpLayout),
# then boot it with 普通启动 (VNC). Expects the app as installed by 30-install.sh (no VMs yet,
# or only the throw-away one). The file picker is matched in English or Chinese.
#
# Works around two Aetherium bugs (docs/emulator-aetherium.md#create-the-vm):
# - disk import fails until files/vms exists: a throw-away VM picks a small file as its ISO
#   first, which runs StoragePaths.ensureDirectories();
# - names are reduced to [A-Za-z0-9_.-]: the VM gets the ASCII suggestion "My Linux".
set -euo pipefail
. "$(dirname "$0")/config.sh"
UI="python3 -I $ROOT/tools/emu/ui.py"
T=$(emu_target)

next() { $UI tap 下一步; sleep 1; }

pick_download() {  # pick_download NAME_PREFIX: the system file picker, 下载 folder
    $UI wait 'Quick access|快速访问' --timeout 30; sleep 3   # taps before it settles get lost
    for _ in 1 2 3; do
        $UI tap 'Downloads|下载'
        $UI wait "$1" --prefix --timeout 10 && break
    done
    $UI tap "$1" --prefix; sleep 1
    $UI tap 'Open|打开' --nth -1; sleep 3       # the last match: the dialog title says Open too
}
start_sheet_or_button() {  # the start-mode sheet only sometimes opens after 创建并启动
    $UI has '普通启动 (VNC)' --contains || $UI tap 启动虚拟机 --timeout "${1:-20}"
}

wizard() {  # wizard throwaway|omarchy
    $UI tap 高级设置
    next; next; next                              # aarch64, virt, virtio-gpu-pci
    $UI tap virtio-net-pci; next
    next                                           # no sound card
    $UI tap '8 GB'; next
    if [ "$1" = omarchy ]; then
        $UI tap 选择                               # 导入现有 QEMU 磁盘 (QCOW2)
        pick_download omarchy-aarch64-virt
    fi
    next
    $UI tap Linux; next
    next                                           # no ISO here: wizard ISOs are never copied
    [ "$1" = omarchy ] && $UI tap 'My Linux'
    next
    $UI tap 创建并启动 --timeout 30
}

"$HDC" -t "$T" shell aa force-stop "$AETH_BUNDLE" >/dev/null
"$HDC" -t "$T" shell aa start -a EntryAbility -b "$AETH_BUNDLE" >/dev/null
sleep 5   # ui.py answers "Never add" (add-to-home) and "Allow" (file permissions) as they pop up
$UI maximize 'Aether Engine'                  # 虚拟机设置 is below the fold otherwise

if ! $UI has 'Linux VM'; then
    $UI tap 创建第一个虚拟机
    wizard throwaway
    sleep 5
    $UI has 取消 && $UI tap 取消                    # start-mode sheet, if it opened: don't start
    sleep 2
    $UI tap 虚拟机设置
    $UI tap 选择                                   # ISO 镜像 → copies at once, creating the dirs
    pick_download aetherium-init
    $UI wait 'ISO 已复制到沙箱并挂载' --contains --timeout 30 || true
fi

$UI tap 添加列表
wizard omarchy
echo "copying the 3.4 GB disk into the sandbox..."
$UI gone 创建并启动 --timeout 900               # the summary closes once the import is done
sleep 5
start_sheet_or_button
$UI tap '普通启动 (VNC)' --contains --timeout 30
echo "started; VNC on 127.0.0.1:15901, serial on 127.0.0.1:14321 (see 30-install.sh)"
