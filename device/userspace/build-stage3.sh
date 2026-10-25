#!/usr/bin/env bash
# Stage 3: cross-build the Hypr C++ stack for OHOS musl with clang 23 + libc++23.
# Offline on a Mac; no build products on ohdev. Depends on Stage 1/2 ($PREFIX populated).
#
# THE TOOLCHAIN (the hard part, all captured in ohos-cmake.toolchain):
#  * compile C++26 with homebrew clang 23 (the OHOS NDK clang 15 can't do -std=c++26).
#  * libc++ must be the from-source libc++23 for OHOS musl, built with
#    -DCMAKE_POSITION_INDEPENDENT_CODE=ON (static .a linked into .so needs PIC) and
#    -DCMAKE_ASM_COMPILER_TARGET=aarch64-linux-ohos (else libunwind's .S assemble to
#    host Mach-O and lld rejects them). Static-linked into every component (OHOS ships
#    libc++_shared.so v15, ABI-incompatible with our v23 — so we don't use it).
#  * clang 23's OHOS driver is GCC-style at link: it wants crtbeginS.o/crtendS.o and
#    its own (empty) resource-dir builtins. Bridge with a compat dir ($CXXLIB) holding
#    the NDK's clang_rt.crtbegin.o/crtend.o renamed to crtbeginS.o/crtendS.o + the NDK
#    libclang_rt.builtins.a + our libc++/libc++abi/libunwind, passed via -B/-L, and a
#    fake resource-dir ($RES) with lib/aarch64-linux-ohos/libclang_rt.builtins.a.
set -euo pipefail
SP="${SP:?}"; NDK="${NDK:-/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/native}"
HB="${HB:-/opt/homebrew/opt/llvm}"; PREFIX="$SP/stage1/prefix"
L="$SP/llvmsrc/build-libcxx/lib"; CXXLIB="$SP/stage3/ohos-cxx-lib"; RES="$SP/stage3/ohos-res"
TC="$SP/stage3/ohos-cmake.toolchain"
RT="$NDK/llvm/lib/clang/15.0.4/lib/aarch64-linux-ohos"

# compat dir + fake resource-dir (see header)
mkdir -p "$CXXLIB" "$RES/lib/aarch64-linux-ohos"
cp "$RT/clang_rt.crtbegin.o" "$CXXLIB/crtbeginS.o"
cp "$RT/clang_rt.crtend.o"   "$CXXLIB/crtendS.o"
cp "$RT/libclang_rt.builtins.a" "$CXXLIB/"
cp "$RT/libclang_rt.builtins.a" "$RES/lib/aarch64-linux-ohos/"
cp "$L/libc++.a" "$L/libc++abi.a" "$L/libunwind.a" "$CXXLIB/"

cmcfg() { # cmcfg <srcdir> [extra cmake args...]
  local d="$1"; shift
  cmake -B "$d/_b" -S "$d" -G Ninja -DCMAKE_TOOLCHAIN_FILE="$TC" \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DPKG_CONFIG_EXECUTABLE=/opt/homebrew/bin/pkg-config "$@"
  ninja -C "$d/_b"
  ninja -C "$d/_b" install
}

# --- Hypr family (light deps) ---
cmcfg "$SP/stage3/src/hyprutils-ex"      # needs pixman        -> libhyprutils.so  4.2M  DONE
cmcfg "$SP/stage3/src/hyprlang-ex"       # needs hyprutils     -> libhyprlang.so   1.8M  DONE
# TODO downstream (need the C support stack first):
#   hyprgraphics  (cairo, libjpeg-turbo, libwebp, libmagic, hyprutils)
#   hyprcursor    (hyprlang, libzip, cairo, librsvg?)
#   aquamarine    (hyprutils, libdrm, libseat, libinput|skip, libdisplay-info, hwdata, gbm)
#   Hyprland      (all above + cairo/pango/glib(gio)/re2(abseil)/muparser/lcms2/lua5.5/
#                  uuid/xcursor/libeis/udis86/glslang/glaze/hyprwayland-scanner/
#                  hyprland-protocols) + D's two hongmeng patches + the HongMeng shims
echo "Stage 3 (hypr family) done; C support stack + Hyprland pending."
