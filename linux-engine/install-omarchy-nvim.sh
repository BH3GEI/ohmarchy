#!/bin/bash
# Run inside HarmonyOS's Linux engine (openEuler container) as your user:
#   bash /mnt/linux_share/storage/Users/currentUser/Download/install-omarchy-nvim.sh
# Installs a static ARM64 neovim (openEuler has no package) plus a config, then
# installs the plugins headless. Config source, in order:
#   1. omarchy-nvim.tgz in the shared Download folder: your own Omarchy config,
#      made on an Omarchy machine with  tar -czf omarchy-nvim.tgz -C ~/.config nvim
#   2. the public LazyVim starter (Omarchy's omarchy-nvim setup is built on LazyVim)
# Progress goes to omarchy-nvim.log/.result in the shared Download folder so the
# host can follow it over hdc.
SHARE=/mnt/linux_share/storage/Users/currentUser/Download
[ -d "$SHARE" ] || SHARE=$HOME
LOG=$SHARE/omarchy-nvim.log RES=$SHARE/omarchy-nvim.result
COLORSCHEME=${COLORSCHEME:-tokyonight}            # Omarchy's default theme
THEME_PLUGIN=${THEME_PLUGIN:-folke/tokyonight.nvim}
exec >"$LOG" 2>&1
# github.com is often unreachable from the container (proxy CONNECT aborted);
# fall back to the gh-proxy.com mirror.
dl()  { curl -fL --connect-timeout 20 -m 300 -o "$2" "$1" || curl -fL --connect-timeout 20 -m 300 -o "$2" "https://gh-proxy.com/$1"; }
clone() { git clone --depth 1 "$1" "$2" || git clone --depth 1 "https://gh-proxy.com/$1" "$2"; }

NV=$HOME/nvim-linux-arm64/bin/nvim
if [ ! -x "$NV" ]; then
    dl https://github.com/neovim/neovim/releases/download/stable/nvim-linux-arm64.tar.gz /tmp/nvim.tgz &&
        tar -xzf /tmp/nvim.tgz -C "$HOME"
fi
mkdir -p "$HOME/.local/bin"; ln -sf "$NV" "$HOME/.local/bin/nvim"
"$NV" --version | head -1 || { echo "RESULT=FAIL nvim" > "$RES"; exit 1; }

if [ ! -f "$HOME/.config/nvim/init.lua" ]; then
    mkdir -p "$HOME/.config"
    if [ -f "$SHARE/omarchy-nvim.tgz" ]; then
        tar -xzf "$SHARE/omarchy-nvim.tgz" -C "$HOME/.config"
    else
        clone https://github.com/LazyVim/starter "$HOME/.config/nvim" && rm -rf "$HOME/.config/nvim/.git"
    fi
fi
# Omarchy's theme.lua points into the Omarchy theme switcher's state directory,
# which does not exist here; replace it with a concrete theme.
T=$HOME/.config/nvim/lua/plugins/theme.lua
if [ -L "$T" ] || [ ! -e "$T" ]; then
    rm -f "$T"
    printf 'return {\n  { "%s", priority = 1000 },\n  { "LazyVim/LazyVim", opts = { colorscheme = "%s" } },\n}\n' \
        "$THEME_PLUGIN" "$COLORSCHEME" > "$T"
fi
timeout 600 "$NV" --headless "+Lazy! install" +qa 2>&1 | tail -20
if [ -d "$HOME/.local/share/nvim/lazy/LazyVim" ]; then echo "RESULT=OK" > "$RES"; else echo "RESULT=PARTIAL plugins" > "$RES"; fi
cat "$RES"
