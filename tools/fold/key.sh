#!/usr/bin/env bash
# key.sh CODE [CODE CODE]: press a key or a chord (HarmonyOS key codes), e.g.
#   Enter 2054  Esc 2070  Up 2012  Down 2013  Backspace 2055  F9 2098
#   Ctrl+Alt+Del: key.sh 2072 2045 2071   (reboots a systemd guest)
. "$(dirname "$0")/env.sh"
hs "uitest uiInput keyEvent $*"
