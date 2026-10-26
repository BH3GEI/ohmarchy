#!/bin/bash
# First boot of the Omarchy base image (hongrong/pure/build-disk.sh with
# BASE=1), on tty1: the user sets the password of "omarchy", then Omarchy is
# installed from the network (Arch Linux ARM from TUNA), the coding agents are
# set up, 鸿融's guest agent is installed when 鸿融's CD is there, and the VM
# reboots into the SDDM login. Shared by the 鸿融 qcow2 and the OSEasy root
# image. Not run yet.
# Also needs zz-hongrong.conf (mkinitcpio hooks) next to it.
#
# Files (installed by build-disk.sh): /usr/local/lib/ohmarchy/ holds this
# script, 20-install-omarchy.sh with etc/, install-vm-agent.sh, setup-ai.sh and,
# on the demo machine's image only, ai.env (never in a public image).
set -uo pipefail

L=/usr/local/lib/ohmarchy
user=omarchy
log=/var/log/ohmarchy-firstboot.log
done_flag=/var/lib/ohmarchy/firstboot.done
extra_pkgs=${EXTRA_PKGS-mesa-utils glmark2}

say() { printf '\n\033[1m%s\033[0m\n' "$*"; }
fail() {
  say "出错了 / Something went wrong: $*"
  echo "日志 / Log: $log"
  echo "按回车重试 / Press Enter to try again."
  read -r _
  exec "$0"
}
retry() { # retry N CMD...: network steps fail now and then
  local n=$1 i; shift
  for i in $(seq "$n"); do "$@" && return 0; echo "retry $i/$n: $*"; sleep 10; done
  return 1
}

clear
say "欢迎使用 Omarchy / Welcome to Omarchy"
cat <<'TXT'
这是第一次开机。接下来：
  1. 为用户 omarchy 设置密码；
  2. 联网安装 Omarchy 桌面，大约 15–30 分钟，取决于网速；
  3. 自动重启，进入登录界面。
安装过程中请不要关闭虚拟机。

This is the first boot. Set the password for the user "omarchy"; Omarchy is
then installed from the network (about 15-30 minutes) and the VM reboots into
the login screen. Do not shut the VM down while it installs.
TXT

# 1. User and password (asked again after a failed run only if not set yet)
id "$user" >/dev/null 2>&1 || useradd -m -G wheel "$user"
echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/wheel
if passwd -S "$user" | grep -q ' L \| NP '; then
  while :; do
    printf '\n设置 omarchy 的密码（至少 8 位） / Password for omarchy (8+ characters): '
    read -rs p1; echo
    [ ${#p1} -ge 8 ] || { echo "太短了 / Too short."; continue; }
    printf '再输一次 / Again: '; read -rs p2; echo
    [ "$p1" = "$p2" ] || { echo "两次不一致 / They do not match."; continue; }
    printf '%s:%s\n' "$user" "$p1" | chpasswd && break
  done
  unset p1 p2
fi

exec > >(tee -a "$log") 2>&1

# 2. Network
say "检查网络 / Checking the network"
until curl -fsI -m 10 https://mirrors.tuna.tsinghua.edu.cn/ >/dev/null; do
  echo "连不上网络，10 秒后重试 / No network yet, retrying in 10 s"; sleep 10
done

# The root filesystem may sit on a device larger than itself (OSEasy grows
# the image file before boot); use all of it.
root_dev=$(findmnt -no SOURCE /)
resize2fs "$root_dev" >/dev/null 2>&1 || true

# 3. Omarchy
say "安装 Omarchy（大约 15–30 分钟）/ Installing Omarchy (15-30 minutes)"
# ext4 root, no btrfs-overlayfs, no autodetect (see build-disk.sh step 3)
install -m 644 "$L/zz-hongrong.conf" /etc/mkinitcpio.conf.d/zz-hongrong.conf
retry 3 bash "$L/20-install-omarchy.sh" "$user" || fail "Omarchy install"
[ -z "$extra_pkgs" ] || retry 3 pacman -S --needed --noconfirm $extra_pkgs || true
# omarchy-apply-system may put autodetect back into the initramfs hooks
sed -i 's/^HOOKS=(\(.*\)autodetect \(.*\))/HOOKS=(\1\2)/' /etc/mkinitcpio.conf
mkinitcpio -P || fail "mkinitcpio"
rm -rf /var/cache/pacman/pkg/*

# 4. Coding agents (Claude Code, Codex, opencode) through the relay
say "配置 AI 编程工具 / Setting up the coding agents"
ai_env=
[ -r "$L/ai.env" ] && { install -m 600 -o "$user" "$L/ai.env" /tmp/ai.env; ai_env=/tmp/ai.env; }
runuser -u "$user" -- bash -lc "bash $L/setup-ai.sh $ai_env --install" || echo "setup-ai.sh failed; the tools install on first use"
rm -f /tmp/ai.env "$L/ai.env"

# 5. Done; 鸿融's guest agent comes last: on its first connection 鸿融 powers
#    the VM off and starts it again, which is the reboot.
mkdir -p "${done_flag%/*}"; touch "$done_flag"
systemctl disable ohmarchy-firstboot.service
cd=/dev/disk/by-label/鸿融
if [ -b "$cd" ]; then
  say "安装鸿融增强服务 / Installing 鸿融's guest tools"
  bash "$L/install-vm-agent.sh" / "$cd" || echo "vm-agent install failed"
  # its logind.conf rewrite has no [Login] header and is ignored; keep the
  # settings it means in a drop-in
  install -D -m 644 /dev/stdin /etc/systemd/logind.conf.d/50-vm-agent.conf <<'CONF'
[Login]
HandleSuspendKey=ignore
HandleHibernateKey=ignore
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
CONF
fi
say "完成，正在重启 / Done, rebooting"
sleep 5
systemctl reboot
