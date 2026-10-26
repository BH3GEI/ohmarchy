#!/usr/bin/env bash
# Re-link the built Hyprland as a dlopen-able shared library libhyprland.so (route J: the
# spawner dlopens it and calls main; no execve of a PIE, which the HAP/HongMeng won't run).
# Run after Hyprland's normal build (on the case-sensitive volume). Reuses the exe's exact link
# line from ninja, turned into a shared lib:
#   -shared -fPIC                      : shared object
#   -Wl,-Bsymbolic                     : bind intra-DSO global refs locally -> no text relocs
#                                        (TEXTREL would need writable code, which XPM blocks)
#   -Wl,--no-dynamic-linker            : no PT_INTERP (it's a library, loaded by dlopen)
#   -Wl,-soname,libhyprland.so         : clean soname
#   -Wl,--export-dynamic-symbol=main   : keep main dlsym-able
#   whole-archive libhyprland_lib.a    : pull every compositor object (main.cpp.o stays once)
set -euo pipefail
BUILD="${1:?usage: make-libhyprland-so.sh <Hyprland/build dir>}"
cd "$BUILD"
ninja -t commands Hyprland | tail -1 | sed 's/^: && //; s/ && :$//' > /tmp/hl_raw.sh
python3 - /tmp/hl_raw.sh /tmp/hl_so.sh <<'PY'
import sys
c=open(sys.argv[1]).read().strip()
c=c.replace("-o Hyprland ",
  "-shared -fPIC -Wl,-Bsymbolic -Wl,-soname,libhyprland.so -Wl,--no-dynamic-linker -Wl,--export-dynamic-symbol=main -o libhyprland.so ")
c=c.replace("-Wl,--export-dynamic -rdynamic ","").replace("-Wl,--export-dynamic ","").replace("-rdynamic ","")
c=c.replace("  libhyprland_lib.a  -lrt  libhyprland_lib.a  ",
            "  -Wl,--whole-archive libhyprland_lib.a -Wl,--no-whole-archive  -lrt  ",1)
open(sys.argv[2],'w').write(c)
PY
sh /tmp/hl_so.sh
echo "built $BUILD/libhyprland.so"
/opt/homebrew/opt/llvm/bin/llvm-readelf -d libhyprland.so | grep -E 'SONAME|TEXTREL' || true
