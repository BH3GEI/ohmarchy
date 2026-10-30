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
# Octos's coding agent (octoscode) and Kimi Code (kimi), npm, on the same relay. octos (the
# server) reads ~/.config/octos/config.json, which names the relay only through ai.conf's
# variables; Kimi Code's config is written at start into /run/ohm-secrets (ohm-sandbox)
$O run /usr/bin/su - $user -c 'set -a; . ~/.config/environment.d/50-mirrors.conf; . ~/.config/environment.d/60-proxy.conf; set +a
export PATH=$HOME/.local/share/mise/shims:$PATH
npm install -g @octos-org/octoscode @octos-org/octos @moonshot-ai/kimi-code > /dev/null 2>&1 && mise reshim 2>/dev/null
mkdir -p ~/.kimi-code && ln -sfn /run/ohm-secrets/kimi-config.toml ~/.kimi-code/config.toml
mkdir -p ~/.config/octos && cat > ~/.config/octos/config.json <<J
{
  "provider": "anthropic",
  "model": "\${ANTHROPIC_MODEL}",
  "base_url": "\${ANTHROPIC_BASE_URL}",
  "api_key_env": "ANTHROPIC_AUTH_TOKEN"
}
J
echo OCTOSCODE_NO_AUTO_INSTALL=1 > ~/.config/environment.d/65-octos.conf'
$O run /usr/bin/su $user -c 'export PATH=$HOME/.local/bin:$PATH; cd /tmp
q="Reply with exactly the word PONG and nothing else"
echo "opencode: $(timeout 240 opencode run "$q" 2>&1 | tail -1)"
echo "codex: $(timeout 240 codex exec --skip-git-repo-check "$q" 2>&1 | tail -1)"
echo "claude: $(timeout 240 claude -p "$q" 2>&1 | tail -1)"' 2>&1 | grep -v -i -e "sk-" -e "https://"
