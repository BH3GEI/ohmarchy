#!/bin/bash
# Launch test of every Omarchy app in the native desktop (tests/apps/launch_all.py).
# Runs on the machine driving the HarmonyOS host; the results land in
# tests/results/launch-<time>.jsonl here and a summary is printed.
#   ONLY=id1,id2  test only these app ids;  ARCH_USER  desktop user (default builder)
set -e
here=$(cd "$(dirname "$0")" && pwd)
user=${ARCH_USER:-builder}
mkdir -p "$here/../results"
res="$here/../results/launch-$(date +%Y%m%d-%H%M%S).jsonl"
tmp=$(mktemp)
{
    echo "mkdir -p /tmp/ohm-tests && chown $user /tmp/ohm-tests"
    echo "cat > /tmp/ohm-tests/launch_all.py <<'END_OF_PY'"
    cat "$here/launch_all.py"
    echo "END_OF_PY"
    cat <<SH
su - $user -c 'export XDG_RUNTIME_DIR=/run/user/\$(id -u) WAYLAND_DISPLAY=wayland-1 PATH=/opt/ohmarchy/bin:\$PATH ONLY=${ONLY:-}
export HYPRLAND_INSTANCE_SIGNATURE=\$(hyprctl instances -j | python3 -c "import json,sys; print(json.load(sys.stdin)[0][\"instance\"])")
OUT=/tmp/ohm-tests/launch.jsonl python3 /tmp/ohm-tests/launch_all.py' < /dev/null
echo "=== JSONL"
cat /tmp/ohm-tests/launch.jsonl
SH
} | "$here/../lib/remote.sh" apps-launch chroot "${TIMEOUT:-3600}" > "$tmp" || true
sed '/^=== JSONL/,$d' "$tmp"
sed -n '/^=== JSONL/,$p' "$tmp" | tail -n +2 > "$res"
rm -f "$tmp"
python3 "$here/summary.py" "$res"
echo "results: $res"
