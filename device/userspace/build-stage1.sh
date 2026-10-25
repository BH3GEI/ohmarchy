#!/usr/bin/env bash
# Stage 1: cross-build the Wayland base stack for OHOS musl (aarch64-linux-ohos).
# Offline on a Mac; build products never go on ohdev. Produces static libs + .pc files
# under $PREFIX, consumed by the Hyprland C++ stack (Stage 3).
#
# Toolchain: the OHOS NDK's own clang 15 (matching crt + libclang_rt.builtins for the
# musl target) is used for these C libraries — no libc++ needed here. The C++26 libc++
# (homebrew clang 23 + LIBCXX_HAS_MUSL_LIBC, built separately) is only for Stage 3.
#
# Host tools needed: meson (pip), ninja, bison>=2.3a (Apple's 2.3 is too old -> brew
# install bison), expat (brew, for the native wayland-scanner). macOS Apple bison fails
# xkbcommon's YACC check.
set -euo pipefail
SP="${SP:?set SP to the scratchpad dir}"
NDK="${NDK:-/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/native}"
PREFIX="$SP/stage1/prefix"          # target (aarch64-ohos) install prefix
NATIVE="$SP/stage1/native"          # host tools (wayland-scanner)
CROSS="$SP/stage1/ohos.cross"
NATIVEINI="$SP/stage1/native.ini"
export PATH="/opt/homebrew/opt/bison/bin:$NATIVE/bin:$SP/pyenv/bin:$PATH"

# 1) libffi (autotools) — required by wayland
cd "$SP/stage1/src/libffi-ex"; rm -rf _b; mkdir _b; cd _b
CC="$NDK/llvm/bin/clang --target=aarch64-linux-ohos" AR="$NDK/llvm/bin/llvm-ar" \
  RANLIB="$NDK/llvm/bin/llvm-ranlib" CFLAGS="-O2 -fPIC" \
  ../configure --host=aarch64-linux-gnu --prefix="$PREFIX" --enable-static --disable-shared --disable-docs
make -j4 && make install

# 2) pixman
cd "$SP/stage1/src/pixman-ex"; rm -rf _b
meson setup _b --cross-file "$CROSS" --prefix="$PREFIX" --default-library=static \
  -Dtests=disabled -Ddemos=disabled -Dgtk=disabled -Dlibpng=disabled -Dgnuplot=false
meson install -C _b

# 3) libdrm
cd "$SP/stage1/src/libdrm-ex"; rm -rf _b
meson setup _b --cross-file "$CROSS" --prefix="$PREFIX" --default-library=static \
  -Dtests=false -Dcairo-tests=disabled -Dvalgrind=disabled -Dman-pages=disabled \
  -Dintel=disabled -Dradeon=disabled -Damdgpu=disabled -Dnouveau=disabled \
  -Dvmwgfx=disabled -Dfreedreno=disabled -Dvc4=disabled -Detnaviv=disabled \
  -Dinstall-test-programs=false
meson install -C _b

# 4) xkbcommon  (needs brew bison on PATH)
cd "$SP/stage1/src/xkbcommon-ex"; rm -rf _b
meson setup _b --cross-file "$CROSS" --prefix="$PREFIX" --default-library=static \
  -Denable-x11=false -Denable-wayland=false -Denable-docs=false \
  -Denable-xkbregistry=false -Denable-tools=false -Denable-bash-completion=false
meson install -C _b

# 5a) wayland — native scanner (runs on the Mac; downstream code-gen tool)
cd "$SP/stage1/src/wayland-ex"; rm -rf _bn
PKG_CONFIG_PATH=/opt/homebrew/opt/expat/lib/pkgconfig \
  meson setup _bn --prefix="$NATIVE" --default-library=static \
  -Dscanner=true -Dlibraries=false -Ddocumentation=false -Dtests=false -Ddtd_validation=false
meson install -C _bn
# 5b) wayland — target libs (scanner=false; native file points to the scanner above)
rm -rf _b
meson setup _b --cross-file "$CROSS" --native-file "$NATIVEINI" --prefix="$PREFIX" \
  --default-library=static -Dscanner=false -Ddocumentation=false -Dtests=false \
  -Ddtd_validation=false -Dlibraries=true
meson install -C _b
echo "Stage 1 done. Libs in $PREFIX/lib, scanner in $NATIVE/bin."
