#!/usr/bin/env bash
# build-module.sh MODULE_DIR: cross-build an out-of-tree arm64 module against
# Debian's extracted linux-headers packages with clang (no gcc cross toolchain).
#   HEADERS=.../usr/src/linux-headers-6.1.0-50-arm64
#   COMMON=.../usr/src/linux-headers-6.1.0-50-common
#   CLANG=clang (any recent clang; Debian built the kernel with gcc, so expect
#   "compiler differs" warnings)
set -euo pipefail
: "${HEADERS:?set HEADERS}" "${COMMON:?set COMMON}" "${CLANG:=clang}"
module_dir=$(realpath -e -- "$1")
llvm_dir=$(dirname "$(command -v "$CLANG")")
ver=$("$CLANG" -dumpversion); maj=${ver%%.*}; rest=${ver#*.}; min=${rest%%.*}
exec make -C "$HEADERS" -f "$COMMON/Makefile" \
    srctree="$COMMON" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
    CC="$CLANG --target=aarch64-linux-gnu" LLVM="$llvm_dir/" \
    CONFIG_CC_IS_GCC= CONFIG_CC_IS_CLANG=y \
    CONFIG_GCC_VERSION=0 CONFIG_CLANG_VERSION=$((maj * 10000 + min * 100)) \
    CONFIG_CC_IMPLICIT_FALLTHROUGH=-Wimplicit-fallthrough \
    CONFIG_CC_HAS_AUTO_VAR_INIT_ZERO_ENABLER=y \
    DEBIAN_KERNEL_NO_CC_VERSION_CHECK= \
    M="$module_dir" -j"$(nproc)" modules
