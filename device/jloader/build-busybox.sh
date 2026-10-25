#!/usr/bin/env bash
# Build busybox 1.36.1 as a HAP-loadable shared object (libbusybox.so) with the OHOS
# clang/musl toolchain. Standalone shell runs applets in-process (fork, no execve), so a
# signed-into-HAP busybox.so gives a no-root shell on ohdev. Usage: build-busybox.sh <src>
set -e
NDK=${NDK:-/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/native}
LB=$NDK/llvm/bin; SRC=${1:?busybox-1.36.1 source dir}; cd "$SRC"
make allnoconfig >/dev/null
for s in ASH SHELL_ASH ASH_JOB_CONTROL ASH_CMDCMD ASH_INTERNAL_GLOB FEATURE_SH_MATH \
         FEATURE_SH_STANDALONE FEATURE_PREFER_APPLETS LS WC SLEEP CAT PWD ECHO TEST PRINTF KILL; do
  grep -q "# CONFIG_$s is not set" .config && sed -i '' "s/# CONFIG_$s is not set/CONFIG_$s=y/" .config || echo "CONFIG_$s=y" >> .config
done
make olddefconfig >/dev/null; make clean >/dev/null
CC="$LB/clang --target=aarch64-linux-ohos --sysroot=$NDK/sysroot"
make -j4 ARCH=arm64 CC="$CC" HOSTCC=clang AR="$LB/llvm-ar" STRIP="$LB/llvm-strip" NM="$LB/llvm-nm" OBJCOPY="$LB/llvm-objcopy" \
  CONFIG_EXTRA_CFLAGS="-fPIC -Wno-everything -D_GNU_SOURCE" SKIP_STRIP=y busybox
"$LB/clang" --target=aarch64-linux-ohos --sysroot=$NDK/sysroot -shared -fPIC -o libbusybox.so \
  -Wl,--whole-archive */built-in.o */lib.a -Wl,--no-whole-archive -Wl,--allow-multiple-definition
echo "built: $SRC/libbusybox.so"
