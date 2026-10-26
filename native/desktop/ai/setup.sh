#!/system/bin/sh
# Coding agents for route D's desktop user, through Yao's API relay. Root on the
# HarmonyOS host:  sh native/desktop/ai/setup.sh [user]   (default builder)
# The relay's address and key come from /data/local/secrets/ai.env (root, 600:
# OHM_AI_KEY, OHM_AI_BASE); they go only into the user's
# ~/.config/environment.d/60-ai.conf (600), which the desktop session reads
# (ohdisplay.lua) and login shells too (/etc/profile.d/ohmarchy-environment.sh).
# Nothing here prints them. The agents' own configs (in this directory) name the
# variables, not the values. The relay speaks the OpenAI API (/v1/chat/completions,
# /v1/responses) and Anthropic's (/v1/messages), with its own model IDs only
# (standard names give 404): every agent is pinned to kimi/kimi-for-coding,
# ark/ark-code-latest as the alternative (supervisor, 2026-10-26).
# The agents themselves are Omarchy's: its ~/.local/bin launchers install them
# through mise on first use (opencode, codex, claude).
set -e
here=$(cd "$(dirname "$0")" && pwd)
B=${ARCH_BASE:-/data/local/archtest}
user=${1:-builder}
S=/data/local/secrets/ai.env
[ -r $S ] || { echo "no $S" >&2; exit 1; }
P=$(cat $B/session.pid); R=/proc/$P/root
home=$(grep "^$user:" $R/etc/passwd | cut -d: -f6); uid=$(grep "^$user:" $R/etc/passwd | cut -d: -f3)
key=$(sed -n 's/^OHM_AI_KEY=//p' $S | tr -d '"'"'"); base=$(sed -n 's/^OHM_AI_BASE=//p' $S | tr -d '"'"'")
[ -n "$key" ] && [ -n "$base" ] || { echo "OHM_AI_KEY or OHM_AI_BASE missing in $S" >&2; exit 1; }
d=$R$home/.config/environment.d; mkdir -p $d
m=kimi/kimi-for-coding
(umask 077; printf 'OPENAI_API_KEY=%s\nOPENAI_BASE_URL=%s/v1\nANTHROPIC_BASE_URL=%s\nANTHROPIC_AUTH_TOKEN=%s\nANTHROPIC_MODEL=%s\nANTHROPIC_DEFAULT_OPUS_MODEL=%s\nANTHROPIC_DEFAULT_SONNET_MODEL=%s\nANTHROPIC_DEFAULT_HAIKU_MODEL=%s\nANTHROPIC_SMALL_FAST_MODEL=%s\n' \
    "$key" "$base" "$base" "$key" $m $m $m $m $m > $d/60-ai.conf)
chown $uid:$uid $d $d/60-ai.conf; chmod 600 $d/60-ai.conf
unset key
echo "60-ai.conf written ($(wc -c < $d/60-ai.conf) bytes, mode 600)"
# configs without secrets
mkdir -p $R$home/.codex $R$home/.config/opencode
cp $here/codex-config.toml $R$home/.codex/config.toml
cp $here/opencode.json $R$home/.config/opencode/opencode.json
chown -R $uid:$uid $R$home/.codex $R$home/.config/opencode
# install them now (mise, through the mirrors in 50-mirrors.conf) and check each
# with one request through the relay
sh $B/bin/omarchy -c 'export PATH=$HOME/.local/bin:$PATH; cd /tmp
for a in opencode codex claude; do echo "$a: $($a --version 2>&1 | tail -1)"; done
q="Reply with exactly the word PONG and nothing else"
echo "opencode: $(timeout 240 opencode run "$q" 2>&1 | tail -1)"
echo "codex: $(timeout 240 codex exec --skip-git-repo-check "$q" 2>&1 | tail -1)"
echo "claude: $(timeout 240 claude -p "$q" 2>&1 | tail -1)"' 2>&1 | grep -v -i -e sk- -e "$base/"
