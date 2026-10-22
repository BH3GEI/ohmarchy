#!/usr/bin/env bash
# Build the Oseasy SVGA driver (vmwgfx-oseasy) and omarchy_efidrm against Debian's
# 6.1 headers, then assemble the full module tree for Omarchy's root:
#   $WORK/k61/Image                       kernel (EFI stub)
#   $WORK/k61/modroot/usr/lib/modules/KVER  Debian modules + our two modules
#   $WORK/k61/modules-KVER.tar.gz         the same tree, shipped on the ESP
set -euo pipefail
. "$(dirname "$0")/config.sh"
need bsdtar make depmod gzip "$CLANG"
D=$WORK/dl K=$WORK/k61
rm -rf "$K"; mkdir -p "$K/hdr" "$K/img" "$K/modroot/usr/lib/modules" "$K/build"

for deb in "linux-headers-${KVER}_${KPKG}_arm64.deb" "linux-headers-${KVER%-arm64}-common_${KPKG}_all.deb" \
           "linux-kbuild-${KBUILD_SERIES}_${KPKG}_$(host_deb_arch).deb"; do
    bsdtar -xOf "$D/$deb" 'data.tar.*' | bsdtar -xf - -C "$K/hdr"
done
bsdtar -xOf "$D/linux-image-$KVER-unsigned_${KPKG}_arm64.deb" 'data.tar.*' | bsdtar -xf - -C "$K/img"

# kernel: Debian ships a gzip-compressed Image; the UKI needs the plain EFI-stub Image
V=$K/img/boot/vmlinuz-$KVER
if gzip -t "$V" 2>/dev/null; then gzip -dc "$V" > "$K/Image"; else cp "$V" "$K/Image"; fi

# out-of-tree modules
cp -a "$OHMARCHY_ROOT/driver/vmwgfx-oseasy" "$K/build/vmwgfx"
cp -a "$OHMARCHY_ROOT/driver/efidrm" "$K/build/efidrm"
for m in vmwgfx efidrm; do
    HEADERS=$K/hdr/usr/src/linux-headers-$KVER COMMON=$K/hdr/usr/src/linux-headers-${KVER%-arm64}-common \
        CLANG=$CLANG bash "$OHMARCHY_ROOT/tools/kbuild/build-module.sh" "$K/build/$m"
done

# module tree: Debian's, our vmwgfx replaces the stock one, efidrm goes to extra/
M=$K/modroot/usr/lib/modules/$KVER
cp -a "$K/img/lib/modules/$KVER" "$M"
cp "$K/build/vmwgfx/vmwgfx.ko" "$M/kernel/drivers/gpu/drm/vmwgfx/vmwgfx.ko"
mkdir -p "$M/extra"; cp "$K/build/efidrm/omarchy_efidrm.ko" "$M/extra/"
depmod -b "$K/modroot" "$KVER" 2>/dev/null || depmod -b "$K/modroot/usr" "$KVER"
[ -s "$M/modules.dep" ] || die "depmod produced no modules.dep"
touch "$M/.ohmarchy"
tar -C "$K/modroot" -czf "$K/modules-$KVER.tar.gz" "usr/lib/modules/$KVER"
ls -la "$K/Image" "$K/modules-$KVER.tar.gz"
