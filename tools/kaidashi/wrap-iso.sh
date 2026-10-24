#!/bin/bash
# Make any UEFI-bootable ISO acceptable to 铠大师: add a fake Windows 11 24H2
# ARM64 sources/install.wim (make-fake-wim.sh) and Joliet names, keep the boot
# catalogue and everything else as is.
#   tools/kaidashi/wrap-iso.sh IN.iso OUT.iso
# Used for route B's oseasy-probe.iso (vmwgfx-oseasy test) as kds-oseasy-probe.iso.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
in=${1:?in.iso} out=${2:?out.iso}
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
"$here/make-fake-wim.sh" "$tmp/install.wim"
rm -f "$out"
xorriso -indev "$in" -outdev "$out" -map "$tmp/install.wim" /sources/install.wim \
  -joliet on -boot_image any replay 2>&1 | tail -1
ls -l "$out"
