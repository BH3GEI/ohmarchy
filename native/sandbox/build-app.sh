#!/bin/bash
# Build the sandbox's display app from native/app, next to the demo's and never over it:
# bundle com.ohmarchy.sandbox (internal id; the user sees "Omarchy（原生应用）"), a recoloured icon, a "Reset Linux"
# shortcut, and its own abstract socket names (prefix ohmsbx: @ohmsbx-display, -vtest,
# -audio, -ime, and -ctl for the helper ohm-sandboxd).
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
sed -i '' 's/"Omarchy (native)"/"Omarchy（原生应用）"/' AppScope/resources/base/element/string.json \
    entry/src/main/resources/base/element/string.json
printf '#pragma once\n#define OHM_NAME_PREFIX "ohmsbx"\n#define OHM_SANDBOX 1\n' > entry/src/main/cpp/ohm_names.h
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
# "权限设置" and "Reset Linux" in the icon's menu: shortcuts whose want carries action
cat > entry/src/main/resources/base/profile/shortcuts_config.json <<'J'
{
  "shortcuts": [
    {
      "shortcutId": "settings",
      "label": "$string:settings_label",
      "icon": "$media:startIcon",
      "wants": [
        {
          "bundleName": "com.ohmarchy.sandbox",
          "moduleName": "entry",
          "abilityName": "EntryAbility",
          "parameters": { "action": "settings" }
        }
      ]
    },
    {
      "shortcutId": "reset",
      "label": "$string:reset_label",
      "icon": "$media:startIcon",
      "wants": [
        {
          "bundleName": "com.ohmarchy.sandbox",
          "moduleName": "entry",
          "abilityName": "EntryAbility",
          "parameters": { "action": "reset" }
        }
      ]
    }
  ]
}
J
python3 - entry/src/main/module.json5 entry/src/main/resources/base/element/string.json <<'P2'
import sys
m, st = sys.argv[1], sys.argv[2]
s = open(m).read()
o = '"startWindowBackground": "$color:start_window_background",'
assert s.count(o) == 1
s = s.replace(o, o + '\n        "metadata": [{ "name": "ohos.ability.shortcuts", "resource": "$profile:shortcuts_config" }],')
open(m, 'w').write(s)
s = open(st).read()
o = '"string": ['
assert s.count(o) == 1
s = s.replace(o, o + '\n    { "name": "reset_label", "value": "Reset Linux" },\n    { "name": "settings_label", "value": "权限设置" },')
open(st, 'w').write(s)
P2
grep -q com.ohmarchy.sandbox AppScope/app.json5 && grep -q 'Omarchy（原生应用）' entry/src/main/resources/base/element/string.json
BUNDLE=com.ohmarchy.sandbox UDID=$UDID ./build.sh --no-install
cp ohdisp.hap "$here/ohm-sandbox.hap"
echo "built $here/ohm-sandbox.hap"
