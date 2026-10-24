#!/usr/bin/env python3
"""Sound latency, session side (tests/audio/run.sh runs it as the desktop user).

Plays beeps through the Pulse server (pipewire-pulse) and prints, for each, the
CLOCK_MONOTONIC time it was handed to the sound server:
  cold  paplay of a beep after 3 s of silence (the app's renderer is stopped)
  warm  a stream from pacat paced in real time: quiet noise, then a beep (renderer
        already running; only the beep counts as an onset)
The display app logs when the speaker played each onset ("onset played at") on
the same clock; run.sh pairs them up.
"""
import math
import os
import struct
import subprocess
import time
import wave

RATE = 48000
ROUNDS = int(os.environ.get("ROUNDS", "5"))


def beep(seconds=0.2, amp=8000):
    return b"".join(struct.pack("<hh", v, v)
                    for v in (int(amp * math.sin(2 * math.pi * 1000 * i / RATE)) for i in range(int(RATE * seconds))))


def quiet(seconds):
    # nonzero but below the app's onset threshold: keeps its renderer running
    return b"".join(struct.pack("<hh", v, v) for v in (20 if i % 2 else -20 for i in range(int(RATE * seconds))))


wav = "/tmp/ohm-tests/beep.wav"
with wave.open(wav, "w") as w:
    w.setnchannels(2)
    w.setsampwidth(2)
    w.setframerate(RATE)
    w.writeframes(beep())

for _ in range(ROUNDS):
    time.sleep(3)  # the app stops its renderer after 2 s of silence
    t0 = time.clock_gettime_ns(time.CLOCK_MONOTONIC)
    subprocess.run(["paplay", wav], check=True)
    print(f"cold {t0}", flush=True)

p = subprocess.Popen(["pacat", "--raw", "--format=s16le", f"--rate={RATE}", "--channels=2",
                      "--latency-msec=20", "--client-name=ohm-latency"], stdin=subprocess.PIPE)
chunk = RATE // 100 * 4  # 10 ms
start = time.monotonic()
written = 0


def paced(data):
    """Write in 10 ms pieces at real-time pace; returns the clock when the first piece went out."""
    global written
    first = None
    for i in range(0, len(data), chunk):
        due = start + written / (RATE * 4)
        delay = due - time.monotonic()
        if delay > 0:
            time.sleep(delay)
        if first is None:
            first = time.clock_gettime_ns(time.CLOCK_MONOTONIC)
        p.stdin.write(data[i:i + chunk])
        p.stdin.flush()
        written += len(data[i:i + chunk])
    return first


paced(quiet(1.0))
for _ in range(ROUNDS):
    t0 = paced(beep())
    print(f"warm {t0}", flush=True)
    paced(quiet(1.0))
p.stdin.close()
p.wait()
