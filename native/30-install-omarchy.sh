#!/bin/bash
# Run in the session as root: sh arch.sh run 30-install-omarchy.sh USER
# Installs Omarchy's packages and the user's configs, the way
# hongrong/20-install-omarchy.sh does, minus everything that needs systemd as
# pid 1, a DRM seat or a boot loader. omarchy-apply-system is not run: its
# firewall step would load ufw rules into the host's kernel, because the
# session shares the host's network namespace.
set -euo pipefail

user=${1:?user}
here=$(cd "$(dirname "$0")" && pwd)
# GitHub is not reachable from the HarmonyOS host; fetch the package lists
# through a proxy (pacman still verifies every package against Omarchy's key).
lists=${OMARCHY_LISTS:-https://gh-proxy.com/https://raw.githubusercontent.com/basecamp/omarchy/967bbdd7346e6e2ff1a6af33c5d762ea784832cc/install}
omarchy_key=40DFB630FF42BCFFB047046CF0134EE680CAC571

# 1. Repositories and keys
install -m 644 "$here/etc/pacman.conf" /etc/pacman.conf
install -m 644 "$here/etc/mirrorlist" /etc/pacman.d/mirrorlist
# Omarchy's omarchy-refresh-pacman (Update menu) overwrites both with its stock
# files; its pre-refresh-pacman hook puts these back before the upgrade.
install -D -m 644 "$here/etc/pacman.conf" /opt/ohmarchy/etc/pacman.conf
install -D -m 644 "$here/etc/mirrorlist" /opt/ohmarchy/etc/mirrorlist
runuser -u "$user" -- install -D -m 755 "$here/desktop/hooks/pre-refresh-pacman-ohmarchy-mirrors" \
    "$(getent passwd "$user" | cut -d: -f6)/.config/omarchy/hooks/pre-refresh-pacman.d/10-ohmarchy-mirrors"
# dirmngr's keyserver fetch fails here ("Server indicated a failure"); get
# the key over HTTPS instead. Only this fingerprint is signed below.
curl -fsSL "https://keys.openpgp.org/vks/v1/by-fingerprint/$omarchy_key" -o /tmp/omarchy.asc
pacman-key --add /tmp/omarchy.asc
pacman-key --lsign-key $omarchy_key
pacman -Sy --noconfirm --needed omarchy-keyring

# 2. Packages: base list + aarch64 additions, plus the two Omarchy packages
#    and waypipe (omarchy -g shows apps in route C's desktop)
pkgs=$(curl -fsL "$lists/omarchy-base.packages" "$lists/omarchy-aarch64.packages" | grep -vE '^\s*(#|$)')
pacman -S --noconfirm --needed omarchy omarchy-settings waypipe $pkgs

# 3. The user existed before omarchy-settings filled /etc/skel.
runuser -u "$user" -- cp -rT /etc/skel "/home/$user"

# 4. System setup: only the file-only steps of omarchy-apply-system.
bash /usr/share/omarchy/install/config/theme-system.sh
updatedb --prune-bind-mounts=no

# 5. Per-user setup (themes, mise, Node). provision-owner falls back to the
#    network for Node instead of the ISO's bundled x64 tarball.
runuser -u "$user" -- bash -lc \
  "OMARCHY_SETUP_CONTEXT=provision-owner MISE_NODE_MIRROR_URL=https://npmmirror.com/mirrors/node/ omarchy-provision-user --force --first-install"

echo "Done. Enter with bin/omarchy."
