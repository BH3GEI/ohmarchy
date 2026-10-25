#!/bin/bash
# Fetch the emulator and terminal into webemu/vendor/: v86 (BSD-2-Clause, npm build
# with libv86.js + v86.wasm), its SeaBIOS/VGA BIOS (LGPL-3.0, from the v86 repo at the
# matching tag), xterm.js (MIT). Pinned versions.
set -e
cd "$(dirname "$0")"
V86=0.5.472 XTERM=6.0.0 V86_REV=${V86_REV:-master}
mkdir -p vendor && cd vendor
t=$(mktemp -d)
curl -fsSL https://registry.npmjs.org/v86/-/v86-$V86.tgz | tar xz -C $t
cp $t/package/build/libv86.js $t/package/build/v86.wasm $t/package/build/v86-fallback.wasm $t/package/LICENSE .
mv LICENSE LICENSE.v86
rm -rf $t/package
curl -fsSL https://registry.npmjs.org/@xterm/xterm/-/xterm-$XTERM.tgz | tar xz -C $t
cp $t/package/lib/xterm.js $t/package/css/xterm.css .
cp $t/package/LICENSE LICENSE.xterm
rm -rf $t
for f in seabios.bin vgabios.bin; do curl -fsSL -o $f https://github.com/copy/v86/raw/$V86_REV/bios/$f; done
ls -la
