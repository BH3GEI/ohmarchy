#!/bin/bash
# Run once inside route I's guest as root, to make it D's Docker backend:
#   ohmarchy-vm ssh 'sudo bash -s' < tools/ownvm/guest-provision.sh
# (sudo the first time takes yao's password, given over stdin from an
# environment variable, never a file; see docs/vm-own.md).
# - sudo for yao without a password only for power-off and reboot, which
#   `ohmarchy-vm stop` uses (the guest ignores StratoVirt's QMP powerdown);
#   removes the broad test rule (zz-ownvm-test) if present
# - Docker + compose, enabled, yao in the docker group (docker over ssh as yao),
#   registry mirrors (Docker Hub direct times out from here)
# - virtio_balloon loaded at boot, so free page reporting returns idle memory
# - D's home share (virtiofs tag "builder") mounted at /home/builder, the same
#   path as in D, so bind mounts given from D's terminal resolve in the VM
set -eu
cat > /etc/sudoers.d/zz-ohmarchy-vm <<'S'
yao ALL=(root) NOPASSWD: /usr/bin/systemctl poweroff, /usr/bin/systemctl reboot
S
chmod 440 /etc/sudoers.d/zz-ohmarchy-vm
visudo -cf /etc/sudoers.d/zz-ohmarchy-vm
rm -f /etc/sudoers.d/zz-ownvm-test /etc/sudoers.d/90-ownvm-test
pacman -S --needed --noconfirm docker docker-compose docker-buildx >/dev/null
mkdir -p /etc/docker
[ -s /etc/docker/daemon.json ] ||
  echo '{"registry-mirrors":["https://docker.m.daocloud.io","https://docker.1ms.run"]}' > /etc/docker/daemon.json
systemctl enable --now docker.service
usermod -aG docker yao
echo virtio_balloon > /etc/modules-load.d/ohmarchy-vm.conf
modprobe virtio_balloon || true
mkdir -p /home/builder
grep -q '^builder ' /etc/fstab ||
  echo 'builder /home/builder virtiofs defaults,nofail,x-systemd.device-timeout=5s 0 0' >> /etc/fstab
systemctl daemon-reload
mount /home/builder 2>/dev/null || true
echo "sudo: $(cat /etc/sudoers.d/zz-ohmarchy-vm)"
echo "docker: $(systemctl is-active docker), $(docker version --format '{{.Server.Version}}')"
echo "home share: $(findmnt -n -o SOURCE,FSTYPE /home/builder || echo 'not mounted (no share this boot?)')"
echo "balloon: $(lsmod | grep -c virtio_balloon) module, reporting order $(cat /sys/module/page_reporting/parameters/page_reporting_order 2>/dev/null || echo ?)"
