#!/bin/bash
# Turn build-disk.sh's raw omarchy-pure.img into a qcow2 that 鸿融's
# "导入 qcow2" accepts. Used on 2026-10-26: the result imported through the
# 鸿融 1.1.1.103 UI and booted.
# What 鸿融 checks (docs/hongrong-whole-os.md, Developer image):
#   - tables within the file: create the qcow2 at its final virtual size
#     (256 GiB) and convert into it; an image grown later with qemu-img resize
#     was rejected;
#   - os_type 1 in byte 255 of a 256-byte header: qcow2-stratovirt-header.py.
# Runs where qemu-img and python3 exist (e.g. the native Arch environment).
# Usage: make-qcow2.sh RAW.img OUT.qcow2 [VIRTUAL_SIZE, default 256G]
set -euo pipefail
raw=${1:?raw image}; out=${2:?output qcow2}; size=${3:-256G}
rm -f "$out"
qemu-img create -q -f qcow2 -o cluster_size=65536,compat=1.1,lazy_refcounts=off "$out" "$size"
qemu-img convert -n -f raw -O qcow2 "$raw" "$out"
python3 "$(dirname "$0")/qcow2-stratovirt-header.py" "$out"
qemu-img check "$out" | tail -2
