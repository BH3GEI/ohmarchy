#!/bin/bash
# Run on a machine that reaches GitHub (the HarmonyOS host does not): fetch the
# aquamarine and Hyprland releases matching Omarchy's packages into desktop/src,
# where 40-install-desktop.sh picks them up after native/ is copied to the host.
set -e
cd "$(dirname "$0")"
mkdir -p src && cd src
[ -d aquamarine ] || git clone -q --depth 1 --branch v0.15.1 https://github.com/hyprwm/aquamarine.git
[ -d Hyprland ] || git clone -q --depth 1 --branch v0.56.2 --recurse-submodules --shallow-submodules https://github.com/hyprwm/Hyprland.git
rm -rf aquamarine/.git Hyprland/.git
du -sh aquamarine Hyprland
