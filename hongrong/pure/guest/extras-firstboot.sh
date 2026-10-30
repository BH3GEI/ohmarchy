#!/bin/bash
# One-time first-boot job for an internal demo disk (firstboot/
# ohmarchy-guest-extras.service, root): the patched kernel back and held,
# mainland mirrors as the system default, kimi-code and octoscode with their
# first-run setup, a proxy check. Expects in /usr/local/lib/ohmarchy/extras/:
# this file, extras-user.sh, setup-ai.sh, demo-setup.sh, the kernel packages
# linux-aarch64(-headers)-7.2.12-1.2 and octos'/octoscode's linux arm64 release
# archives (GitHub is slow from the guest). The report goes to
# /var/log/ohmarchy-extras.log and to the host (172.16.100.1:8766, if a
# listener waits there).
set -u
E=/usr/local/lib/ohmarchy/extras; L=/usr/local/lib/ohmarchy; user=omarchy; h=/home/$user
log=/var/log/ohmarchy-extras.log
exec > >(tee $log) 2>&1
mask() { sed -E 's/[A-Za-z0-9_-]{30,}/***/g'; }
echo "== start $(date +%T)"
install -m 755 $E/setup-ai.sh $E/demo-setup.sh $L/
# an update cancelled before the VM went down can leave pacman's lock behind
pgrep -x pacman >/dev/null || rm -f /var/lib/pacman/db.lck
echo "== kernel"
v=$(pacman -Q linux-aarch64 | cut -d' ' -f2); echo "before: $v"
if [ "$v" != 7.2.12-1.2 ]; then
  pk=($E/linux-aarch64-7.2.12-1.2-aarch64.pkg.tar.xz)
  pacman -Q linux-aarch64-headers >/dev/null 2>&1 && pk+=($E/linux-aarch64-headers-7.2.12-1.2-aarch64.pkg.tar.xz)
  pacman -U --noconfirm "${pk[@]}" 2>&1 | tail -3
fi
echo "now: $(pacman -Q linux-aarch64)"
echo "== network"
for i in $(seq 1 60); do curl -s -o /dev/null -m 5 https://mirrors.tuna.tsinghua.edu.cn && break; sleep 5; done
echo "== mirrors (as root for the user's home, then handed back)"
HOME=$h USER=$user bash $L/demo-setup.sh mirrors 2>&1 | tail -4
chown -R $user:$user $h/.cargo $h/.config/omarchy $h/.config/environment.d
echo "== agents (as $user)"
# ai.conf comes from the user unit ohmarchy-ai-import.service at the first
# login, later than this system unit: wait for it (up to 15 minutes; without
# it the agents are installed and left unconfigured)
for i in $(seq 1 180); do [ -s $h/.config/environment.d/ai.conf ] && break; sleep 5; done
[ -s $h/.config/environment.d/ai.conf ] && echo "ai.conf there" || echo "no ai.conf after 15 minutes"
runuser -u $user -- env HOME=$h USER=$user LOGNAME=$user PATH=$h/.local/bin:/usr/local/bin:/usr/bin bash $E/extras-user.sh 2>&1 | mask
echo "== proxy"
systemctl is-active sing-box; systemctl is-enabled sing-box
[ -e /etc/ohmarchy/proxy.env ] && echo "proxy.env still there" || echo "proxy.env consumed"
for u in https://www.google.com https://github.com; do
  curl -s -o /dev/null -m 15 -w "$u tun %{http_code}\n" $u
  curl -s -o /dev/null -m 15 -x http://127.0.0.1:7890 -w "$u mixed %{http_code}\n" $u
done
echo "== pacman"
grep -n '^IgnorePkg' /etc/pacman.conf; grep '^Server' /etc/pacman.d/mirrorlist
ls /etc/environment.d/ /etc/profile.d/ohmarchy-mirrors.sh /usr/etc/npmrc /etc/pip.conf /etc/uv/uv.toml /etc/docker/daemon.json $h/.cargo/config.toml $h/.config/omarchy/hooks/pre-refresh-pacman.d/ 2>&1
echo "== done $(date +%T)"
rm -f /var/lib/ohmarchy/extras-pending
systemctl disable ohmarchy-guest-extras.service 2>/dev/null
sleep 1
mask < $log > /dev/tcp/172.16.100.1/8766 2>/dev/null
exit 0
