#!/bin/bash
# B-line demo: install Omarchy into OSEasy from the no-VM state and show it working.
# Drives the HarmonyOS UI over tools/ohdev/ohui and the guest over ssh.
# Prereqs (see docs/demo.md "B: Omarchy in OSEasy"):
#   - Download/oseasy-probe.iso is the 5ms+watchdog installer build (GRUB default=4)
#   - /data/local/oseasy/ has omarchy-pure.img.zst, push-disk.sh, waitpush.sh, rb.sh
#   - no VM running, 鸿融 off, both locks held by the presenter
# Usage: OHMARCHY_ROOT=~/oseasy-work/ohmarchy bash tests/demo/b.sh
set -u
ROOT=${OHMARCHY_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}
O=$ROOT/tools/ohdev/ohui
HOST=${OHDEV:-ohdev}
GUEST=${OSEASY_GUEST:-ohvm-arch}
h() { perl -e 'alarm shift; exec @ARGV' "$1" ssh -o ConnectTimeout=15 "$HOST" sh -s; }
g() { perl -e 'alarm shift; exec @ARGV' "$1" ssh -o BatchMode=yes -o ConnectTimeout=20 "$GUEST" "${@:2}"; }
# tap only if the top window at (x,y) is OSEasy (guards against stray windows)
st() { "$ROOT/tests/demo/safetap" com.oseasy1.ohvm "$1" "$2" 2>/dev/null || $O tap "$1" "$2" >/dev/null 2>&1; }
step() { echo "== $* ($(date +%T))"; }

step "B1 arm the disk push"
echo 'wc -l < /data/log/hwf_service/vmlog > /data/local/oseasy/vmlog.s2; nohup sh /data/local/oseasy/waitpush.sh >/dev/null 2>&1 & echo armed' | h 25

step "B1 open OSEasy, create VM"
$O sh 'aa start -b com.oseasy1.ohvm -a VMConsoleAbility -m entry' >/dev/null 2>&1; sleep 5
# if a prior failed VM is remembered, OSEasy shows 安装失败 -> 再次安装; else 立即创建
if $O dump d 2>/dev/null | grep -q 再次安装; then
  st 946 419                       # 再次安装
else
  st 1053 449; sleep 3             # 立即创建
  st 735 419;  sleep 2             # 取消 the wrong-ISO dialog
  st 1118 398; sleep 4             # 点击选择 ISO
  $O tap 460 320 >/dev/null 2>&1; sleep 2   # oseasy-probe.iso (picker is another app)
  $O tap 1185 775 >/dev/null 2>&1; sleep 3  # 打开
  st 1278 659; sleep 3             # 下一步 (past "镜像不符合要求")
  st 735 430;  sleep 3             # 继续安装
  st 735 430;  sleep 3             # 仍要安装
  st 1278 659; sleep 4             # 开始安装
  $O tap 720 738 >/dev/null 2>&1   # 收起介绍
fi

step "B1 wait for INSTALL_DONE (~133 s)"
t0=$(date +%s)
until o=$(echo 'tail -n +$(cat /data/local/oseasy/vmlog.s2) /data/log/hwf_service/vmlog | grep "probe\] install" | sed "s/^.*INFO: //"' | h 30 2>/dev/null) && echo "$o" | grep -q -E 'INSTALL_DONE|could not'; do
  sleep 8; [ $(( $(date +%s) - t0 )) -gt 480 ] && { echo "install timeout"; exit 1; }
done
echo "$o" | grep -q INSTALL_DONE || { echo "install failed"; exit 1; }
echo "installed in $(( $(date +%s)-t0 )) s"

step "B2 reboot into Omarchy (~10 s to Hyprland)"
rm -f ~/.ssh/known_hosts_oseasy
perl -e 'alarm 40; exec @ARGV' ssh "$HOST" sh -s < "$ROOT/tests/demo/rb.sh" >/dev/null 2>&1 || h 40 < "$ROOT/oseasy/rb.sh" 2>/dev/null
t1=$(date +%s)
for i in $(seq 1 90); do g 15 'ps -o user= -C Hyprland' 2>/dev/null | grep -q yao && break; sleep 2; done
echo "Hyprland up $(( $(date +%s)-t1 )) s after reset"

step "B3 es2gears (120 fps from the VM)"
g 20 'setsid -f env XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-1 es2gears_wayland >/tmp/g.log 2>&1 </dev/null'; sleep 3
"$ROOT/oseasy/measure-fps.sh" 6 2>&1 | grep -e 'composer fps' -e dxvk | head -3

step "B3 workspace switching"
g 20 'XDG_RUNTIME_DIR=/run/user/1000 /tmp/guest-bench.sh workspaces 8 >/dev/null 2>&1 &' 2>/dev/null; sleep 1
"$ROOT/oseasy/measure-fps.sh" 6 2>&1 | grep 'composer fps'

step "B3 foot and chromium launch times"
g 60 'bash -s' <<'G'
export XDG_RUNTIME_DIR=/run/user/$(id -u) WAYLAND_DISPLAY=wayland-1
count(){ hyprctl clients -j 2>/dev/null | grep -c '"class"'; }
for app in "foot" "chromium --user-data-dir=/tmp/demo-cr --no-first-run"; do
  b=$(count); t0=$(date +%s%N); setsid -f $app >/dev/null 2>&1 </dev/null
  for _ in $(seq 1 100); do [ "$(count)" -gt "$b" ] && break; sleep 0.05; done
  printf '%s: %d ms\n' "${app%% *}" "$(( ($(date +%s%N)-t0)/1000000 ))"
  sleep 1; hyprctl dispatch killactive >/dev/null 2>&1; sleep 1
done
rm -rf /tmp/demo-cr
G
echo "== demo done ($(date +%T))"
