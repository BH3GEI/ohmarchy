#!/bin/bash
# Build the host side of Hyprland's GPU path for HarmonyOS (musl, OpenHarmony NDK):
#  - vtest-broker: passes Mesa virpipe's connections (/tmp/.virgl_test in the Arch
#    chroot) to the display app, which renders and presents them itself (default);
#  - virgl_test_server: renders on the host instead, against the system's own
#    libvirglrenderer.so.1 (an OpenHarmony port: zink on the Maleoon GPU's Vulkan);
#    frames are then read back to the CPU (OHMARCHY_GPU=host, or no app).
# Runs on the machine with DevEco Studio; needs network for the virglrenderer source.
#   OHOS_HOST  ssh host with a root shell on the HarmonyOS PC (default: ohdev)
#   OUT        output directory (default: ./build)
set -e
cd "$(dirname "$0")"
SRC=$PWD
HOST=${OHOS_HOST:-ohdev}
OUT=${OUT:-$PWD/build}
NDK=${OHOS_NDK:-/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/native}
mkdir -p "$OUT" && cd "$OUT"

# Link against the device's library; only its public API is used.
[ -s libvirglrenderer.so.1 ] || ssh -tt "$HOST" 'base64 /system/lib64/libvirglrenderer.so.1' 2>/dev/null \
    | tr -d '\r' | grep -v '^Connection' | base64 -d > libvirglrenderer.so.1
[ -d virglrenderer ] || git clone -q --depth 1 --branch 1.1.1 https://gitlab.freedesktop.org/virgl/virglrenderer.git

cat > config.h <<'H'
/* minimal config for vtest against the system libvirglrenderer on OpenHarmony */
#define _GNU_SOURCE 1
#define NDEBUG 1
#define HAVE_EVENTFD_H 1
#define HAVE_SYS_SELECT_H 1
#define HAVE_SYS_UIO_H 1
#define HAVE_PTHREAD 1
#define HAVE_FUNC_ATTRIBUTE_VISIBILITY 1
#define HAVE_FUNC_ATTRIBUTE_PACKED 1
#define HAVE_FUNC_ATTRIBUTE_FORMAT 1
#define HAVE_FUNC_ATTRIBUTE_UNUSED 1
#define HAVE_FUNC_ATTRIBUTE_NORETURN 1
#define HAVE___BUILTIN_EXPECT 1
#define HAVE___BUILTIN_CLZ 1
#define HAVE___BUILTIN_CLZLL 1
#define HAVE___BUILTIN_FFS 1
#define HAVE___BUILTIN_FFSLL 1
#define HAVE___BUILTIN_POPCOUNT 1
#define HAVE___BUILTIN_POPCOUNTLL 1
#define UTIL_ARCH_LITTLE_ENDIAN 1
#define UTIL_ARCH_BIG_ENDIAN 0
#define PACKAGE_VERSION "1.1.1-ohos"
#define VIRGL_RENDERER_UNSTABLE_APIS 1
H
sed -e 's/@VIRGL_MAJOR_VERSION@/1/; s/@VIRGL_MINOR_VERSION@/1/; s/@VIRGL_MICRO_VERSION@/1/' \
    virglrenderer/src/virgl-version.h.meson > virgl-version.h

V=virglrenderer
"$NDK/llvm/bin/clang" --target=aarch64-linux-ohos --sysroot="$NDK/sysroot" -O2 -fPIC -include config.h \
    -I. -I$V/src -I$V/src/gallium/include -I$V/src/gallium/include/pipe -I$V/src/mesa/pipe \
    -I$V/src/gallium/auxiliary -I$V/src/mesa -I$V/src/mesa/util -I$V/src/mesa/compat -I$V/vtest \
    $V/vtest/util.c $V/vtest/vtest_shm.c $V/vtest/vtest_server.c $V/vtest/vtest_renderer.c $V/vtest/vtest_main.c \
    $V/src/mesa/util/ralloc.c $V/src/mesa/util/hash_table.c $V/src/gallium/auxiliary/util/u_hash_table.c \
    -L. -l:libvirglrenderer.so.1 -lm -o virgl_test_server
"$NDK/llvm/bin/clang" --target=aarch64-linux-ohos --sysroot="$NDK/sysroot" -O2 -Wall \
    "$SRC/vtest-broker.c" -o vtest-broker
ls -l "$OUT/vtest-broker" "$OUT/virgl_test_server"
echo "copy both to the host as <native base>/bin/; 'omarchy desktop start' runs one"
