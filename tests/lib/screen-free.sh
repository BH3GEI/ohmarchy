#!/bin/bash
# screen-free.sh: succeed only if the HarmonyOS screen is free for a test that shows
# the display app. The screen and focus belong to whoever holds
# /data/local/screen.lock (a directory with an owner file; /data/local/vm.lock is
# only for the hypervisor). Tests that bring the app to the front must wait.
# HOLD_LOCK=1: the lock is ours (its owner names the native-desktop line), go ahead.
HOST=${OHOS_HOST:-ohdev}
owner=$(perl -e 'alarm 30; exec @ARGV' ssh -o ConnectTimeout=15 "$HOST" \
    'if [ -e /data/local/screen.lock ]; then echo HELD; cat /data/local/screen.lock/owner 2>/dev/null; fi' 2>/dev/null)
if [ -n "$HOLD_LOCK" ] && echo "$owner" | grep -q "native-desktop"; then
    exit 0
fi
if [ -n "$owner" ]; then
    echo "screen busy: /data/local/screen.lock is held (${owner#HELD}); not opening the display app" >&2
    exit 1
fi
