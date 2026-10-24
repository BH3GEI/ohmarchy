#!/bin/bash
# session-py.sh NAME SCRIPT.py [timeout-s] [args...]
# Run a Python test script inside route D's desktop session, as the desktop user
# with the session's environment (Wayland, Hyprland instance, session bus), via
# remote.sh. Its JSON lines ($OUT) are printed after a "=== JSONL" marker.
#   ARCH_USER  desktop user (default builder)
name=$1; script=$2; tmo=${3:-1800}; shift 3 2>/dev/null
here=$(cd "$(dirname "$0")" && pwd)
user=${ARCH_USER:-builder}
args=$(printf '%q ' "$@")
{
    echo "mkdir -p /tmp/ohm-tests && chown $user /tmp/ohm-tests"
    echo "cat > /tmp/ohm-tests/$name.py <<'END_OF_PY'"
    cat "$script"
    echo "END_OF_PY"
    cat <<SH
su - $user -c 'export XDG_RUNTIME_DIR=/run/user/\$(id -u) WAYLAND_DISPLAY=wayland-1 PATH=/opt/ohmarchy/bin:\$PATH
export DBUS_SESSION_BUS_ADDRESS=unix:path=\$XDG_RUNTIME_DIR/bus
export HYPRLAND_INSTANCE_SIGNATURE=\$(hyprctl instances -j | python3 -c "import json,sys; print(json.load(sys.stdin)[0][\"instance\"])")
OUT=/tmp/ohm-tests/$name.jsonl python3 /tmp/ohm-tests/$name.py $args' < /dev/null
echo "=== JSONL"
cat /tmp/ohm-tests/$name.jsonl
SH
} | "$here/remote.sh" "$name" chroot "$tmo"
