#!/bin/bash
# First login of the NOPASS image (build-disk.sh NOPASS=1): SDDM logs the user
# "omarchy" in without a password once, ohmarchy-setpass.service opens a
# terminal on the desktop and runs this through sudo (one NOPASSWD rule for
# this file only). It sets the password, removes the autologin, the sudo rule
# and the terminal unit, and installs 鸿融's guest agent when 鸿融's CD is
# attached. Replaces the tty1 prompt, which route B's vmwgfx console hides.
# Not run yet.
set -uo pipefail

user=omarchy
L=/usr/local/lib/ohmarchy
pending=/var/lib/ohmarchy/setpass-pending
[ -e "$pending" ] || { echo "密码已经设置过了 / The password is already set."; exit 0; }

cat <<'TXT'
欢迎使用 Omarchy。请为用户 omarchy 设置密码（至少 8 位）。
以后登录、sudo 都用这个密码。

Welcome to Omarchy. Set the password for the user "omarchy" (8+ characters);
it is used to log in and for sudo.
TXT
while :; do
  printf '\n新密码 / New password: '; read -rs p1; echo
  [ ${#p1} -ge 8 ] || { echo "太短了 / Too short."; continue; }
  printf '再输一次 / Again: '; read -rs p2; echo
  [ "$p1" = "$p2" ] || { echo "两次不一致 / They do not match."; continue; }
  printf '%s:%s\n' "$user" "$p1" | chpasswd && break
done
unset p1 p2

# route B keeps the autologin (the password is then for sudo)
[ -e /var/lib/ohmarchy/keep-autologin ] || rm -f /etc/sddm.conf.d/zz-ohmarchy-firstboot.conf
rm -f "$pending"
rm -f "/home/$user/.config/systemd/user/graphical-session.target.wants/ohmarchy-setpass.service"
touch /var/lib/ohmarchy/firstboot.done

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
  echo "完成。开机仍会自动登录；sudo 用这个密码。按回车关闭窗口。"
  echo "Done. Login stays automatic; sudo asks for this password. Press Enter to close."
else
  echo "完成。以后用这个密码登录。按回车关闭窗口。"
  echo "Done. Log in with this password from now on. Press Enter to close."
fi
# the sudo rule goes last: this script runs under it
rm -f /etc/sudoers.d/ohmarchy-setpass
