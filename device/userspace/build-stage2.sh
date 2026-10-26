#!/usr/bin/env bash
# Stage 2: cross-build mesa (virgl gallium driver, NO LLVM) for OHOS musl, plus the
# runtime deps mesa pulls in (zlib, expat) and the build-time data (wayland-protocols).
# Offline on a Mac; no build products on ohdev. Depends on Stage 1 ($PREFIX populated).
#
# Host python deps (in the pip venv): mako, packaging (mesa's mako check imports
# packaging.version — distutils is gone in py3.12+), pyyaml.
set -euo pipefail
SP="${SP:?}"; NDK="${NDK:-/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/native}"
PREFIX="$SP/stage1/prefix"; NATIVE="$SP/stage1/native"
CROSS="$SP/stage1/ohos.cross"; NATIVEINI="$SP/stage1/native.ini"
export PATH="$NATIVE/bin:$SP/pyenv/bin:$PATH"
CLANG="$NDK/llvm/bin/clang"

# zlib — its Darwin Makefile forces Apple libtool (chokes on ELF .o); build the lib by hand.
cd "$SP/stage1/src/zlib-ex"
"$CLANG" --target=aarch64-linux-ohos -O2 -fPIC -DHAVE_HIDDEN -c \
  adler32.c crc32.c deflate.c infback.c inffast.c inflate.c inftrees.c trees.c \
  zutil.c compress.c uncompr.c gzclose.c gzlib.c gzread.c gzwrite.c
"$NDK/llvm/bin/llvm-ar" rcs libz.a *.o
cp libz.a "$PREFIX/lib/"; cp zlib.h zconf.h "$PREFIX/include/"
# (zlib.pc written once; see repo)

# expat — shared .so is a runtime NEEDED of libEGL. The tools/ subdir errors but the lib installs.
cd "$SP/stage1/src/expat-ex"; rm -rf _b; mkdir _b; cd _b
CC="$CLANG --target=aarch64-linux-ohos" AR="$NDK/llvm/bin/llvm-ar" RANLIB="$NDK/llvm/bin/llvm-ranlib" \
  CFLAGS="-O2 -fPIC" ../configure --host=aarch64-linux-gnu --prefix="$PREFIX" \
  --enable-shared --disable-static --without-docbook --without-examples --without-tests
make -j4 libexpat.la && make install-libLTLIBRARIES install-pkgconfigDATA install-cincludeHEADERS || true

# wayland-protocols — host data (XML + .pc), installed into the native prefix for downstream.
cd "$SP/stage1/src/wlproto-ex"; rm -rf _b
meson setup _b --prefix="$NATIVE" --native-file "$NATIVEINI" -Dtests=false
meson install -C _b

# mesa — virgl only, no llvm, wayland platform. NOTE: the vtest winsys needs
# -DVIRGL_RENDERER_UNSTABLE_APIS (add c_args to src/gallium/winsys/virgl/vtest/meson.build)
# to negotiate vtest protocol v3 (shm resources); a multi-client in-app vtest requires >=3.
cd "$SP/stage1/src/mesa-ex"; rm -rf _b
meson setup _b --cross-file "$CROSS" --native-file "$NATIVEINI" --prefix="$PREFIX" \
  -Dgallium-drivers=virgl -Dvulkan-drivers= -Dllvm=disabled -Dplatforms=wayland \
  -Dglx=disabled -Degl=enabled -Dgles2=enabled -Dgbm=enabled -Dshared-glapi=enabled \
  -Dgallium-vdpau=disabled -Dgallium-va=disabled -Dvideo-codecs= -Dtools= -Dbuildtype=release
meson install -C _b
echo "Stage 2 done. libEGL/libGLESv2/libgbm/libgallium(+virgl) in $PREFIX/lib."
