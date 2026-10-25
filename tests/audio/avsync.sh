#!/bin/bash
# A/V sync with mpv: a video with a white flash and a 1 kHz beep at the start of
# every second, played full screen (mpv's Wayland shm output: CPU, as the
# session's clients render by default). The display app logs when each flash reaches it
# ("flash shown at") and when the speaker plays each beep ("onset played at"), both
# on CLOCK_MONOTONIC; offset = sound - picture (positive: sound late). The display
# app must be open. The picture still needs one HarmonyOS vsync (about 8 ms at
# 120 Hz) after the app has it, which this does not count.
#   MPV_ARGS  extra mpv options (default: none);  ARCH_USER  desktop user
here=$(cd "$(dirname "$0")" && pwd)
user=${ARCH_USER:-builder}
B=${ARCH_BASE:-/data/local/archtest}
{
    echo "B=$B; P=\$(cat $B/session.pid); T=/proc/\$P/root/tmp/ohm-tests"
    echo "mkdir -p \$T && chmod 777 \$T"
    cat <<'SH'
cat > $T/avsync-play.sh <<'EOF2'
f=/tmp/ohm-tests/avsync.mp4
[ -s $f ] || { ffmpeg -loglevel error -f lavfi -i "color=black:s=640x360:r=60:d=12" \
    -f lavfi -i "sine=f=1000:sample_rate=48000:d=12" \
    -filter_complex "[0]drawbox=c=white:t=fill:enable='lt(mod(t,1),0.1)*gte(t,2)'[v];[1]volume=0:enable='gte(mod(t,1),0.1)+lt(t,2)'[a]" \
    -map "[v]" -map "[a]" -c:v libx264 -preset ultrafast -pix_fmt yuv420p -c:a pcm_s16le $f.mkv && mv $f.mkv $f; }
export XDG_RUNTIME_DIR=/run/user/$(id -u) WAYLAND_DISPLAY=wayland-1
mpv --fs --really-quiet --no-config --vo=wlshm $MPV_ARGS $f
EOF2
chmod 755 $T/avsync-play.sh
# the log buffer turns over within seconds on a busy host: follow it during the run
hilog -T ohdisp,ohdisp-audio > $T/marks.log 2>&1 & hp=$!
SH
    echo "nsenter -t \$P -m -p -- chroot $B/arch /usr/bin/env -i PATH=/usr/bin /usr/bin/su - $user -c 'MPV_ARGS=\"${MPV_ARGS:-}\" sh /tmp/ohm-tests/avsync-play.sh' < /dev/null"
    echo 'sleep 1; kill $hp; echo "=== MARKS"; grep -E "onset played|flash shown" $T/marks.log'
} | "$here/../lib/remote.sh" audio-avsync host 300 | python3 -c '
import re, statistics, sys
text = sys.stdin.read()
marks = text.split("=== MARKS")[-1]
flash = [int(x) for x in re.findall(r"flash shown at (\d+)", marks)]
sound = [int(x) for x in re.findall(r"onset played at (\d+)", marks)]
pairs = []
for f in flash:
    near = [s for s in sound if abs(s - f) < 400e6]
    if near:
        pairs.append((min(near, key=lambda s: abs(s - f)) - f) / 1e6)
print(f"{len(flash)} flashes, {len(sound)} beeps, {len(pairs)} pairs")
if not pairs:
    print(text[-1500:]); sys.exit(1)
print("sound - picture (ms): " + " ".join(f"{x:+.0f}" for x in pairs))
rest = pairs[1:] or pairs
print(f"after the first: median {statistics.median(rest):+.0f} ms, range {min(rest):+.0f}..{max(rest):+.0f} ms")
'
