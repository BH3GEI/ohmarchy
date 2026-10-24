#!/bin/bash
# Write a tiny WIM whose XML metadata reads as Windows 11 Pro 24H2 (10.0.26100)
# ARM64 (ARCH 12), the only thing 铠大师's ISO check looks at
# (CheckISOVersion: ARCH, MAJOR/MINOR/BUILD/SPBUILD, name WINDOWS 11).
#   tools/kaidashi/make-fake-wim.sh OUT.wim
set -euo pipefail
out=$1; tmp=$(mktemp -d)
echo "Not Windows: placeholder for the Omarchy installer (ohmarchy route G)." > "$tmp/README.txt"
rm -f "$out"
wimlib-imagex capture "$tmp" "$out" "Windows 11 Pro" "Windows 11 Pro" --compress=none >/dev/null
for kv in WINDOWS/ARCH=12 "WINDOWS/PRODUCTNAME=Microsoft® Windows® Operating System" \
  WINDOWS/EDITIONID=Professional WINDOWS/INSTALLATIONTYPE=Client WINDOWS/PRODUCTTYPE=WinNT \
  WINDOWS/VERSION/MAJOR=10 WINDOWS/VERSION/MINOR=0 WINDOWS/VERSION/BUILD=26100 \
  WINDOWS/VERSION/SPBUILD=1742 WINDOWS/VERSION/SPLEVEL=0 \
  WINDOWS/LANGUAGES/LANGUAGE=zh-CN WINDOWS/LANGUAGES/DEFAULT=zh-CN FLAGS=Professional \
  "DISPLAYNAME=Windows 11 Pro" "DISPLAYDESCRIPTION=Windows 11 Pro"; do
  wimlib-imagex info "$out" 1 --image-property "$kv" >/dev/null
done
rm -rf "$tmp"
