#!/bin/bash
# Run inside HarmonyOS's Linux engine as your user: installs Omarchy's CLI tools
# (fastfetch, btop, lazygit) as static ARM64 binaries into ~/.local/bin.
SHARE=/mnt/linux_share/storage/Users/currentUser/Download
[ -d "$SHARE" ] || SHARE=$HOME
LOG=$SHARE/omarchy-cli.log RES=$SHARE/omarchy-cli.result
exec >"$LOG" 2>&1
BIN=$HOME/.local/bin; mkdir -p "$BIN"; cd /tmp || exit 1
dl() { curl -fL --connect-timeout 20 -m 300 -o "$2" "$1" || curl -fL --connect-timeout 20 -m 300 -o "$2" "https://gh-proxy.com/$1"; }
GH=https://github.com
dl $GH/fastfetch-cli/fastfetch/releases/latest/download/fastfetch-linux-aarch64.tar.gz ff.tgz &&
    tar -xzf ff.tgz && cp fastfetch-linux-aarch64/usr/bin/fastfetch "$BIN/"
dl $GH/aristocratos/btop/releases/latest/download/btop-aarch64-unknown-linux-musl.tar.gz btop.tgz &&
    tar -xzf btop.tgz && cp btop/bin/btop "$BIN/"
V=$(curl -fsSL https://api.github.com/repos/jesseduffield/lazygit/releases/latest | grep -oE '"tag_name": *"v[^"]+' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
[ -n "$V" ] && dl "$GH/jesseduffield/lazygit/releases/download/v$V/lazygit_${V}_Linux_arm64.tar.gz" lg.tgz &&
    tar -xzf lg.tgz lazygit && cp lazygit "$BIN/"
chmod +x "$BIN"/* 2>/dev/null
for t in fastfetch btop lazygit; do printf '%s: ' $t; "$BIN/$t" --version 2>&1 | head -1; done
echo "RESULT fastfetch=$([ -x "$BIN/fastfetch" ] && echo y || echo n) btop=$([ -x "$BIN/btop" ] && echo y || echo n) lazygit=$([ -x "$BIN/lazygit" ] && echo y || echo n)" > "$RES"
cat "$RES"
