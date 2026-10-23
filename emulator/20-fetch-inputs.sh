#!/usr/bin/env bash
# Fetch Aetherium, the Omarchy AArch64 image and (optionally) RemoteDesk; verify; patch Aetherium.
set -euo pipefail
. "$(dirname "$0")/config.sh"
cd "$WORK"

gh_fetch() {  # gh_fetch REPO TAG PATTERN...
    local repo=$1 tag=$2; shift 2
    local args=(); for p in "$@"; do args+=(-p "$p"); done
    gh release download "$tag" -R "$repo" "${args[@]}" --skip-existing
}

gh_fetch "$AETH_REPO" "$AETH_TAG" "$AETH_HAP"
sha_check "$AETH_HAP" "$AETH_SHA256"
python3 -I "$ROOT/emulator/lib/patch_aetherium.py" "$AETH_HAP" aetherium-patched.hap

if [ ! -f omarchy-aarch64-virt.qcow2 ]; then
    gh_fetch "$OMARCHY_REPO" "$OMARCHY_TAG" 'Omarchy-virt.utm.zip.part-*'
    cat Omarchy-virt.utm.zip.part-* > Omarchy-virt.utm.zip
    sha_check Omarchy-virt.utm.zip "$OMARCHY_ZIP_SHA256"
    unzip -o -j Omarchy-virt.utm.zip 'Omarchy-virt.utm/Data/omarchy-aarch64-virt.qcow2'
    rm -f Omarchy-virt.utm.zip Omarchy-virt.utm.zip.part-*
fi

if [ "${WITH_REMOTEDESK:-1}" = 1 ]; then
    gh_fetch "$RD_REPO" "$RD_TAG" "$RD_HAP"
    sha_check "$RD_HAP" "$RD_SHA256"
fi
ls -la "$WORK"
