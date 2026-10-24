#!/bin/bash
# Run in the session as root: sh arch.sh run 40-install-desktop.sh USER
# Omarchy's Hyprland desktop rendered natively for the HarmonyOS display app
# (native/app). Builds aquamarine and Hyprland with the patches in desktop/patches
# into /opt/ohmarchy, next to the packaged ones:
#   aquamarine: a dma-heap allocator for the headless backend (no DRM device on
#     HongMeng) and a frame export socket the app reads the output buffers from;
#   Hyprland: EGL on Mesa's surfaceless platform (llvmpipe, or virpipe through a
#     vtest server on the host GPU), read-back into the buffers when the driver
#     cannot import dmabufs, and no dmabuf advertisement without linux-dmabuf.
# Needs desktop/src from desktop/fetch-sources.sh.
set -euo pipefail

user=${1:?user}
here=$(cd "$(dirname "$0")" && pwd)
src=$here/desktop/src
prefix=/opt/ohmarchy
[ -d "$src/aquamarine" ] && [ -d "$src/Hyprland" ] || { echo "run desktop/fetch-sources.sh first" >&2; exit 1; }

# The ALARM root ships libglvnd without its GL headers; reinstalling restores them.
pacman -S --noconfirm --needed fcitx5 fcitx5-chinese-addons clang cmake ninja meson hyprwayland-scanner glaze hyprland-protocols \
    wayland-protocols xorgproto hwdata libdisplay-info libinput libdrm seatd pixman libxkbcommon pango \
    cairo libxcursor xcb-util-errors xcb-util-wm libliftoff re2 muparser tomlplusplus lua mesa-utils wayvnc
pacman -S --noconfirm libglvnd
# Missing from Omarchy's set on aarch64, needed by preinstalled entries: qv4l2
# (libQt6Core5Compat) and Disk Usage (dua).
pacman -S --noconfirm --needed qt6-5compat dua-cli
# Default browser: Firefox. Chromium cannot sandbox itself here (no user
# namespaces; its setuid sandbox's zygote fails a check) and runs with
# --no-sandbox; Firefox's content processes get their seccomp-bpf sandbox.
# Web apps (omarchy-launch-webapp) still use Chromium.
pacman -S --noconfirm --needed firefox

# cmake does not know a "HarmonyOS" system; report Linux to the tools.
gcc -O2 -shared -fPIC -o /usr/local/lib/libhongmeng-uname.so "$here/desktop/hongmeng-uname.c" -ldl
grep -q libhongmeng-uname /etc/ld.so.preload 2>/dev/null || echo /usr/local/lib/libhongmeng-uname.so >> /etc/ld.so.preload
# statx(fd, "", AT_EMPTY_PATH) fails with EFAULT here; glycin (GTK's image loading) needs it.
# Global, because glycin starts its loaders with an empty environment.
gcc -O2 -shared -fPIC -o /usr/local/lib/libhongmeng-statx.so "$here/desktop/hongmeng-statx.c"
grep -q libhongmeng-statx /etc/ld.so.preload || echo /usr/local/lib/libhongmeng-statx.so >> /etc/ld.so.preload
# A msgrcv already blocked is never woken by a later msgsnd (fakeroot, so makepkg,
# hangs); poll instead (desktop/hongmeng-msgrcv.c).
gcc -O2 -shared -fPIC -o /usr/local/lib/libhongmeng-msgrcv.so "$here/desktop/hongmeng-msgrcv.c" -ldl
grep -q libhongmeng-msgrcv /etc/ld.so.preload || echo /usr/local/lib/libhongmeng-msgrcv.so >> /etc/ld.so.preload

build=/var/tmp/ohmarchy-build
rm -rf "$build" && mkdir -p "$build" "$prefix"
cp -a "$src/aquamarine" "$src/Hyprland" "$build/"
(cd "$build/aquamarine" && patch -p1 < "$here/desktop/patches/aquamarine-0.15.1-hongmeng.patch")
(cd "$build/Hyprland" && patch -p1 < "$here/desktop/patches/hyprland-0.56.2-hongmeng.patch")
chown -R "$user:" "$build" "$prefix"

# g++ 16.1 crashes (ICE) on these sources under HongMeng; clang builds them.
# FindOpenGL misses libGLESv2 with clang here, so name the libraries.
su "$user" -s /bin/bash -c "
set -e
export CC=clang CXX=clang++ PKG_CONFIG_PATH=$prefix/lib/pkgconfig:$prefix/share/pkgconfig CMAKE_PREFIX_PATH=$prefix
gl='-DOPENGL_gles3_LIBRARY=/usr/lib/libGLESv2.so -DOPENGL_egl_LIBRARY=/usr/lib/libEGL.so -DOPENGL_opengl_LIBRARY=/usr/lib/libOpenGL.so'
cd $build/aquamarine
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=$prefix -DCMAKE_INSTALL_LIBDIR=lib \$gl
ninja -C build install
cd $build/Hyprland
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=$prefix -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_INSTALL_RPATH=$prefix/lib -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON -DNO_TESTS=ON -DBUILD_TESTING=OFF \$gl
ninja -C build install
"

install -m 755 "$here/desktop/ohmarchy-desktop" "$here/desktop/systemd-cat" "$prefix/bin/"
# Omarchy launches apps through systemd --user (uwsm-app, systemd-run --user), and its
# update check needs fakeroot, which fails on HongMeng (SysV IPC); /usr/local/bin
# precedes /usr/bin on the session's PATH.
install -m 755 "$here/desktop/shims/uwsm-app" "$here/desktop/shims/systemd-run" "$here/desktop/shims/checkupdates" /usr/local/bin/
# Replacements for Omarchy commands: ahead of Omarchy's bin in the apps' PATH (ohdisplay.lua)
install -D -m 755 "$here/desktop/shims/omarchy-launch-webapp" /opt/ohmarchy/overrides/omarchy-launch-webapp
home=$(getent passwd "$user" | cut -d: -f6)
# Chromium's sandbox needs user namespaces or a setuid helper; neither exists here.
grep -qx -- --no-sandbox "$home/.config/chromium-flags.conf" 2>/dev/null ||
    echo --no-sandbox >> "$home/.config/chromium-flags.conf"
# Electron apps need --no-sandbox too; mpv's GPU probe asserts in x11 unless told Wayland.
[ -x /opt/obsidian/obsidian ] && printf '#!/bin/sh\nexec /opt/obsidian/obsidian --no-sandbox "$@"\n' > /usr/local/bin/obsidian && chmod 755 /usr/local/bin/obsidian
mkdir -p "$home/.config/mpv"
grep -q '^gpu-context' "$home/.config/mpv/mpv.conf" 2>/dev/null || echo gpu-context=wayland >> "$home/.config/mpv/mpv.conf"
chown -R "$user:" "$home/.config/mpv"
# GitHub is not reachable from the host: mise (Omarchy's tool installs) goes through a proxy.
mkdir -p "$home/.config/mise"
grep -q url_replacements "$home/.config/mise/config.toml" 2>/dev/null || cat >> "$home/.config/mise/config.toml" <<'T'

# GitHub is not reachable from the HarmonyOS host; fetch through a proxy.
[settings.url_replacements]
"https://github.com" = "https://gh-proxy.com/https://github.com"
"https://api.github.com" = "https://gh-proxy.com/https://api.github.com"
T
# libdbus aborts without a machine id (Qt's fcitx plugin took the Omarchy shell down);
# systemd would have written one.
[ -s /etc/machine-id ] || dbus-uuidgen > /etc/machine-id
mkdir -p /var/lib/dbus && ln -sf /etc/machine-id /var/lib/dbus/machine-id

# Input methods: fcitx5 with pinyin next to the US layout (Ctrl+Space switches), started
# by ohdisplay.lua; ohime is the alternative that takes text from the HarmonyOS IME
# through the display app (OHMARCHY_IME=harmony).
xml=$build/Hyprland/protocols/input-method-unstable-v2.xml
wayland-scanner client-header "$xml" "$build/input-method-unstable-v2-client-protocol.h"
wayland-scanner private-code "$xml" "$build/input-method-unstable-v2-protocol.c"
gcc -O2 -o "$prefix/bin/ohime" "$here/desktop/ohime.c" "$build/input-method-unstable-v2-protocol.c" -I"$build" -lwayland-client
# GPU clients: ohmarchy-gpu APP (virpipe, frames as GPU copies; see ohzc-memcpy.c)
mkdir -p "$prefix/lib"
clang -O2 -shared -fPIC -o "$prefix/lib/libohzc.so" "$here/desktop/ohzc-memcpy.c" -ldl
install -m 755 "$here/desktop/ohmarchy-gpu" "$prefix/bin/"
runuser -u "$user" -- xdg-settings set default-web-browser firefox.desktop || true
# Sound to the display app over an abstract socket, to its uid only
cc -O2 -o "$prefix/bin/ohmarchy-audio-relay" "$here/desktop/ohmarchy-audio-relay.c"
# System D-Bus, started and stopped with the desktop (ohmarchy-sysbus): only these
# services can be bus-activated
install -m 755 "$here/desktop/ohmarchy-sysbus" "$prefix/bin/"
install -D -m 644 "$here/desktop/dbus-system.conf" "$prefix/share/dbus-1/system.conf"
mkdir -p "$prefix/share/dbus-1/system-services"
for s in UDisks2 PolicyKit1 UPower; do
    ln -sf "/usr/share/dbus-1/system-services/org.freedesktop.$s.service" "$prefix/share/dbus-1/system-services/"
done
if ! grep -q '^Name=pinyin' "$home/.config/fcitx5/profile" 2>/dev/null; then
    mkdir -p "$home/.config/fcitx5"
    cat > "$home/.config/fcitx5/profile" <<'T'
[Groups/0]
Name=Default
Default Layout=us
DefaultIM=pinyin

[Groups/0/Items/0]
Name=keyboard-us
Layout=

[Groups/0/Items/1]
Name=pinyin
Layout=

[GroupOrder]
0=Default
T
    chown -R "$user:" "$home/.config/fcitx5"
fi

# HarmonyOS locks the machine; Omarchy's idle lock would need a user password the
# chroot user does not have, and its screensaver only burns CPU here.
su "$user" -c "python3 - ~/.config/omarchy/shell.json" <<'P'
import json, os, sys
p = os.path.expanduser(sys.argv[1]) if len(sys.argv) > 1 else os.path.expanduser("~/.config/omarchy/shell.json")
d = json.load(open(p)) if os.path.exists(p) else {}
d.setdefault("idle", {}).update({"lock": 0, "screensaver": 0})
os.makedirs(os.path.dirname(p), exist_ok=True)
json.dump(d, open(p, "w"), indent=2)
P
chown -R "$user:" "$home/.config/chromium-flags.conf" "$home/.config/mise"
install -m 644 -o "$user" -g "$user" "$here/desktop/ohdisplay.lua" "$home/.config/hypr/ohdisplay.lua"
# Sound out to the display app (PipeWire, started by ohmarchy-desktop)
install -d -o "$user" -g "$user" "$home/.config/pipewire" "$home/.config/pipewire/pipewire.conf.d"
install -m 644 -o "$user" -g "$user" "$here/desktop/ohmarchy-audio.conf" "$home/.config/pipewire/pipewire.conf.d/"
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
rm -rf "$build"

# Last: no passwordless root for the desktop user. Without user namespaces, root in
# the session is root on the HarmonyOS host. Omarchy's own narrow NOPASSWD rules
# (DNS, timezone, browser theme policy) come later in sudoers.d and still apply.
# The password comes from ARCH_PASSWORD (never stored here); without it the user
# has none and sudo is unavailable until `passwd` is run as root.
# Roll back: echo '%wheel ALL=(ALL:ALL) NOPASSWD: ALL' > /etc/sudoers.d/10-wheel
echo '%wheel ALL=(ALL:ALL) ALL' > /tmp/10-wheel
visudo -cf /tmp/10-wheel && install -m 440 /tmp/10-wheel /etc/sudoers.d/10-wheel
rm -f /tmp/10-wheel
[ -n "${ARCH_PASSWORD:-}" ] && printf '%s:%s\n' "$user" "$ARCH_PASSWORD" | chpasswd
echo "Done. Start it from the host with: omarchy desktop start"
