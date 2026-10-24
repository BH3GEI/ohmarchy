#!/bin/bash
# Security checks for route D (E). Prints one line per check: PASS / FAIL / INFO.
#   desktop-user     the desktop's processes run as the ordinary desktop user
#   root-in-session  which processes run as root in the session
#   sudo             whether the desktop user gets root without a password
#   host-context     host-side processes of route D and their SELinux context
#   listeners        TCP ports route D opens on the host
#   browser-sandbox  whether the default browser runs sandboxed (Firefox)
#   webapp-sandbox   whether Omarchy's web apps open in the sandboxed browser
#   seccomp          whether the kernel takes seccomp-bpf filters (for sandboxes)
here=$(cd "$(dirname "$0")" && pwd)
B=${ARCH_BASE:-/data/local/archtest}
user=${ARCH_USER:-builder}
{
    echo "B=$B; U=$user"
    cat <<'SH'
P=$(cat $B/session.pid)
ins() { nsenter -t $P -m -p -- chroot $B/arch /usr/bin/env -i PATH=/usr/bin /bin/bash -c "$1"; }
bad=$(ins "for c in Hyprland quickshell Xwayland pipewire wireplumber fcitx5; do ps -o user= -C \$c; done | sort -u | grep -vx $U")
[ -z "$bad" ] && echo "PASS desktop-user: Hyprland, shell, Xwayland, sound, input method run as $U" || echo "FAIL desktop-user: also as $bad"
echo "INFO root-in-session: $(ins "ps -eo user=,comm= | awk '\$1==\"root\" {print \$2}' | grep -vxE 'bash|ps|awk|sort|uniq|tr|su|catatonit|sh' | sort | uniq -c | awk '{printf \"%s%s \", \$2, (\$1>1 ? \"x\"\$1 : \"\")}'")"
s=$(ins "su - $U -c 'sudo -n true' < /dev/null 2>&1 && echo yes")
[ "$s" = yes ] && echo "FAIL sudo: $U gets root without a password (wheel NOPASSWD); session root is host root (no user namespaces, context u:r:su:s0)" \
    || echo "PASS sudo: $U needs a password for root"
for p in $(ps -ef | grep -E "virgl_test_server|vtest-broker|catatonit" | grep -v grep | awk '{print $2}'); do
    echo "INFO host-context: $(cat /proc/$p/attr/current 2>/dev/null | tr -d '\0') $(stat -c %U /proc/$p) $(timeout 2 tr '\0' ' ' < /proc/$p/cmdline | cut -d' ' -f1 | xargs basename)"
done
l=$(netstat -ltnp 2>/dev/null | awk '/LISTEN/ {print $4, $7}' | grep -vE "softbus|ohsshd")
echo "INFO listeners: ${l:-none}"
echo "$l" | grep -qE "^(0\.0\.0\.0|\[?::\]?):" && echo "FAIL listeners: route D listens on all interfaces" || echo "PASS listeners: route D listens on loopback only"
d=$(ins "su - $U -c 'xdg-settings get default-web-browser' < /dev/null 2>/dev/null")
case "$d" in
firefox*) echo "PASS browser-sandbox: the default browser is Firefox (content processes under seccomp-bpf)" ;;
*) echo "FAIL browser-sandbox: the default browser is ${d:-unknown}" ;;
esac
w=$(ins "[ -x /opt/ohmarchy/overrides/omarchy-launch-webapp ] && grep -q /opt/ohmarchy/overrides /home/$U/.config/hypr/ohdisplay.lua && echo yes")
[ "$w" = yes ] && echo "PASS webapp-sandbox: Omarchy's web apps open in Firefox (route D's omarchy-launch-webapp, ahead in the apps' PATH)" \
    || echo "FAIL webapp-sandbox: web apps open in Chromium"
f=$(ins "grep -x -- --no-sandbox /home/$U/.config/chromium-flags.conf")
[ -n "$f" ] && echo "INFO chromium: started by hand, Chromium still runs with --no-sandbox (it cannot sandbox itself here)"
ins "cat > /tmp/seccomp-check.py <<'PY'
import ctypes, struct
libc = ctypes.CDLL(None, use_errno=True)
libc.prctl(38, 1, 0, 0, 0)
f = (ctypes.c_ubyte * 8).from_buffer_copy(struct.pack('<HBBI', 6, 0, 0, 0x7fff0000))
class P(ctypes.Structure):
    _fields_ = [('len', ctypes.c_ushort), ('f', ctypes.c_void_p)]
print('ok' if libc.syscall(277, 1, 0, ctypes.byref(P(1, ctypes.addressof(f)))) == 0 else 'no')
PY
python3 /tmp/seccomp-check.py" | grep -q ok && echo "PASS seccomp: the kernel takes seccomp-bpf filters" || echo "FAIL seccomp: no seccomp-bpf"
SH
} | "$here/../lib/remote.sh" security host 120
