#!/usr/bin/env bash
# Remaster the Debian netinst ISO to carry the Omarchy disk image plus the
# writer scripts. Oseasy boots it like any installer.
set -euo pipefail
. "$(dirname "$0")/config.sh"
need xorriso gzip
cd "$WORK"; . ./image.env
Z=gzip; command -v pigz >/dev/null && Z=pigz
echo "compressing omarchy.raw (sparse 64 GiB, takes a few minutes)"
$Z -1 -c omarchy.raw > omarchy.raw.gz
dd if=omarchy.raw bs=1M skip=$((ESP_OFFSET / 1048576)) count=1024 status=none | $Z -1 -c > esp.img.gz
rm -f omarchy-install.iso
xorriso -indev "dl/${NETINST_URL##*/}" -outdev omarchy-install.iso -boot_image any replay \
    -map omarchy.raw.gz /omarchy.raw.gz -map esp.img.gz /esp.img.gz \
    -map "$OHMARCHY_ROOT/oseasy/installer/omarchy-write.sh" /omarchy-write.sh \
    -map "$OHMARCHY_ROOT/oseasy/installer/write-esp.sh" /write-esp.sh -commit
sha256sum omarchy-install.iso | tee omarchy-install.iso.sha256
