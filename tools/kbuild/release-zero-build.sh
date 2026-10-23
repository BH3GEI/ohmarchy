#!/bin/bash
# Build upstream release kernels (defconfig Image) for `hrvm ktest`, with every
# ID register read that v6.8 did not do at boot replaced by 0, to find the
# release that adds a second 鸿融 boot hang beside those reads.
# Runs as root in an Arch Linux ARM environment; the build runs as $BUILD_USER.
# Usage: release-zero-build.sh W VERSION... -> $W/out/zero-VERSION.Image
set -e
W=$1; shift
BUILD_USER=${BUILD_USER:-builder}
MIRROR=${MIRROR:-https://mirrors.tuna.tsinghua.edu.cn/kernel}
pacman -Q bc >/dev/null 2>&1 || pacman -S --needed --noconfirm bc
for ver in "$@"; do
su "$BUILD_USER" -s /bin/bash -c "set -e; cd '$W'; mkdir -p dl out
t=dl/linux-$ver.tar.xz
[ -f \$t ] || curl -fsSL -o \$t $MIRROR/v${ver%%.*}.x/linux-$ver.tar.xz
rm -rf zsrc; mkdir zsrc; tar -xJf \$t -C zsrc --strip-components=1; cd zsrc
for r in ID_AA64ISAR3_EL1 ID_AA64PFR2_EL1 ID_AA64FPFR0_EL1 ID_AA64MMFR4_EL1 AIDR_EL1 SMIDR_EL1 MPAMIDR_EL1; do
  sed -i \"s/read_cpuid(\$r)/0/g\" arch/arm64/kernel/cpuinfo.c arch/arm64/kernel/cpufeature.c
done
grep -cE 'read_cpuid\((ID_AA64(ISAR3|PFR2|FPFR0|MMFR4)|AIDR|SMIDR|MPAMIDR)_EL1\)' arch/arm64/kernel/cpuinfo.c arch/arm64/kernel/cpufeature.c || true
make -s defconfig
scripts/config -e EFI_ZBOOT -e EFI -e EFI_STUB
make -s olddefconfig
make -s -j\$(nproc) Image
cp arch/arm64/boot/Image ../out/zero-$ver.Image
ls -la ../out/zero-$ver.Image"
done
echo ALLDONE
