#!/bin/bash
# Is there sound going out? Session side, without the display app: plays a 1 kHz
# tone at -12 dBFS with paplay and records the "HarmonyOS" sink's monitor (what the
# relay sends to the app) at the same time; prints the recorded level in RMS and
# dBFS, and the same with nothing playing. The app's side (it detects the beeps in
# the PCM it hands to OHAudio, and the renderer plays them) is tests/audio/run.sh.
here=$(cd "$(dirname "$0")" && pwd)
user=${ARCH_USER:-builder}
cat <<SH | "$here/../lib/remote.sh" audio-level chroot 120
su - $user -c '
export XDG_RUNTIME_DIR=/run/user/\$(id -u)
python3 - <<"PY"
import math, struct, subprocess, threading, time, wave
rate = 48000
amp = int(32767 * 10 ** (-12 / 20))
with wave.open("/tmp/ohm-tests/level-tone.wav", "w") as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(rate)
    w.writeframes(b"".join(struct.pack("<hh", v, v) for v in (int(amp * math.sin(2 * math.pi * 1000 * i / rate)) for i in range(rate * 2))))
def record(seconds, play):
    rec = subprocess.Popen(["stdbuf", "-o0", "pw-record", "--raw", "--target", "ohmarchy-out", "-P", "{ stream.capture.sink = true }",
                            "--rate", "48000", "--channels", "2", "--format", "s16", "-"], stdout=subprocess.PIPE)
    chunks = []
    def drain():  # read while recording: a full pipe (64 KB, 0.3 s) would stall pw-record
        while True:
            c = rec.stdout.read1(65536)
            if not c:
                return
            chunks.append(c)
    t = threading.Thread(target=drain); t.start()
    time.sleep(0.3)
    if play:
        subprocess.Popen(["paplay", "/tmp/ohm-tests/level-tone.wav"])
    time.sleep(seconds)
    rec.terminate(); t.join(5)
    data = b"".join(chunks)
    n = len(data) // 2
    s = struct.unpack("<%dh" % n, data[:n * 2]) if n else ()
    peak = max((abs(x) for x in s), default=0)
    loud = [x for x in s if abs(x) > 64]  # the tone part only: its start depends on timing
    rms = math.sqrt(sum(x * x for x in loud) / len(loud)) if loud else 0
    db = lambda v: 20 * math.log10(v / 32767) if v > 0 else float("-inf")
    return peak, db(peak), rms, db(rms), len(loud), n
for label, play in (("silence", False), ("tone -12 dBFS peak (-15 dBFS RMS)", True)):
    peak, pdb, rms, rdb, nl, n = record(3, play)
    print(f"{label}: peak {peak} ({pdb:.1f} dBFS), RMS over the {nl} non-silent of {n} samples {rms:.0f} ({rdb:.1f} dBFS)")
PY' < /dev/null
SH
