#!/usr/bin/env bash
# Convert the Omarchy qcow2 to a raw disk image and record its layout.
set -euo pipefail
. "$(dirname "$0")/config.sh"
need qemu-img sfdisk blkid python3
cd "$WORK"
[ -s omarchy.raw ] || qemu-img convert -p -O raw dl/omarchy-aarch64-virt.qcow2 omarchy.raw
sfdisk --json omarchy.raw > layout.json
python3 - <<'PY' > image.env
import json
t = json.load(open('layout.json'))['partitiontable']
ss = t.get('sectorsize', 512)
for p in t['partitions']:
    if p['type'].upper() == 'C12A7328-F81F-11D2-BA4B-00A0C93EC93B':
        print(f"ESP_OFFSET={p['start'] * ss}")
    elif p['type'].upper() in ('0FC63DAF-8483-4772-8E79-3D69D8477DE4', 'B921B045-1DF0-41C3-AF44-4C6F280D3FAE'):
        print(f"ROOT_OFFSET={p['start'] * ss}")
PY
. ./image.env
echo "ROOT_UUID=$(blkid -p -O "$ROOT_OFFSET" -s UUID -o value omarchy.raw)" >> image.env
cat image.env
