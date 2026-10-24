#!/bin/bash
# Sound latency end to end: from handing a beep to the session's sound server to the
# HarmonyOS speaker playing it (tests/audio/latency.py, and the display app's
# "onset played at" log line, both on CLOCK_MONOTONIC). The display app must be open.
#   ROUNDS  beeps per kind (default 5);  ARCH_USER  desktop user (default builder)
here=$(cd "$(dirname "$0")" && pwd)
user=${ARCH_USER:-builder}
B=${ARCH_BASE:-/data/local/archtest}
{
    echo "B=$B; P=\$(cat $B/session.pid); T=/proc/\$P/root/tmp/ohm-tests"
    echo "mkdir -p \$T && chmod 777 \$T"
    echo "cat > \$T/latency.py <<'END_OF_PY'"; cat "$here/latency.py"; echo "END_OF_PY"
    cat <<SH
# the log buffer turns over within seconds on a busy host: follow it during the run
hilog -T ohdisp-audio > \$T/marks.log 2>&1 & hp=\$!
nsenter -t \$P -m -p -- chroot $B/arch /usr/bin/env -i PATH=/usr/bin /usr/bin/su - $user -c \\
    'XDG_RUNTIME_DIR=/run/user/\$(id -u) ROUNDS=${ROUNDS:-5} python3 /tmp/ohm-tests/latency.py' < /dev/null
sleep 1
kill \$hp
echo "=== ONSETS"
grep "onset played" \$T/marks.log
SH
} | "$here/../lib/remote.sh" audio-latency host 300 | python3 -c '
import re, statistics, sys
lines = sys.stdin.read().split("=== ONSETS")
sent = [l.split() for l in lines[0].splitlines() if re.match(r"^(cold|warm) \d+$", l)]
played = sorted(int(m) for m in re.findall(r"onset played at (\d+) ns", lines[1] if len(lines) > 1 else ""))
res, missed = {}, 0
for kind, t0 in sent:
    t0 = int(t0)
    after = [t for t in played if t0 < t < t0 + 1e9]  # the first onset after the beep was sent
    if not after:
        missed += 1
        continue
    res.setdefault(kind, []).append((after[0] - t0) / 1e6)
if missed or not res:
    print(f"{missed} of {len(sent)} beeps were not timed by the app"); print(lines[0][-800:])
    if not res:
        sys.exit(1)
for kind, v in res.items():
    print(f"{kind}: " + " ".join(f"{x:.0f}" for x in v) + f" ms; median {statistics.median(v):.0f} ms, max {max(v):.0f} ms")
'
