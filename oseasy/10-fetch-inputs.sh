#!/usr/bin/env bash
# Download and verify the inputs: Omarchy AArch64 image, Debian 6.1 kernel and
# header packages, Debian arm64 netinst ISO. Everything lands in $WORK/dl.
set -euo pipefail
. "$(dirname "$0")/config.sh"
need curl sha256sum unzip
mkdir -p "$WORK/dl"; cd "$WORK/dl"

fetch() {
    local url=$1 f=${2:-${1##*/}}
    [ -s "$f" ] && return 0
    echo "fetch $url"
    curl -fL --retry 3 -o "$f.part" "$url"
    mv "$f.part" "$f"
}

# Debian kernel image + headers (headers and kbuild are only needed for the modules)
A=$(host_deb_arch)
P=$DEBIAN_MIRROR/pool/main/l/linux
fetch "$P/linux-image-$KVER-unsigned_${KPKG}_arm64.deb"
fetch "$P/linux-headers-${KVER}_${KPKG}_arm64.deb"
fetch "$P/linux-headers-${KVER%-arm64}-common_${KPKG}_all.deb"
fetch "$P/linux-kbuild-${KBUILD_SERIES}_${KPKG}_${A}.deb"

# Debian installer ISO (the carrier Oseasy will boot)
if [ -n "$NETINST_ISO" ]; then
    ln -sf "$(realpath "$NETINST_ISO")" "${NETINST_URL##*/}"
else
    fetch "$NETINST_URL"
fi

# Omarchy AArch64 VM image (UTM bundle split in two parts)
if [ -n "$OMARCHY_QCOW2" ]; then
    ln -sf "$(realpath "$OMARCHY_QCOW2")" omarchy-aarch64-virt.qcow2
elif [ ! -s omarchy-aarch64-virt.qcow2 ]; then
    R=https://github.com/riverscn/omarchy-aarch64-image/releases/download/$OMARCHY_RELEASE
    fetch "$R/SHA256SUMS" omarchy-SHA256SUMS
    fetch "$R/Omarchy-virt.utm.zip.part-00"
    fetch "$R/Omarchy-virt.utm.zip.part-01"
    grep -E 'utm\.zip\.part-0[01]$' omarchy-SHA256SUMS | sha256sum -c -
    cat Omarchy-virt.utm.zip.part-00 Omarchy-virt.utm.zip.part-01 > Omarchy-virt.utm.zip
    unzip -o -j Omarchy-virt.utm.zip '*.qcow2' -d .
    q=$(ls ./*.qcow2 | grep -v omarchy-aarch64-virt.qcow2 | head -1 || true)
    [ -n "$q" ] && mv "$q" omarchy-aarch64-virt.qcow2
    rm -f Omarchy-virt.utm.zip
fi

# Verify what we have pinned (the kernel image deb is checked by apt's own
# Release signatures upstream; record its hash for reproducibility)
sha256sum -c --ignore-missing "$OHMARCHY_ROOT/oseasy/inputs.sha256"
sha256sum "linux-image-$KVER-unsigned_${KPKG}_arm64.deb"
echo "inputs ready in $WORK/dl"
