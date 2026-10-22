#!/usr/bin/env bash
# tap.sh X Y: click at physical screen coordinates (the Fold screen is 2472x1608)
. "$(dirname "$0")/env.sh"
hs "uitest uiInput click $1 $2"
