#!/bin/bash
# Build an upstream arm64 kernel Image for boot tests in the 鸿融 VM.
# Runs in a Debian arm64 container with the kernel source at /work/linux
# (see docs/hongrong-whole-os.md#kernel-bisect).
# Usage: kernel-build.sh REF NAME [scripts/config args...] -> /work/out/NAME.Image
set -e
ref=$1 name=$2; shift 2
cd /work/linux
git checkout -q -f "$ref"
make -s mrproper
make -s defconfig
[ $# -gt 0 ] && scripts/config "$@"
make -s olddefconfig
make -s -j"$(nproc)" CC="ccache gcc" Image
mkdir -p /work/out
cp arch/arm64/boot/Image /work/out/$name.Image
ls -la /work/out/$name.Image
