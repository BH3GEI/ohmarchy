#!/bin/bash
# Rebuild Arch Linux ARM's linux-aarch64 kernel Image with the 鸿融 patches,
# the way ALARM's PKGBUILD builds it (kernel.org tarball + stable patch + ALARM
# patches), keeping ALARM's config and release string so the installed
# package's modules and initramfs load with it. Runs as root inside an Arch
# Linux ARM environment (e.g. native/ on the HarmonyOS host, via arch.sh run);
# the build itself runs as $BUILD_USER.
# Layout of $W: config (scripts/extract-ikconfig on the package's /boot/Image),
# patches/000N-*.patch (ALARM's), patches/hmv-*.patch (hongrong/kernel/patches).
# Usage: alarm-build-native.sh VERSION PKGREL [W] -> $W/out/Image-VERSION-PKGREL-hmv
#   e.g. alarm-build-native.sh 7.2.11 1 /home/builder/hmvk
set -e
ver=$1 rel=$2 W=${3:-/home/builder/hmvk}
BUILD_USER=${BUILD_USER:-builder}
MIRROR=${MIRROR:-https://mirrors.tuna.tsinghua.edu.cn/kernel}
major=${ver%%.*} base=${ver%.*}
pacman -Q bc >/dev/null 2>&1 || pacman -S --needed --noconfirm bc
rm -f "$W"/patches/._* "$W"/._*
su "$BUILD_USER" -s /bin/bash -c "set -e; cd '$W'
mkdir -p dl out
[ -f dl/linux-$base.tar.xz ] || curl -fL -o dl/linux-$base.tar.xz $MIRROR/v$major.x/linux-$base.tar.xz
[ -f dl/patch-$ver.xz ] || curl -fL -o dl/patch-$ver.xz $MIRROR/v$major.x/patch-$ver.xz
rm -rf src; mkdir src; tar -xJf dl/linux-$base.tar.xz -C src --strip-components=1
cd src
xz -dc ../dl/patch-$ver.xz | patch -p1 -s
for p in ../patches/000*.patch; do patch -p1 -s < \$p; done
for p in ../patches/hmv-*.patch; do patch -p1 -s < \$p; echo applied \$(basename \$p); done
echo -$rel > localversion.10-pkgrel
echo -aarch64 > localversion.20-pkgname
cp ../config .config
make -s olddefconfig
r=\$(make -s kernelrelease); [ \"\$r\" = $ver-$rel-aarch64-ARCH ] || { echo release mismatch: \$r; exit 1; }
make -s -j\$(nproc) Image
cp arch/arm64/boot/Image ../out/Image-$ver-$rel-hmv
ls -la ../out/Image-$ver-$rel-hmv"
