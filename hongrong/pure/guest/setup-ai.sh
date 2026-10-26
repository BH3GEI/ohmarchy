#!/bin/bash
# Point Omarchy's coding agents (Claude Code, Codex, opencode) at one
# OpenAI/Anthropic-compatible relay, with the model pinned. Runs as the desktop
# user inside the guest.
#
# Usage: setup-ai.sh [ENV_FILE] [--install]
#   ENV_FILE  shell file with OHM_AI_KEY, OHM_AI_BASE (no path, used for the
#             Anthropic format) and OHM_AI_BASE_V1 (ending in /v1, OpenAI
#             format). Without it (the public image) the key stays empty and a
#             first-use hint tells the user where to put theirs.
#   --install install the tools now through Omarchy's mise wrappers instead of
#             on first use (needs the network).
# Environment: AI_MODEL (default kimi/kimi-for-coding; the relay's IDs are not
# the vendors' standard names, those return 404), AI_MODEL_FALLBACK (default
# ark/ark-code-latest, offered in opencode).
#
# The key ends up only in ~/.config/environment.d/ai.conf (mode 600), read by
# the systemd user session and sourced from ~/.bashrc; the tool configs
# reference the variables. Never put a real ENV_FILE into a public image.
set -euo pipefail

env_file=
install=0
for a in "$@"; do case "$a" in --install) install=1 ;; *) env_file=$a ;; esac; done
model=${AI_MODEL:-kimi/kimi-for-coding}
fallback=${AI_MODEL_FALLBACK:-ark/ark-code-latest}
key= base= base_v1=
if [ -n "$env_file" ]; then
  # shellcheck disable=SC1090
  . "$env_file"
  key=${OHM_AI_KEY:?no OHM_AI_KEY in $env_file}
  base=${OHM_AI_BASE:?no OHM_AI_BASE in $env_file}
  base_v1=${OHM_AI_BASE_V1:-$base/v1}
fi

umask 077
mkdir -p ~/.config/environment.d ~/.codex ~/.config/opencode ~/.claude
cat > ~/.config/environment.d/ai.conf <<EOF
# AI relay for Claude Code, Codex and opencode (hongrong/pure/guest/setup-ai.sh)
OPENAI_API_KEY=$key
OPENAI_BASE_URL=$base_v1
ANTHROPIC_AUTH_TOKEN=$key
ANTHROPIC_BASE_URL=$base
ANTHROPIC_MODEL=$model
ANTHROPIC_DEFAULT_HAIKU_MODEL=$model
ANTHROPIC_DEFAULT_SONNET_MODEL=$model
ANTHROPIC_DEFAULT_OPUS_MODEL=$model
CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
EOF
chmod 600 ~/.config/environment.d/ai.conf
line='[ -r ~/.config/environment.d/ai.conf ] && { set -a; . ~/.config/environment.d/ai.conf; set +a; }'
grep -qxF "$line" ~/.bashrc 2>/dev/null || echo "$line" >> ~/.bashrc

cat > ~/.codex/config.toml <<EOF
model = "$model"
model_provider = "relay"

[model_providers.relay]
name = "relay"
base_url = "$base_v1"
env_key = "OPENAI_API_KEY"
wire_api = "responses"
EOF

cat > ~/.config/opencode/opencode.json <<EOF
{
  "\$schema": "https://opencode.ai/config.json",
  "model": "relay/$model",
  "provider": {
    "relay": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "relay",
      "options": { "baseURL": "$base_v1", "apiKey": "{env:OPENAI_API_KEY}" },
      "models": { "$model": {}, "$fallback": {} }
    }
  }
}
EOF

# Claude Code: skip the login screen; the relay authenticates the token
[ -f ~/.claude.json ] || echo '{"hasCompletedOnboarding": true}' > ~/.claude.json

if [ -z "$key" ]; then
  # public image: a one-time hint in the first terminal
  hint='[ -s ~/.config/environment.d/ai.conf ] && grep -q "^OPENAI_API_KEY=$" ~/.config/environment.d/ai.conf && echo "AI agents: put your key and base URL into ~/.config/environment.d/ai.conf (see ohmarchy docs/hongrong-whole-os.md, AI agents), then log in again."'
  grep -qxF "$hint" ~/.bashrc || echo "$hint" >> ~/.bashrc
fi

if [ $install = 1 ]; then
  for t in claude codex opencode; do MISE_MINIMUM_RELEASE_AGE=0 mise use -g --quiet "$t"; done
fi
echo AI_SETUP_DONE
