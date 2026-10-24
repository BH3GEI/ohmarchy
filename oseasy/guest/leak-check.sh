#!/bin/bash
# Leak check for the GEM_CLOSE fallback in vmwgfx-oseasy (root, in the guest):
# vmwgfx memory managers and kernel memory before and after 2 x 2000 rounds of
# create/export/prime-import/GEM_CLOSE/destroy (prime-close COUNT), then the
# kernel log for refcount/KASAN/use-after-free warnings.
#   leak-check.sh /path/to/prime-close
P=${1:-/tmp/prime-close}
mountpoint -q /sys/kernel/debug || mount -t debugfs debugfs /sys/kernel/debug
mem() {
    for f in mob_ttm system_mob_ttm system_ttm vram_ttm; do
        echo "  $f: $(head -c 300 /sys/kernel/debug/dri/0/$f | tr -s ' \n' ' ')"
    done
    echo "  $(grep -e MemAvailable -e '^Slab' /proc/meminfo | tr -s ' \n' ' ')"
}
echo "before:"; mem
dmesg -C
"$P" /dev/dri/renderD128 /dev/dri/card0 2000
"$P" /dev/dri/renderD128 /dev/dri/card0 2000
sleep 2
echo "after:"; mem
echo "kernel log: $(dmesg | grep -i -c -e refcount -e kasan -e use-after -e 'WARNING' -e 'BUG') warnings"
dmesg | grep -i -e refcount -e kasan -e use-after -e 'WARNING' -e 'BUG' | head -5
