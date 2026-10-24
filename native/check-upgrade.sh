#!/bin/bash
# After `pacman -Syu` in the session (run there as root: sh arch.sh run
# check-upgrade.sh): is what 40-install-desktop.sh built still good against the
# upgraded system? Hyprland and aquamarine in /opt/ohmarchy are built from source
# against the libraries of the day; an upgrade can change a soname under them.
# Prints PASS/FAIL lines; exit 1 means: run 40-install-desktop.sh again.
fail=0
missing=$(for f in /opt/ohmarchy/bin/* /opt/ohmarchy/lib/*.so* /usr/local/lib/*.so; do
    [ -f "$f" ] && file -b "$f" | grep -q ELF && ldd "$f" 2>/dev/null | grep "not found" | sed "s|^|$f: |"
done | sort -u)
if [ -n "$missing" ]; then
    echo "FAIL libraries: missing after the upgrade:"; echo "$missing" | sed 's/^/  /'; fail=1
else
    echo "PASS libraries: everything in /opt/ohmarchy and the preloads resolves"
fi
v=$(XDG_RUNTIME_DIR=/tmp /opt/ohmarchy/bin/Hyprland --version 2>&1 | head -1)
case "$v" in
Hyprland*) echo "PASS hyprland: $v" ;;
*) echo "FAIL hyprland: --version says: $v"; fail=1 ;;
esac
pre=0
for l in $(cat /etc/ld.so.preload 2>/dev/null); do
    [ -f "$l" ] || { echo "FAIL preload: $l listed in /etc/ld.so.preload but missing"; pre=1; fail=1; }
done
[ $pre = 0 ] && echo "PASS preload: $(wc -w < /etc/ld.so.preload) libraries present"
pv=$(pacman -Q hyprland aquamarine 2>/dev/null | tr '\n' ' ')
echo "INFO packaged versions: $pv(ours: Hyprland 0.56.2, aquamarine 0.15.1; a newer packaged Hyprland means the patches need porting)"
exit $fail
