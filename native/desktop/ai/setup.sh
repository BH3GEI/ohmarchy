#!/system/bin/sh
# Coding agents for route D's desktop user, through the API relay, with the
# configuration every route uses (hongrong/pure/guest/setup-ai.sh). Root on the
# HarmonyOS host:  sh native/desktop/ai/setup.sh [user]   (default builder)
# The relay's address and key are read from /data/local/secrets/ai.env (root, 600)
# and only ever written to the user's ~/.config/environment.d/ai.conf (600) and
# the agents' configs in their home; nothing here prints them. The desktop
# session reads environment.d (ohdisplay.lua), login shells through
# /etc/profile.d/ohmarchy-environment.sh. Then each agent answers one prompt.
set -e
here=$(cd "$(dirname "$0")" && pwd)
B=${ARCH_BASE:-/data/local/archtest}
user=${1:-builder}
S=/data/local/secrets/ai.env
[ -r $S ] || { echo "no $S" >&2; exit 1; }
R=/proc/$(cat $B/session.pid)/root
uid=$(grep "^$user:" $R/etc/passwd | cut -d: -f3)
home=$(grep "^$user:" $R/etc/passwd | cut -d: -f6)
# the env file and the script, readable only by that user, for the run
t=$R/tmp/ohm-ai.$$; mkdir -m 700 $t; chown $uid:$uid $t
cp $S $t/ai.env && cp $here/../../../hongrong/pure/guest/setup-ai.sh $t/setup-ai.sh
chown $uid:$uid $t/ai.env $t/setup-ai.sh; chmod 600 $t/ai.env
rm -f $R$home/.config/environment.d/60-ai.conf   # an earlier version's file
sh $B/bin/omarchy -c "bash /tmp/ohm-ai.$$/setup-ai.sh /tmp/ohm-ai.$$/ai.env --install | tail -1" || true
rm -rf $t
sh $B/bin/omarchy -c 'export PATH=$HOME/.local/bin:$PATH; cd /tmp
q="Reply with exactly the word PONG and nothing else"
echo "opencode: $(timeout 240 opencode run "$q" 2>&1 | tail -1)"
echo "codex: $(timeout 240 codex exec --skip-git-repo-check "$q" 2>&1 | tail -1)"
echo "claude: $(timeout 240 claude -p "$q" 2>&1 | tail -1)"' 2>&1 | grep -v -i -e "sk-" -e "https://"
