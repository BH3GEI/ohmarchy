#!/bin/bash
# Fill an internal (demo) Omarchy guest with tools, apps and a ready-to-run AI
# agent demo. Never for the public image (its 2 GiB limit; the AI key and the
# proxy come from inject-ai-env.sh and inject-proxy-env.sh, not from here).
# Runs as the desktop user inside the guest, asks for sudo once. Idempotent.
# Packages that the repositories do not have are skipped and listed at the end.
# Usage: demo-setup.sh [packages|agents|vscodium|desktop|nvim|all] (default all)
set -uo pipefail
step=${1:-all}
log() { printf '\n== %s\n' "$*"; }
missing=()

PKGS=(
  # development
  nodejs npm rustup go clang cmake github-cli uv lazydocker docker-compose
  # apps
  firefox firefox-i18n-zh-cn obsidian libreoffice-fresh libreoffice-fresh-zh-cn
  xournalpp localsend gimp inkscape obs-studio zathura zathura-pdf-mupdf
  # Chinese input and fonts
  fcitx5-im fcitx5-chinese-addons noto-fonts-cjk
  # terminal show
  cava cmatrix tty-clock
  # proxy (configured by ohmarchy-proxy-setup.service)
  sing-box
)

packages() {
  log packages
  sudo pacman --sync --refresh --noconfirm >/dev/null
  local have=()
  for p in "${PKGS[@]}"; do
    if pacman --sync --print --print-format %n "$p" >/dev/null 2>&1; then have+=("$p"); else missing+=("$p"); fi
  done
  sudo pacman --sync --noconfirm --needed "${have[@]}"
  # a toolchain whose download was cut off reports "error reading rustc version"
  rustc --version >/dev/null 2>&1 || { rustup toolchain uninstall stable >/dev/null 2>&1; rustup default stable; }
  # pinyin next to the US layout, unless a profile already has it
  local prof=~/.config/fcitx5/profile
  if ! grep -q '^Name=pinyin' "$prof" 2>/dev/null; then
    mkdir -p ~/.config/fcitx5
    cat > "$prof" <<'EOF'
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
EOF
  fi
}

agents() {
  log "AI agents"
  # From npm (npmmirror, direct) with the system Node.js, not through Omarchy's
  # launchers: those run `mise use` at every start, which looks for a newer
  # version online and hung for minutes behind a slow network, and mise's
  # downloads (GitHub through the proxy) were cut off and left empty installs.
  # npm 11+ skips install scripts unless allowed; claude and opencode fetch
  # their native binary in one. Upgrade: run this step again.
  pkill -f '^mise (use|x) ' 2>/dev/null
  for t in claude codex opencode; do
    [ -f ~/.local/bin/$t ] && [ ! -L ~/.local/bin/$t ] && mv -f ~/.local/bin/$t ~/.local/bin/$t.mise-launcher
  done
  npm install -g --prefix ~/.local --no-fund --no-audit \
    --allow-scripts=@anthropic-ai/claude-code,opencode-ai \
    @anthropic-ai/claude-code @openai/codex opencode-ai
  # a `node = "latest"` left by a failed mise install makes every mise shim hang
  sed -i '/^node *= *"latest"/d' ~/.config/mise/config.toml 2>/dev/null
  mkdir -p ~/demo
  if [ ! -f ~/demo/app.py ]; then
    cat > ~/demo/app.py <<'EOF'
"""A tiny to-do list on the command line (the AI agent demo project)."""
import json
import sys
from pathlib import Path

DB = Path(__file__).with_name("todo.json")


def load():
    return json.loads(DB.read_text()) if DB.exists() else []


def save(items):
    DB.write_text(json.dumps(items, ensure_ascii=False, indent=2))


def main(argv):
    items = load()
    if not argv or argv[0] == "list":
        for i, it in enumerate(items, 1):
            print(f"{i}. [{'x' if it['done'] else ' '}] {it['text']}")
    elif argv[0] == "add":
        items.append({"text": " ".join(argv[1:]), "done": False})
        save(items)
    elif argv[0] == "done":
        items[int(argv[1])].update(done=True)  # bug: the list numbers from 1
        save(items)
    else:
        print("usage: app.py [list | add TEXT | done N]")


if __name__ == "__main__":
    main(sys.argv[1:])
EOF
    cat > ~/demo/CLAUDE.md <<'EOF'
# Demo project

`app.py` is a tiny command-line to-do list (`python app.py add 买牛奶`,
`python app.py list`, `python app.py done 1`).

Demo tasks for the agent, one at a time:
1. `done 1` marks the wrong item. Find the bug and fix it.
2. Add `python app.py remove N`.
3. Write tests with pytest and run them.
4. Turn it into a small web page (Flask or plain http.server) and open it in Firefox.

Answer in Chinese.
EOF
    cp ~/demo/CLAUDE.md ~/demo/AGENTS.md
    (cd ~/demo && git init -q && git add -A && git -c user.name=omarchy -c user.email=omarchy@localhost commit -qm "demo project")
  fi
  local mark='# ohmarchy demo: AI agents'
  grep -qxF "$mark" ~/.bashrc || cat >> ~/.bashrc <<'EOF'
# ohmarchy demo: AI agents
alias ai='cd ~/demo && claude'
alias ai-codex='cd ~/demo && codex'
alias ai-oc='cd ~/demo && opencode'
[[ $- == *i* ]] && echo "输入 ai 开始（Claude Code），或 ai-codex / ai-oc · Type ai to start"
EOF
  mkdir -p ~/.local/share/applications
  cat > ~/.local/share/applications/ai-terminal.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=AI Terminal
Name[zh_CN]=AI 终端
Comment=Claude Code in the demo project
Exec=sh -c 'cd ~/demo && exec foot bash -ic "claude; exec bash"'
Icon=utilities-terminal
Terminal=false
Categories=Development;
EOF
}

vscodium() {
  log VSCodium
  command -v codium >/dev/null && return
  # TUNA mirrors the GitHub releases and is reached directly (GitHub through
  # the proxy ran at 40 KB/s)
  local m=https://mirrors.tuna.tsinghua.edu.cn/github-release/VSCodium/vscodium/LatestRelease f
  f=$(curl -fsSL "$m/" | grep -o 'VSCodium-linux-arm64-[0-9.]*\.tar\.gz' | head -1)
  [ -n "$f" ] || { echo "VSCodium: no release found"; missing+=(vscodium); return; }
  curl -fL "$m/$f" -o /tmp/vscodium.tgz || { missing+=(vscodium); return; }
  sudo mkdir -p /opt/vscodium && sudo tar xzf /tmp/vscodium.tgz -C /opt/vscodium && rm -f /tmp/vscodium.tgz
  sudo ln -sf /opt/vscodium/bin/codium /usr/local/bin/codium
  sudo tee /usr/share/applications/codium.desktop >/dev/null <<'EOF'
[Desktop Entry]
Type=Application
Name=VSCodium
Comment=Code editor
Exec=/opt/vscodium/bin/codium --ozone-platform=wayland %F
Icon=/opt/vscodium/resources/app/resources/linux/code.png
Categories=Development;TextEditor;
EOF
}

desktop() {
  log desktop
  # one cursor: the host draws its own; hide the guest's (route C and the
  # native app: docs/native-desktop.md)
  local h=~/.config/hypr/hyprland.lua line='hl.config({ cursor = { invisible = true } })'
  [ -f "$h" ] && { grep -qxF "$line" "$h" || printf '\n-- one cursor: the host draws its own (ohmarchy)\n%s\n' "$line" >> "$h"; }
  # a demo machine: no idle lock or screensaver (they came every two minutes)
  command -v omarchy-toggle-idle >/dev/null && omarchy-toggle-idle stay-awake
}

nvim_setup() {
  log neovim
  nvim --headless "+Lazy! sync" +qa >/dev/null 2>&1
  nvim --headless "+TSInstallSync lua python javascript typescript rust go bash markdown json yaml toml" +qa >/dev/null 2>&1
  nvim --headless "+MasonInstall lua-language-server pyright typescript-language-server rust-analyzer gopls" "+sleep 240" +qa >/dev/null 2>&1
  ls ~/.local/share/nvim/mason/bin 2>/dev/null | tr '\n' ' '; echo
}

# mainland mirrors for the developer tools (the same as route D's
# native/desktop/environment.d/50-mirrors.conf), plus Node.js for mise
mirrors() {
  mkdir -p ~/.config/environment.d
  cat > ~/.config/environment.d/50-mirrors.conf <<'EOF'
RUSTUP_DIST_SERVER=https://mirrors.tuna.tsinghua.edu.cn/rustup
RUSTUP_UPDATE_ROOT=https://mirrors.tuna.tsinghua.edu.cn/rustup/rustup
GOPROXY=https://goproxy.cn,direct
NPM_CONFIG_REGISTRY=https://registry.npmmirror.com
PIP_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple
UV_DEFAULT_INDEX=https://pypi.tuna.tsinghua.edu.cn/simple
MISE_NODE_MIRROR_URL=https://npmmirror.com/mirrors/node/
EOF
  local line='[ -r ~/.config/environment.d/50-mirrors.conf ] && { set -a; . ~/.config/environment.d/50-mirrors.conf; set +a; }'
  grep -qxF "$line" ~/.bashrc || echo "$line" >> ~/.bashrc
  set -a; . ~/.config/environment.d/50-mirrors.conf; set +a
}

sudo -v || exit 1
mirrors
case $step in
  packages) packages ;; agents) agents ;; vscodium) vscodium ;; desktop) desktop ;; nvim) nvim_setup ;;
  all) packages; agents; vscodium; desktop; nvim_setup ;;
  *) echo "usage: demo-setup.sh [packages|agents|vscodium|desktop|nvim|all]"; exit 1 ;;
esac
[ ${#missing[@]} -eq 0 ] || echo "not installed: ${missing[*]}"
echo DEMO_SETUP_DONE
