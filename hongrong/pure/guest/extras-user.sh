#!/bin/bash
# the desktop user's part of extras-firstboot.sh: ai.conf again (kimi-code, no auto-updates), kimi-code, octoscode and its octos profile
E=/usr/local/lib/ohmarchy/extras
cd ~ || exit 1
if [ -s ~/.config/environment.d/ai.conf ]; then
  # setup-ai.sh again (this disk's newer copy: kimi-code's model, no auto-updates)
  set -a; . ~/.config/environment.d/ai.conf; set +a
  e=$(umask 077; mktemp)
  printf 'OHM_AI_KEY=%s\nOHM_AI_BASE=%s\nOHM_AI_BASE_V1=%s\n' "$OPENAI_API_KEY" "$ANTHROPIC_BASE_URL" "$OPENAI_BASE_URL" > "$e"
  AI_MODEL=$ANTHROPIC_MODEL bash /usr/local/lib/ohmarchy/setup-ai.sh "$e" | tail -1; : > "$e"; rm -f "$e"
  echo "KIMI_MODEL_ lines: $(grep -c '^KIMI_MODEL_' ~/.config/environment.d/ai.conf)"
fi
OHM_BUNDLE_DIR=$E bash /usr/local/lib/ohmarchy/demo-setup.sh more-agents 2>&1 | tail -6
for t in claude codex opencode octoscode octos kimi; do printf '%s: %s\n' $t "$(command -v $t || echo MISSING)"; done
ls ~/.local/lib/node_modules/@octos-org/octoscode/node_modules/.bin_real/ 2>&1
python3 -c 'import json,os; d=json.load(open(os.path.expanduser("~/.octos/profiles/omarchy.json"))); print("octos profile model:", d["config"].get("llm",{}).get("primary",{}).get("model_id"))' 2>&1
