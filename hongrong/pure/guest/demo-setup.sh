#!/bin/bash
# Fill an internal (demo) Omarchy guest with tools, apps and a ready-to-run AI
# agent demo. Never for the public image (its 2 GiB limit; the AI key and the
# proxy come from inject-ai-env.sh and inject-proxy-env.sh, not from here).
# Runs as the desktop user inside the guest, asks for sudo once. Idempotent.
# Packages that the repositories do not have are skipped and listed at the end.
# Usage: demo-setup.sh [mirrors|packages|agents|more-agents|vscodium|desktop|nvim|all]
#   (default all). more-agents (kimi, octoscode) needs no sudo; OHM_BUNDLE_DIR
#   may hold octoscode's and octos' linux arm64 release archives fetched
#   elsewhere (their installers download them from GitHub, slow behind the proxy).
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
alias ai-kimi='cd ~/demo && kimi'
alias ai-octos='cd ~/demo && octoscode'
[[ $- == *i* ]] && echo "输入 ai 开始（Claude Code），或 ai-codex / ai-oc / ai-kimi / ai-octos · Type ai to start"
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

more_agents() {
  log "kimi and octoscode"
  # octoscode, the terminal client of the octos server; octos' installer takes
  # a local archive, octoscode's only a download, so with OHM_BUNDLE_DIR its
  # binary is unpacked where its launcher looks
  local d=${OHM_BUNDLE_DIR:-} oc=octoscode-aarch64-unknown-linux-gnu os=octos-bundle-aarch64-unknown-linux-gnu.tar.gz
  local allow=@octos-org/octoscode,@octos-org/octos
  [ -n "$d" ] && allow=@octos-org/octos
  # kimi: Moonshot's kimi-code (command kimi; its config: setup-ai.sh)
  OCTOS_BUNDLE_URL=${d:+file://$d/$os} npm install -g --prefix ~/.local --no-fund --no-audit \
    --allow-scripts=$allow,@moonshot-ai/kimi-code @octos-org/octoscode @octos-org/octos @moonshot-ai/kimi-code ||
    missing+=(octoscode/kimi-code)
  if [ -n "$d" ]; then
    local real=~/.local/lib/node_modules/@octos-org/octoscode/node_modules/.bin_real
    mkdir -p "$real" && tar xJf "$d/$oc.tar.xz" -C "$real" --strip-components=1 "$oc/octoscode"
  fi
  # disks set up before these two agents have the alias block without them
  grep -q '^alias ai-kimi=' ~/.bashrc || printf '%s\n' "alias ai-kimi='cd ~/demo && kimi'" "alias ai-octos='cd ~/demo && octoscode'" >> ~/.bashrc
  octos_profile
}

# octoscode's first-run wizard (local profile, provider, key): the profile is
# created through octos' own AppUI call, its model route is the relay of
# ai.conf with the key read from OPENAI_API_KEY at run time
octos_profile() {
  command -v octos >/dev/null || return
  set -a; . ~/.config/environment.d/ai.conf 2>/dev/null; set +a
  local id=$USER
  [ -f ~/.octos/profiles/$id.json ] ||
    (cd ~ && { printf '{"jsonrpc":"2.0","id":"1","method":"profile/local/create","params":{"name":"%s","username":"%s","email":"%s@localhost"}}\n' $id $id $id; sleep 10; } |
      timeout 60 octos serve --stdio --solo >/dev/null 2>&1)
  [ -f ~/.octos/profiles/$id.json ] || { missing+=(octos-profile); return; }
  [ -n "${OPENAI_BASE_URL:-}" ] || return
  python3 - ~/.octos/profiles/$id.json <<'PYEOF'
import json, os, sys
p = sys.argv[1]
d = json.load(open(p))
# the relay's kimi only takes the default temperature
d["config"]["llm"] = {"primary": {"family_id": "openai", "model_id": os.environ["ANTHROPIC_MODEL"],
    "route": {"route_id": "custom", "label": "relay", "base_url": os.environ["OPENAI_BASE_URL"],
              "api_key_env": "OPENAI_API_KEY", "api_type": "openai"},
    "model_hints": {"fixed_temperature": True}}}
json.dump(d, open(p, "w"), indent=2)
PYEOF
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

# mainland mirrors as the system default, for every user and every shell:
# pacman (TUNA, USTC, then Omarchy's own), npm (npmmirror), pip and uv (TUNA),
# rustup and cargo (rsproxy), go (goproxy.cn), mise's Node.js (npmmirror),
# Docker (DaoCloud and 1ms registry mirrors). Variables go to
# /etc/environment.d (the systemd user session, so the desktop and its
# terminals) and /etc/profile.d (login shells), files to /etc and /etc/skel.
mirrors_system() {
  log "mainland mirrors (system default)"
  local L=/usr/local/lib/ohmarchy
  # pacman: mainland mirrors and the kernel held back (鸿融's patched
  # linux-aarch64; the stock one from a system update may not boot). Omarchy's
  # updates put its stock pacman.conf and mirrorlist back, so a pre-refresh-pacman
  # hook (as route D's) runs this again before each upgrade
  sudo tee $L/pin-pacman.sh >/dev/null <<'EOF'
#!/bin/bash
# mainland mirrors first and the patched kernel held back (ohmarchy demo-setup.sh)
cat > /etc/pacman.d/mirrorlist <<'ML'
# Arch Linux ARM: mainland mirrors first, Omarchy's ARM mirror as fallback (ohmarchy)
Server = https://mirrors.tuna.tsinghua.edu.cn/archlinuxarm/$arch/$repo
Server = https://mirrors.ustc.edu.cn/archlinuxarm/$arch/$repo
Server = https://arm-stable-mirror.omarchy.org/$arch/$repo
ML
grep -q '^IgnorePkg *=.*linux-aarch64' /etc/pacman.conf ||
  sed -i '/^\[options\]/a IgnorePkg = linux-aarch64 linux-aarch64-headers' /etc/pacman.conf
EOF
  sudo chmod 755 $L/pin-pacman.sh; sudo $L/pin-pacman.sh
  local hook=~/.config/omarchy/hooks/pre-refresh-pacman.d/10-ohmarchy-pin
  mkdir -p "${hook%/*}"
  printf '#!/bin/bash\n# ohmarchy: mainland mirrors, patched kernel held back\nsudo %s/pin-pacman.sh\n' $L > "$hook"
  chmod 755 "$hook"
  local env='RUSTUP_DIST_SERVER=https://rsproxy.cn
RUSTUP_UPDATE_ROOT=https://rsproxy.cn/rustup
CARGO_REGISTRIES_CRATES_IO_PROTOCOL=sparse
GOPROXY=https://goproxy.cn,direct
NPM_CONFIG_REGISTRY=https://registry.npmmirror.com
PIP_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple
UV_DEFAULT_INDEX=https://pypi.tuna.tsinghua.edu.cn/simple
MISE_NODE_MIRROR_URL=https://npmmirror.com/mirrors/node/'
  sudo mkdir -p /etc/environment.d /etc/docker /etc/skel/.cargo /etc/uv
  printf '# mainland mirrors (ohmarchy demo-setup.sh)\n%s\n' "$env" | sudo tee /etc/environment.d/50-ohmarchy-mirrors.conf >/dev/null
  printf '# mainland mirrors (ohmarchy demo-setup.sh)\n%s\n' "$(sed 's/^/export /' <<<"$env")" | sudo tee /etc/profile.d/ohmarchy-mirrors.sh >/dev/null
  # interactive non-login shells (the terminals) get it from bash.bashrc too
  sudo grep -q ohmarchy-mirrors /etc/bash.bashrc ||
    echo '[ -r /etc/profile.d/ohmarchy-mirrors.sh ] && . /etc/profile.d/ohmarchy-mirrors.sh' | sudo tee -a /etc/bash.bashrc >/dev/null
  echo 'registry=https://registry.npmmirror.com' | sudo tee /usr/etc/npmrc >/dev/null 2>&1 ||
    { sudo mkdir -p /usr/etc && echo 'registry=https://registry.npmmirror.com' | sudo tee /usr/etc/npmrc >/dev/null; }
  printf '[global]\nindex-url = https://pypi.tuna.tsinghua.edu.cn/simple\n' | sudo tee /etc/pip.conf >/dev/null
  printf '[[index]]\nurl = "https://pypi.tuna.tsinghua.edu.cn/simple"\ndefault = true\n' | sudo tee /etc/uv/uv.toml >/dev/null
  # cargo reads no system-wide file: new users get it from /etc/skel, this one directly
  local cargo='[source.crates-io]
replace-with = "rsproxy-sparse"

[source.rsproxy-sparse]
registry = "sparse+https://rsproxy.cn/index/"

[registries.rsproxy]
index = "https://rsproxy.cn/crates.io-index"

[net]
git-fetch-with-cli = true'
  echo "$cargo" | sudo tee /etc/skel/.cargo/config.toml >/dev/null
  mkdir -p ~/.cargo; [ -f ~/.cargo/config.toml ] && grep -q rsproxy ~/.cargo/config.toml || echo "$cargo" >> ~/.cargo/config.toml
  # Docker: merged into an existing daemon.json
  sudo python3 - <<'PYEOF'
import json, os
p = "/etc/docker/daemon.json"
d = json.load(open(p)) if os.path.exists(p) and os.path.getsize(p) else {}
d["registry-mirrors"] = ["https://docker.m.daocloud.io", "https://docker.1ms.run"]
json.dump(d, open(p, "w"), indent=2)
PYEOF
  set -a; . /etc/environment.d/50-ohmarchy-mirrors.conf; set +a
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

[ "$step" = more-agents ] || sudo -v || exit 1
mirrors
case $step in
  mirrors) mirrors_system ;; packages) packages ;; agents) agents ;; more-agents) more_agents ;; vscodium) vscodium ;; desktop) desktop ;; nvim) nvim_setup ;;
  all) mirrors_system; packages; agents; more_agents; vscodium; desktop; nvim_setup ;;
  *) echo "usage: demo-setup.sh [mirrors|packages|agents|more-agents|vscodium|desktop|nvim|all]"; exit 1 ;;
esac
[ ${#missing[@]} -eq 0 ] || echo "not installed: ${missing[*]}"
echo DEMO_SETUP_DONE
