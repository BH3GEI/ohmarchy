#!/usr/bin/env bash
# Stage 3 support stack: the C/C++ libraries Hyprland links, cross-built for OHOS musl.
# All STATIC (.a, -fPIC) — they link into the Hyprland binary. Two compilers:
#   * C-API libs  -> NDK clang 15 (meson ohos.cross / autotools CC=clang15). Static only,
#     because macOS libtool cannot emit Linux ELF .so (its shared-lib link step fails).
#   * C++-API libs consumed by Hyprland (abseil, re2, muparser) -> clang 23 + the
#     ohos-cmake.toolchain, so their C++ ABI matches Hyprland/libc++_ohm.
#
# THREE environment fixes this stage needs (all one-time, see commits):
#  A. OHOS sysroot's linux/socket.h defines struct sockaddr_storage UNGUARDED, clashing with
#     musl sys/socket.h (breaks glib/gio). Shipped override uapi-fix/linux/socket.h guards it
#     with #ifndef _SYS_SOCKET_H; it's added to ohos.cross c_args as -isystem <uapi-fix>.
#  B. clang 23's resource dir has the intrinsic headers (arm_neon.h) but no OHOS builtins;
#     copy the NDK libclang_rt.builtins.a into `clang -print-resource-dir`/lib/aarch64-linux-ohos
#     once, so C++ compiles (neon) AND links (builtins) with the real resource dir.
#  C. musl keeps gettext inside libc, but some .pc add -lintl -> drop an empty libintl.a stub.
set -euo pipefail
SP="${SP:?}"; NDK="${NDK:-/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/native}"
PREFIX="$SP/stage1/prefix"; export PATH="/opt/homebrew/opt/bison/bin:$SP/pyenv/bin:$PATH"
XC="$SP/stage1/ohos.cross"; CTC="$SP/stage3/ohos-c-cmake.toolchain"; CXXTC="$SP/stage3/ohos-cmake.toolchain"
# fix B
RRES=$(/opt/homebrew/opt/llvm/bin/clang -print-resource-dir); mkdir -p "$RRES/lib/aarch64-linux-ohos"
cp "$NDK/llvm/lib/clang/15.0.4/lib/aarch64-linux-ohos/libclang_rt.builtins.a" "$RRES/lib/aarch64-linux-ohos/"
# host python for meson builds: mako packaging pyyaml already installed in $SP/pyenv

# --- autotools C libs (static) ---  CC=NDK clang15
ATCC="$NDK/llvm/bin/clang --target=aarch64-linux-ohos"
export AR="$NDK/llvm/bin/llvm-ar" RANLIB="$NDK/llvm/bin/llvm-ranlib"
export CFLAGS="-O2 -fPIC -I$PREFIX/include" CPPFLAGS="-I$PREFIX/include" LDFLAGS="-L$PREFIX/lib"
export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig"
at(){ local d="$1"; shift; cd "$SP/stage3/csrc/$d"; rm -rf _b; mkdir _b; cd _b
  CC="$ATCC" ../configure --host=aarch64-linux-gnu --prefix="$PREFIX" --disable-shared --enable-static "$@"
  make -j4; make install; }
at pcre2-ex
at lcms2-ex --without-jpeg --without-tiff
at libpng-ex
# --- cmake C libs (static) ---
cm(){ local tc="$1" d="$2"; shift 2; cd "$SP/stage3/csrc/$d"; rm -rf _b
  cmake -B _b -G Ninja -DCMAKE_TOOLCHAIN_FILE="$tc" -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" -DBUILD_SHARED_LIBS=OFF -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DPKG_CONFIG_EXECUTABLE=/opt/homebrew/bin/pkg-config "$@"; ninja -C _b; ninja -C _b install; }
cm "$CTC" libjpegturbo-ex -DENABLE_SHARED=0 -DENABLE_STATIC=1 -DWITH_SIMD=0
cm "$CTC" libwebp-ex -DWEBP_BUILD_CWEBP=0 -DWEBP_BUILD_DWEBP=0 -DWEBP_BUILD_GIF2WEBP=0 -DWEBP_BUILD_IMG2WEBP=0 -DWEBP_BUILD_VWEBP=0 -DWEBP_BUILD_WEBPINFO=0 -DWEBP_BUILD_WEBPMUX=0 -DWEBP_BUILD_EXTRAS=0 -DWEBP_BUILD_ANIM_UTILS=0
cm "$CTC" freetype-ex -DFT_DISABLE_HARFBUZZ=ON -DFT_DISABLE_BROTLI=ON -DFT_REQUIRE_PNG=ON -DFT_REQUIRE_ZLIB=ON
# --- meson C libs (static) ---
ms(){ local d="$1"; shift; cd "$SP/stage3/csrc/$d"; rm -rf _b
  meson setup _b --cross-file "$XC" --prefix="$PREFIX" --default-library=static "$@"
  meson compile -C _b; meson install -C _b --no-rebuild; }
ms fribidi-ex -Dtests=false -Ddocs=false -Dbin=false
ms harfbuzz-ex -Dtests=disabled -Ddocs=disabled -Dutilities=disabled -Dcairo=disabled -Dglib=disabled -Dgobject=disabled -Dicu=disabled -Dfreetype=enabled
ms fontconfig-ex -Dtests=disabled -Dtools=disabled -Ddoc=disabled -Dcache-build=disabled -Dnls=disabled
ms glib-ex -Dtests=false -Dnls=disabled -Dselinux=disabled -Dlibmount=disabled -Dxattr=false -Dman-pages=disabled -Ddtrace=disabled -Dsystemtap=disabled -Dglib_debug=disabled -Dintrospection=disabled
ms cairo-ex -Dxlib=disabled -Dxcb=disabled -Dquartz=disabled -Dtests=disabled -Dspectre=disabled -Dsymbol-lookup=disabled -Dglib=enabled -Dfreetype=enabled -Dfontconfig=enabled -Dpng=enabled -Dzlib=enabled
ms pango-ex -Dintrospection=disabled -Ddocumentation=false -Dxft=disabled -Dfontconfig=enabled -Dfreetype=enabled -Dcairo=enabled || true  # tools fail on -lintl; libs install
# fix C
printf '' | "$NDK/llvm/bin/clang" --target=aarch64-linux-ohos -c -x c - -o /tmp/empty_intl.o
"$NDK/llvm/bin/llvm-ar" rcs "$PREFIX/lib/libintl.a" /tmp/empty_intl.o
# --- cmake C++ libs (clang 23, static) ---
cm "$CXXTC" abseil-ex -DABSL_PROPAGATE_CXX_STD=ON -DABSL_ENABLE_INSTALL=ON -DCMAKE_CXX_STANDARD=17
cm "$CXXTC" re2-ex -DRE2_BUILD_TESTING=OFF -DCMAKE_CXX_STANDARD=17
cm "$CXXTC" muparser-ex -DENABLE_SAMPLES=OFF -DENABLE_OPENMP=OFF -DBUILD_TESTING=OFF
echo "Stage 3 support stack done."
