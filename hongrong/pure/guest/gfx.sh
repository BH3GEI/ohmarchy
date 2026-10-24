#!/bin/bash
# Run as the desktop user over ssh in the guest: GPU benchmarks on the running
# Hyprland session. Usage: gfx.sh glmark2|gears [SECONDS]
set -u
export XDG_RUNTIME_DIR=/run/user/$(id -u) WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-wayland-1}
what=${1:-glmark2}; secs=${2:-30}
grep -o "renderer:.*" <(eglinfo -B 2>/dev/null) | head -2
case $what in
  glmark2) glmark2-es2-wayland --fullscreen 2>&1 | grep -E "glmark2 Score|GL_RENDERER|GL_VERSION" ;;
  gears)   timeout "$secs" es2gears_wayland -fullscreen 2>&1 | grep -E "frames in" | tail -5 ;;
esac
