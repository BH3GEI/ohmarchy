#!/bin/bash
# Benchmarks inside the Omarchy guest, in the running Hyprland session (run as the
# desktop user over ssh). Pair the animated parts with oseasy/measure-fps.sh on
# the workstation to count what reaches the HarmonyOS screen.
#   guest-bench.sh info              renderer and modes
#   guest-bench.sh gears [SECS]      es2gears_wayland, frames per second it reports
#   guest-bench.sh glmark2           glmark2-es2-wayland at 1280x720, score
#   guest-bench.sh workspaces [SECS] switch workspaces 1<->2 continuously (animations)
#   guest-bench.sh launch APP...     seconds from exec to the first mapped window
set -u
export XDG_RUNTIME_DIR=/run/user/$(id -u)
export WAYLAND_DISPLAY=$(ls "$XDG_RUNTIME_DIR" | grep -m1 '^wayland-[0-9]*$')
export HYPRLAND_INSTANCE_SIGNATURE=$(ls "$XDG_RUNTIME_DIR/hypr" | head -1)

case "${1:-info}" in
info)
    eglinfo -B -p wayland 2>/dev/null | grep -e 'OpenGL ES profile renderer' -e 'OpenGL ES profile version' -e 'OpenGL core profile renderer' | sort -u
    hyprctl monitors | grep -e 'Monitor' -e '@' | head -4
    cat /sys/module/vmwgfx/parameters/hvm_refresh 2>/dev/null | sed 's/^/vmwgfx hvm_refresh=/'
    ;;
gears)
    timeout "${2:-12}" es2gears_wayland 2>&1 | grep -i fps
    ;;
glmark2)
    glmark2-es2-wayland --size 1280x720 2>&1 | grep -e 'GL_RENDERER' -e 'glmark2 Score' -e 'FPS' | tail -40
    ;;
workspaces)
    end=$(( $(date +%s) + ${2:-10} ))
    while [ "$(date +%s)" -lt "$end" ]; do
        hyprctl dispatch workspace 2 >/dev/null; sleep 0.4
        hyprctl dispatch workspace 1 >/dev/null; sleep 0.4
    done
    ;;
launch)
    shift
    for app in "$@"; do
        before=$(hyprctl clients | grep -c '^Window')
        t0=$(date +%s.%N)
        hyprctl dispatch exec "$app" >/dev/null
        for _ in $(seq 1 300); do
            [ "$(hyprctl clients | grep -c '^Window')" -gt "$before" ] && break
            sleep 0.05
        done
        echo "$app: $(echo "$(date +%s.%N) - $t0" | bc) s"
        sleep 1; hyprctl dispatch killactive >/dev/null; sleep 1
    done
    ;;
esac
