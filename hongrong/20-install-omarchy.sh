#!/bin/bash
# Run as root in the booted Arch (after 10-bootstrap-arch.sh). Installs Omarchy
# the way its ISO finalizes a target, adjusted for this VM.
# Usage: 20-install-omarchy.sh USER
set -euo pipefail

user=${1:?user}
here=$(cd "$(dirname "$0")" && pwd)
# The quattro branch carries the aarch64 package list; the stable omarchy
# package does not. This is the commit the install was done with.
lists=https://raw.githubusercontent.com/basecamp/omarchy/967bbdd7346e6e2ff1a6af33c5d762ea784832cc/install
omarchy_key=40DFB630FF42BCFFB047046CF0134EE680CAC571

# 1. Repositories and keys
install -m 644 "$here/etc/pacman.conf" /etc/pacman.conf
install -m 644 "$here/etc/mirrorlist" /etc/pacman.d/mirrorlist
pacman-key --recv-keys $omarchy_key --keyserver keys.openpgp.org
pacman-key --lsign-key $omarchy_key
pacman -Sy --noconfirm --needed omarchy-keyring

# 2. Packages: base list + aarch64 additions, plus the two Omarchy packages
pkgs=$(curl -fsL "$lists/omarchy-base.packages" "$lists/omarchy-aarch64.packages" | grep -vE '^\s*(#|$)')
pacman -S --noconfirm --needed omarchy omarchy-settings $pkgs

# 3. The ISO creates the user after omarchy-settings fills /etc/skel; ours exists.
runuser -u "$user" -- cp -rT /etc/skel "/home/$user"

# 4. System setup. The root is ext4, so skip Snapper's create-config.
OMARCHY_SNAPPER_CONFIGURE_TEST=1 omarchy-apply-system --install-user "$user" --first-install

# 5. Undo what does not fit this VM
#  - omarchy-apply-pacman writes the x86 templates: put the aarch64 ones back.
install -m 644 "$here/etc/pacman.conf" /etc/pacman.conf
install -m 644 "$here/etc/mirrorlist" /etc/pacman.d/mirrorlist
#  - NetworkManager replaces networkd; the bridge has no DHCP (keyfile installed
#    by 10-bootstrap-arch.sh).
#  - ufw cannot load its rules on deepin's kernel and would block sshd.
systemctl disable ufw
sed -i 's/^ENABLED=.*/ENABLED=no/' /etc/ufw/ufw.conf
#  - The SDDM theme has only a password field and logs in userModel.lastUser,
#    which is empty until someone has logged in through SDDM.
install -D -m 600 -o sddm -g sddm /dev/stdin /var/lib/sddm/state.conf <<STATE
[Last]
User=$user
Session=/usr/local/share/wayland-sessions/omarchy.desktop
STATE

# 6. Per-user setup. --first-install forces the ISO context, which wants a
#    bundled x64 Node tarball; provision-owner falls back to the network.
runuser -u "$user" -- bash -lc \
  "OMARCHY_SETUP_CONTEXT=provision-owner MISE_NODE_MIRROR_URL=https://npmmirror.com/mirrors/node/ omarchy-provision-user --force --first-install"

echo "Done. Reboot into the SDDM login."
