#!/bin/bash
# Inputs for the app's in-process GPU renderer (entry/src/main/cpp/gpu.cpp):
#  - the device's own libvirglrenderer.so.1 and libepoxy.so.0, copied into the HAP as
#    libvirglrenderer.so and libepoxy.so (HAP libraries must end in .so; the names
#    inside are patched to match, same length or shorter);
#  - upstream virglrenderer 1.1.1's vtest server, patched to take clients from
#    native/vtest/vtest-broker and to present frames (vtest-inapp.patch).
# Runs on the machine with DevEco Studio; needs the device (ssh) and network once.
#   OHOS_HOST  ssh host with a root shell on the HarmonyOS PC (default: ohdev)
set -e
cd "$(dirname "$0")"
HOST=${OHOS_HOST:-ohdev}
LIBS=entry/libs/arm64-v8a
GPU=entry/src/main/cpp/gpu
mkdir -p "$LIBS" "$GPU"

fetch() {  # device library -> local file, checked by size
    local size
    size=$(ssh "$HOST" "wc -c < $1" | tr -d ' \r')
    ssh "$HOST" "cat $1" > "$2"
    [ "$(wc -c < "$2" | tr -d ' ')" = "$size" ] || { echo "short copy of $1" >&2; exit 1; }
}
rename_in() {  # replace NUL-terminated name $2 by $3 (not longer) in file $1
    python3 - "$@" <<'PY'
import sys
f, old, new = sys.argv[1], sys.argv[2].encode() + b'\0', sys.argv[3].encode() + b'\0'
d = open(f, 'rb').read()
assert len(new) <= len(old) and d.count(old) >= 1, (f, old)
open(f, 'wb').write(d.replace(old, new.ljust(len(old), b'\0')))
PY
}
if [ ! -s "$LIBS/libvirglrenderer.so" ]; then
    fetch /system/lib64/libvirglrenderer.so.1 "$LIBS/libvirglrenderer.so"
    rename_in "$LIBS/libvirglrenderer.so" libvirglrenderer.so.1 libvirglrenderer.so
    rename_in "$LIBS/libvirglrenderer.so" libepoxy.so.0 libepoxy.so
fi
if [ ! -s "$LIBS/libepoxy.so" ]; then
    fetch /system/lib64/libepoxy.so.0 "$LIBS/libepoxy.so"
    rename_in "$LIBS/libepoxy.so" libepoxy.so.0 libepoxy.so
fi

if [ ! -d "$GPU/virglrenderer" ]; then
    git clone -q --depth 1 --branch 1.1.1 https://gitlab.freedesktop.org/virgl/virglrenderer.git "$GPU/virglrenderer"
    git -C "$GPU/virglrenderer" apply "$PWD/vtest-inapp.patch"
fi
sed -e 's/@VIRGL_MAJOR_VERSION@/1/; s/@VIRGL_MINOR_VERSION@/1/; s/@VIRGL_MICRO_VERSION@/1/' \
    "$GPU/virglrenderer/src/virgl-version.h.meson" > "$GPU/virgl-version.h"
cat > "$GPU/config.h" <<'H'
/* minimal config for vtest in the app, against the system libvirglrenderer */
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
#define VTEST_BROKER 1
H
