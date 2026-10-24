#!/bin/bash
# Drive 铠大师 from a Mac/Linux host: create its VM from an ISO in 下载 and pick a
# GRUB entry of kds-installer.iso, or close the VM. Needs tools/ohdev/ohui and the
# ohdev ssh alias; take /data/local/vm.lock first (and power off 鸿融's VM).
#   tools/kaidashi/kds-run.sh start ROW ENTRY   ROW: the ISO's row in the picker's
#                                               下载 list (1 = top), ENTRY: GRUB entry (0 = first)
#   tools/kaidashi/kds-run.sh close
#   tools/kaidashi/kds-run.sh serial [PATTERN]  guest serial lines of the running VM
# Coordinates are for the 1440-wide screenshots of ohui on the MateBook 14
# (2880x1920) with 铠大师's window at its default place; check with `ohui shot`.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
U() { perl -e 'alarm 120; exec @ARGV' "$here/../ohdev/ohui" "$@" >/dev/null; }
R() { perl -e "alarm ${1:-60}; exec @ARGV" ssh -o BatchMode=yes -o ConnectTimeout=10 ohdev sh -s; }

vm_pid() { echo 'pidof stratovirt' | R 20 2>/dev/null || true; }

serial() {
  printf 'p=$(pidof stratovirt); [ -n "$p" ] && grep -a "\\[$p\\]" /data/log/hwf_service/vmlog | grep -a chardev.rs:207 | sed "s/^.*INFO: //" | grep -a -e "%s"\n' "${1:-.}" | R 60
}

case ${1:-} in
start)
  row=${2:?row} entry=${3:-0}
  [ -z "$(vm_pid)" ] || { echo "a VM is running"; exit 1; }
  echo 'aa start -b com.sanway.ecoengine -a VMConsoleAbility' | R 30
  sleep 4
  U tap 910 527; sleep 1; U tap 1043 681; sleep 3     # 选择本地 Windows 镜像 → 下一步
  U tap 789 513; sleep 3; U tap 245 367; sleep 3      # 选择ISO镜像文件 → 下载
  U tap 455 $((320 + 38 * (row - 1))); sleep 1        # the ISO (the 安全访问 banner shifts rows to 320)
  U tap 1185 775; sleep 8                             # 打开; the WIM check runs
  U tap 1043 702; sleep 3                             # 下一步
  U tap 719 529; sleep 2                              # 温馨提示: 我知道了
  U tap 1043 691; sleep 3; U tap 1043 695; sleep 3    # 推荐配置 → 下一步
  U tap 1043 698; sleep 4                             # 开始安装
  U tap 719 577                                       # 文档 folder sheet: 确定 without enabling it
  for _ in $(seq 1 60); do
    n=$(printf 'p=$(pidof stratovirt); [ -n "$p" ] && grep -a "\\[$p\\]" /data/log/hwf_service/vmlog | grep -ac "Boot the installed Omarchy"\n' | R 15 2>/dev/null || true)
    [ "${n:-0}" -gt 0 ] 2>/dev/null && break; sleep 1
  done
  echo "GRUB menu up (pid $(vm_pid)); entry $entry"
  for _ in $(seq 1 "$entry"); do U key 2013; sleep 0.3; done   # Down
  U key 2054                                                    # Enter
  ;;
close)
  U tap 1240 51; sleep 2; U tap 700 502                        # 关闭 → 确定
  for _ in $(seq 1 20); do [ -z "$(vm_pid)" ] && { echo closed; break; }; sleep 2; done
  sleep 2; U tap 719 522                                       # 安装过程异常终止: 确定
  ;;
serial) serial "${2:-.}" ;;
*) sed -n '2,10p' "$0"; exit 1 ;;
esac
