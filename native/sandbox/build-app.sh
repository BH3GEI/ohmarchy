#!/bin/bash
# Build the sandbox's display app from native/app, next to the demo's and never over it:
# bundle com.ohmarchy.sandbox, "Omarchy (sandbox)", a recoloured icon, and its own
# abstract socket names (prefix ohmsbx: @ohmsbx-display, -vtest, -audio, -ime).
#   UDID=<bm get --udid> native/sandbox/build-app.sh   ->  native/sandbox/ohm-sandbox.hap
# Needs DevEco Studio's command-line tools (as native/app/build.sh) and Python's Pillow.
set -e
here=$(cd "$(dirname "$0")" && pwd)
src=$here/../app
work=${TMPDIR:-/tmp}/ohm-sandbox-app
: "${UDID:?set UDID to the device id from bm get --udid}"
rm -rf "$work" && mkdir -p "$work"
rsync -a --exclude entry/build --exclude .hvigor --exclude ohdisp.hap "$src/" "$work/"
cd "$work"
sed -i '' 's/"com\.ohmarchy\.display"/"com.ohmarchy.sandbox"/' AppScope/app.json5
sed -i '' 's/"Omarchy (native)"/"Omarchy (sandbox)"/' AppScope/resources/base/element/string.json \
    entry/src/main/resources/base/element/string.json
printf '#pragma once\n#define OHM_NAME_PREFIX "ohmsbx"\n' > entry/src/main/cpp/ohm_names.h
python3 - AppScope/resources/base/media/background.png entry/src/main/resources/base/media/background.png <<'P'
import sys
from PIL import Image
for p in sys.argv[1:]:  # rotate the hue a third of the way round: same icon, other colour
    im = Image.open(p).convert("RGBA")
    h, s, v = im.convert("RGB").convert("HSV").split()
    h = h.point(lambda x: (x + 85) % 256)
    out = Image.merge("HSV", (h, s, v)).convert("RGB")
    out.putalpha(im.getchannel("A"))
    out.save(p)
P
grep -q com.ohmarchy.sandbox AppScope/app.json5 && grep -q 'Omarchy (sandbox)' entry/src/main/resources/base/element/string.json
BUNDLE=com.ohmarchy.sandbox UDID=$UDID ./build.sh --no-install
cp ohdisp.hap "$here/ohm-sandbox.hap"
echo "built $here/ohm-sandbox.hap"
