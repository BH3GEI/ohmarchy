#!/system/bin/sh
# Coding agents for the sandbox's desktop user, through the API relay, with the
# configuration every route uses (hongrong/pure/guest/setup-ai.sh); the sandbox's
# counterpart of native/desktop/ai/setup.sh. Root on the HarmonyOS host, the sandbox
# running:  sh native/sandbox/ai-setup.sh [user]   (default builder)
# The relay's address and key are read from /data/local/secrets/ai.env (root, 600)
# and only ever written to the user's ~/.config/environment.d/ai.conf (600) and the
# agents' configs in their home; nothing here prints them. Run again after ai.env
# changes. Then each agent answers one prompt.
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
cp $E $R$t/ai.env && cp $here/../../hongrong/pure/guest/setup-ai.sh $R$t/setup-ai.sh
chown $uid:$uid $R$t/ai.env $R$t/setup-ai.sh && chmod 600 $R$t/ai.env
$O run /usr/bin/su $user -c "bash $t/setup-ai.sh $t/ai.env --install | tail -1" || true
rm -rf $R$t
$O run /usr/bin/su $user -c 'export PATH=$HOME/.local/bin:$PATH; cd /tmp
q="Reply with exactly the word PONG and nothing else"
echo "opencode: $(timeout 240 opencode run "$q" 2>&1 | tail -1)"
echo "codex: $(timeout 240 codex exec --skip-git-repo-check "$q" 2>&1 | tail -1)"
echo "claude: $(timeout 240 claude -p "$q" 2>&1 | tail -1)"' 2>&1 | grep -v -i -e "sk-" -e "https://"
