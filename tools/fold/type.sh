#!/usr/bin/env bash
# type.sh 'TEXT': type into the focused VM window and press Enter.
# VM_X/VM_Y must point inside the VM window (default: centre of the Fold screen).
# The text must not contain single quotes; long lines may be dropped, so keep
# commands short.
. "$(dirname "$0")/env.sh"
hs "uitest uiInput inputText ${VM_X:-1236} ${VM_Y:-700} '$1'" >/dev/null
sleep 0.5
hs "uitest uiInput keyEvent 2054" >/dev/null
