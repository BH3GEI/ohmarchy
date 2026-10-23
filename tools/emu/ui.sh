#!/usr/bin/env bash
# ui.sh: drive the HarmonyOS emulator's UI over hdc (only targets 127.0.0.1:*, never a USB device)
#   ui.sh tap X Y        tap at device pixels (the 2in1 screen is 3120x2080)
#   ui.sh text X Y STR   focus the field at X Y and type STR (the IME may turn letters into pinyin;
#                        `ui.sh key 2054` (Enter) commits the raw letters)
#   ui.sh key CODE       key event (2054 Enter, 2055 Backspace)
#   ui.sh shot NAME      screenshot -> $OUT/NAME.jpeg (scaled to 1600 px wide on macOS)
set -euo pipefail
: "${HDC:=hdc}" "${OUT:=/tmp/ohmarchy}"
mkdir -p "$OUT"
T=$("$HDC" list targets | grep -m1 '^127\.0\.0\.1:') || { echo "emulator not connected" >&2; exit 1; }
h() { "$HDC" -t "$T" "$@"; }
case "$1" in
    tap)  h shell uitest uiInput click "$2" "$3" >/dev/null ;;
    text) h shell uitest uiInput inputText "$2" "$3" "$4" >/dev/null ;;
    key)  h shell uitest uiInput keyEvent "$2" >/dev/null ;;
    shot) h shell snapshot_display -f "/data/local/tmp/$2.jpeg" >/dev/null
          h file recv "/data/local/tmp/$2.jpeg" "$OUT/$2.jpeg" >/dev/null
          command -v sips >/dev/null && sips -Z 1600 "$OUT/$2.jpeg" >/dev/null
          echo "$OUT/$2.jpeg" ;;
    *) sed -n '2,8p' "$0"; exit 1 ;;
esac
