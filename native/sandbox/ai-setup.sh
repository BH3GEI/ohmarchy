#!/system/bin/sh
# Coding agents for the sandbox's desktop user, through the API relay, with the
# configuration every route uses (hongrong/pure/guest/setup-ai.sh); the sandbox's
# counterpart of native/desktop/ai/setup.sh. Root on the HarmonyOS host, the sandbox
# running:  sh native/sandbox/ai-setup.sh [user]   (default builder)
# Installs the agents, then leaves no secret in the image (README, Secrets): the three
# files that carry the relay's address or key become links to /run/ohm-secrets, which
# ohm-sandbox fills from /data/local/secrets at each start (here: ohm-sandbox secrets).
# Nothing here prints them. Then each agent answers one prompt.
set -e
here=$(cd "$(dirname "$0")" && pwd)
S=${OHM_SANDBOX:-/data/local/ohm-sandbox}
O="sh $S/bin/ohm-sandbox"
user=${1:-builder}
E=/data/local/secrets/ai.env
[ -r $E ] || { echo "no $E" >&2; exit 1; }
$O status | grep -q running || { echo "the sandbox is not running" >&2; exit 1; }
R=/proc/$(cat $S/sandbox.pid)/root
uid=$(grep "^$user:" $R/etc/passwd | cut -d: -f3)
# the env file and the script, readable only by that user, for the run
t=/tmp/ohm-ai.$$
mkdir -m 700 $R$t && chown $uid:$uid $R$t
cp $E $R$t/ai.env && cp $S/lib/setup-ai.sh $R$t/setup-ai.sh
chown $uid:$uid $R$t/ai.env $R$t/setup-ai.sh && chmod 600 $R$t/ai.env
$O run /usr/bin/su $user -c "bash $t/setup-ai.sh $t/ai.env --install | tail -1" || true
rm -rf $R$t
# the secrets out of the home: links to the tmpfs instead
$O run /usr/bin/su $user -c 'cd ~ && mkdir -p .config/environment.d .codex .config/opencode &&
ln -sfn /run/ohm-secrets/ai.conf .config/environment.d/ai.conf &&
ln -sfn /run/ohm-secrets/codex-config.toml .codex/config.toml &&
ln -sfn /run/ohm-secrets/opencode.json .config/opencode/opencode.json'
$O secrets > /dev/null
# Octos's coding agent (octoscode) and Kimi Code (kimi), npm, on the same relay (2a's recipe,
# 2026-10-30). Their installers fetch from GitHub without the proxy: put
# octos-bundle-aarch64-unknown-linux-gnu.tar.gz (the npm package's version) and
# octoscode-aarch64-unknown-linux-gnu.tar.xz in $S/lib/octos/ first. octos's profile and Kimi
# Code's config hold the relay's address: the image has a template (u.json.in) and links;
# ohm-sandbox fills /run/ohm-secrets at start.
B=$S/lib/octos
cp $B/octos-bundle-aarch64-unknown-linux-gnu.tar.gz $R/tmp/octos-bundle.tar.gz &&
  cp $B/octoscode-aarch64-unknown-linux-gnu.tar.xz $R/tmp/octoscode.tar.xz && chmod 644 $R/tmp/octos*.tar.*
$O run /usr/bin/su - $user -c 'set -a; . ~/.config/environment.d/50-mirrors.conf; . ~/.config/environment.d/60-proxy.conf; set +a
export PATH=$HOME/.local/share/mise/shims:$PATH OCTOSCODE_NO_AUTO_INSTALL=1 OCTOS_NO_MODEL_DOWNLOAD=1 KIMI_CODE_NO_AUTO_UPDATE=1
OCTOS_BUNDLE_URL=file:///tmp/octos-bundle.tar.gz npm install -g --allow-scripts=@octos-org/octos,@moonshot-ai/kimi-code \
  @octos-org/octoscode @octos-org/octos @moonshot-ai/kimi-code > /dev/null 2>&1; mise reshim 2>/dev/null
d=$(npm root -g)/@octos-org/octoscode/node_modules/.bin_real; mkdir -p $d /tmp/ocx && tar -xJf /tmp/octoscode.tar.xz -C /tmp/ocx &&
  install -m 755 "$(find /tmp/ocx -type f -name octoscode | head -1)" $d/octoscode; rm -rf /tmp/ocx
printf "%s\n" OCTOSCODE_NO_AUTO_INSTALL=1 OCTOS_NO_MODEL_DOWNLOAD=1 KIMI_CODE_NO_AUTO_UPDATE=1 > ~/.config/environment.d/65-octos.conf
mkdir -p ~/.kimi-code ~/.octos/profiles && ln -sfn /run/ohm-secrets/kimi-config.toml ~/.kimi-code/config.toml
rm -f ~/.octos/profiles/u.json ~/.octos/profiles/u.json.in
printf "%s\n" "{\"jsonrpc\":\"2.0\",\"id\":\"1\",\"method\":\"profile/local/create\",\"params\":{\"name\":\"U\",\"username\":\"U\",\"email\":\"U@localhost\"}}" |
  timeout 60 octos serve --stdio --solo > /dev/null 2>&1
python3 -c "
import json, os
p = os.path.expanduser(\"~/.octos/profiles/u.json\"); d = json.load(open(p))
d.setdefault(\"config\", {})[\"llm\"] = {\"primary\": {\"family_id\": \"openai\", \"model_id\": \"kimi/kimi-for-coding\",
  \"route\": {\"route_id\": \"custom\", \"label\": \"relay\", \"base_url\": \"@OPENAI_BASE_URL@\", \"api_key_env\": \"OPENAI_API_KEY\", \"api_type\": \"openai\"},
  \"model_hints\": {\"fixed_temperature\": True}}}
json.dump(d, open(p + \".in\", \"w\"), indent=2); os.remove(p); os.symlink(\"/run/ohm-secrets/octos-u.json\", p)"'
rm -f $R/tmp/octos-bundle.tar.gz $R/tmp/octoscode.tar.xz
$O secrets > /dev/null
$O run /usr/bin/su $user -c 'export PATH=$HOME/.local/bin:$PATH; cd /tmp
q="Reply with exactly the word PONG and nothing else"
echo "opencode: $(timeout 240 opencode run "$q" 2>&1 | tail -1)"
echo "codex: $(timeout 240 codex exec --skip-git-repo-check "$q" 2>&1 | tail -1)"
echo "claude: $(timeout 240 claude -p "$q" 2>&1 | tail -1)"' 2>&1 | grep -v -i -e "sk-" -e "https://"
