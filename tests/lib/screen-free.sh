#!/bin/bash
# screen-free.sh: succeed only if the HarmonyOS screen is free for a test that shows
# the display app. Whoever holds /data/local/vm.lock (a directory with an owner
# file) owns the screen and focus; tests that bring the app to the front must wait.
HOST=${OHOS_HOST:-ohdev}
owner=$(perl -e 'alarm 30; exec @ARGV' ssh -o ConnectTimeout=15 "$HOST" \
    'if [ -e /data/local/vm.lock ]; then echo HELD; cat /data/local/vm.lock/owner 2>/dev/null; fi' 2>/dev/null)
if [ -n "$owner" ]; then
    echo "screen busy: /data/local/vm.lock is held (${owner#HELD}); not opening the display app" >&2
    exit 1
fi
