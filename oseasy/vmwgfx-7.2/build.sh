#!/bin/bash
# Build the vmwgfx-oseasy package in an Arch Linux ARM environment as root,
# without installing anything there: the headers package is only unpacked.
#   build.sh /path/to/linux-aarch64-headers-*.pkg.tar.* [OUTDIR]
# fakeroot hangs on the HongMeng kernel (SysV msgrcv), so makepkg runs from a
# copy with its root check disabled.
set -euo pipefail
hdr=${1:?headers package}; out=${2:-$PWD}
here=$(cd "$(dirname "$0")" && pwd)
w=$(mktemp -d /tmp/vmwgfx-oseasy.XXXXXX)
trap 'rm -rf "$w"' EXIT
bsdtar -xf "$hdr" -C "$w" usr/lib/modules
export KDIR=$(echo "$w"/usr/lib/modules/*/build)
[ -f "$KDIR/Makefile" ] || { echo "no build tree in $hdr"; exit 1; }
# linux-aarch64 pkgver-pkgrel from the headers package name
export _kpkgver=$(bsdtar -xOf "$hdr" .PKGINFO | sed -n 's/^pkgver = //p')
sed 's/^\(\s*\)if (( EUID == 0 )); then/\1if false; then/' /usr/bin/makepkg > "$w/makepkg"
cp "$here/PKGBUILD" "$here/vmwgfx-oseasy.conf" "$w/"
cd "$w"
export VMWGFX_SRC=$here/../../driver/vmwgfx-oseasy-7.2
PKGDEST=$out bash "$w/makepkg" -f --nodeps --noconfirm --skipinteg
ls -la "$out"/vmwgfx-oseasy-*.pkg.tar.*
