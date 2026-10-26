#!/bin/bash
# First login of the NOPASS image (build-disk.sh NOPASS=1): tty1 logs the user
# "omarchy" in without a password (getty autologin, its login shell execs
# Omarchy's uwsm session, as route B's bare image does; SDDM's Hyprland greeter
# left route B's vmwgfx screen black), ohmarchy-setpass.service opens a
# terminal on the desktop and runs this through sudo (one NOPASSWD rule for
# this file only). It sets the password, removes the autologin, the sudo rule
# the terminal unit and the stay-awake switch (idle goes back to Omarchy's
# screensaver and lock), and installs 鸿融's guest agent when 鸿融's CD is
# attached. Replaces the tty1 prompt, which route B's vmwgfx console hides.
# Not run yet.
set -uo pipefail

user=omarchy
L=/usr/local/lib/ohmarchy
pending=/var/lib/ohmarchy/setpass-pending
[ -e "$pending" ] || { echo "密码已经设置过了 / The password is already set."; exit 0; }

export LC_ALL=C.UTF-8
cols=$(tput cols 2>/dev/null || echo 80); rows=$(tput lines 2>/dev/null || echo 24)
center() { # center LINE: pad by display width (CJK counts double)
  local w; w=$(printf '%s' "$1" | wc -L)
  printf '%*s%s\n' $(( (cols - w) / 2 > 0 ? (cols - w) / 2 : 0 )) '' "$1"
}
ask() { # ask PROMPT VAR: centered prompt, hidden input
  local w; w=$(printf '%s' "$1" | wc -L)
  printf '%*s%s' $(( (cols - w - 12) / 2 > 0 ? (cols - w - 12) / 2 : 0 )) '' "$1"
  IFS= read -rs "$2"; echo
}
clear
for _ in $(seq $(( rows / 4 ))); do echo; done
printf '\033[1m'
center "请设置密码 / Set your password"
printf '\033[0m'
echo
center "用户 omarchy 的密码：至少 8 位，输入两次。登录后 sudo 要用它。"
center "Password for the user omarchy: at least 8 characters, typed twice; sudo asks for it."
center "输入时屏幕上不显示字符。 / Nothing is shown while you type."
echo
while :; do
  ask "新密码 / New password: " p1
  if [ ${#p1} -lt 8 ]; then
    printf '\033[31m'; center "太短了：至少 8 位，请重新输入。 / Too short: at least 8 characters. Try again."; printf '\033[0m'
    continue
  fi
  ask "再输一次 / Type it again: " p2
  if [ "$p1" != "$p2" ]; then
    printf '\033[31m'; center "两次输入不一致，请重新输入。 / The two entries differ. Try again."; printf '\033[0m'
    continue
  fi
  printf '%s:%s\n' "$user" "$p1" | chpasswd && break
  printf '\033[31m'; center "设置失败，请重试。 / Could not set it. Try again."; printf '\033[0m'
done
printf '\033[32m'; center "密码已设置。 / Password set."; printf '\033[0m'
unset p1 p2

# route B keeps the autologin (the password is then for sudo); otherwise back
# to SDDM's password login
if [ ! -e /var/lib/ohmarchy/keep-autologin ]; then
  rm -f /etc/systemd/system/getty@tty1.service.d/ohmarchy-autologin.conf
  systemctl enable sddm.service
fi
rm -f "$pending"
rm -f "/home/$user/.config/systemd/user/graphical-session.target.wants/ohmarchy-setpass.service"
touch /var/lib/ohmarchy/firstboot.done
# back to Omarchy's idle defaults (screensaver, lock with this password)
rm -f "/home/$user/.local/state/omarchy/indicators/stay-awake"

cd=/dev/disk/by-label/鸿融
if [ -b "$cd" ]; then
  echo; echo "安装鸿融增强服务 / Installing 鸿融's guest tools"
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
  echo "鸿融会重启一次虚拟机 / 鸿融 restarts the VM once."
fi

echo
if [ -e /var/lib/ohmarchy/keep-autologin ]; then
  center "完成。开机仍会自动登录；sudo 和锁屏用这个密码。按回车关闭。"
  center "Done. Login stays automatic; sudo and the lock screen use this password. Press Enter."
else
  center "完成。以后用这个密码登录。按回车关闭。"
  center "Done. Log in with this password from now on. Press Enter."
fi
# the sudo rule goes last: this script runs under it
rm -f /etc/sudoers.d/zz-ohmarchy-setpass
