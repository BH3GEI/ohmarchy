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
pacman -S --noconfirm --needed clang cmake ninja meson hyprwayland-scanner glaze hyprland-protocols \
    wayland-protocols xorgproto hwdata libdisplay-info libinput libdrm seatd pixman libxkbcommon pango \
    cairo libxcursor xcb-util-errors xcb-util-wm libliftoff re2 muparser tomlplusplus lua mesa-utils wayvnc
pacman -S --noconfirm libglvnd

# cmake does not know a "HarmonyOS" system; report Linux to the tools.
gcc -O2 -shared -fPIC -o /usr/local/lib/libhongmeng-uname.so "$here/desktop/hongmeng-uname.c" -ldl
grep -q libhongmeng-uname /etc/ld.so.preload 2>/dev/null || echo /usr/local/lib/libhongmeng-uname.so >> /etc/ld.so.preload

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
home=$(getent passwd "$user" | cut -d: -f6)
# Chromium's sandbox needs user namespaces or a setuid helper; neither exists here.
grep -qx -- --no-sandbox "$home/.config/chromium-flags.conf" 2>/dev/null ||
    echo --no-sandbox >> "$home/.config/chromium-flags.conf"
# GitHub is not reachable from the host: mise (Omarchy's tool installs) goes through a proxy.
mkdir -p "$home/.config/mise"
grep -q url_replacements "$home/.config/mise/config.toml" 2>/dev/null || cat >> "$home/.config/mise/config.toml" <<'T'

# GitHub is not reachable from the HarmonyOS host; fetch through a proxy.
[settings.url_replacements]
"https://github.com" = "https://gh-proxy.com/https://github.com"
"https://api.github.com" = "https://gh-proxy.com/https://api.github.com"
T
chown -R "$user:" "$home/.config/chromium-flags.conf" "$home/.config/mise"
install -m 644 -o "$user" -g "$user" "$here/desktop/ohdisplay.lua" "$home/.config/hypr/ohdisplay.lua"
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
rm -rf "$build"
echo "Done. Start it from the host with: omarchy desktop start"
