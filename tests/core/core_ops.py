#!/usr/bin/env python3
"""Core operations in the native desktop (acceptance A2).

Runs inside the Arch session as the desktop user with the session's environment
(tests/core/run.sh does that). Each check prints one line: name, PASS/FAIL, seconds,
detail; the results also go to $OUT as JSON lines.

  file-libreoffice  save a Writer document with Chinese and English text, read it back
  file-nvim         write a file from Neovim, read it back
  clipboard         copy in one Wayland client (wl-copy), paste in another (wl-paste)
  chinese-input     type "nihao" + space through fcitx5 pinyin into a foot window
  audio             play a short tone (PipeWire/PulseAudio, then ALSA)
  file-chooser      ask the desktop portal for an Open File dialog, see it appear
"""
import json
import os
import shlex
import socket
import struct
import subprocess
import tempfile
import time

OUT = os.environ.get("OUT", "/tmp/ohm-tests/core.jsonl")
TEXT = "验收测试 acceptance 123"
work = tempfile.mkdtemp(prefix="ohm-core-")


def sh(cmd, timeout=30):
    p = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout)
    return p.returncode, (p.stdout + p.stderr).strip()


def clients():
    try:
        return json.loads(sh("hyprctl clients -j", 5)[1] or "[]")
    except json.JSONDecodeError:
        return []


def wait_window(pred, timeout=10):
    t0 = time.monotonic()
    while time.monotonic() - t0 < timeout:
        for c in clients():
            if pred(c):
                return c
        time.sleep(0.1)
    return None


def keys(seq):
    """Send evdev key events through aquamarine's export input device."""
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect("\0" + os.environ.get("AQ_HEADLESS_EXPORT", "ohmarchy-display"))
    for code, down in seq:
        s.send(struct.pack("<4i", 4, code, down, 0))
        time.sleep(0.06)
    s.close()


def focus(win):
    """Focus a window and put the pointer on it: a Hyprland that has had no input
    yet does not give new windows keyboard focus (the app's pointer events do)."""
    sh(f"hyprctl eval {shlex.quote('hl.dispatch(hl.dsp.focus({ window = "address:' + win['address'] + '" }))')}", 5)
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect("\0" + os.environ.get("AQ_HEADLESS_EXPORT", "ohmarchy-display"))
    s.send(struct.pack("<4i", 1, win["at"][0] + win["size"][0] // 2, win["at"][1] + win["size"][1] // 2, 0))
    s.close()
    time.sleep(0.3)


def tap(*codes):
    return [(c, 1) for c in codes] + [(c, 0) for c in reversed(codes)]


def file_libreoffice():
    src = os.path.join(work, "doc.txt")
    open(src, "w").write(TEXT + "\n")
    rc, out = sh(f"cd {work} && soffice --headless --convert-to odt doc.txt", 90)
    odt = os.path.join(work, "doc.odt")
    if not os.path.exists(odt):
        return False, f"no .odt written: {out[-200:]}"
    os.remove(src)
    rc, out = sh(f"cd {work} && soffice --headless --convert-to txt:Text doc.odt", 90)
    back = open(src, encoding="utf-8-sig").read().strip() if os.path.exists(src) else ""
    return back == TEXT, f"read back {back!r}"


def file_nvim():
    path = os.path.join(work, "nvim.txt")
    sh(f"nvim --headless -c {shlex.quote('call setline(1, ' + json.dumps(TEXT) + ')')} -c {shlex.quote('wq ' + path)}", 30)
    back = open(path).read().strip() if os.path.exists(path) else ""
    return back == TEXT, f"read back {back!r}"


def clipboard():
    p = subprocess.Popen(["wl-copy"], stdin=subprocess.PIPE, text=True)
    p.communicate(TEXT, timeout=10)
    time.sleep(0.3)
    rc, out = sh("wl-paste --no-newline", 10)
    return out == TEXT, f"pasted {out!r}"


def chinese_input():
    path = os.path.join(work, "zh.txt")
    title = "ohm-zh-test"
    sh(f"hyprctl eval {shlex.quote(f'hl.exec_cmd([[foot -T {title} sh -c {shlex.quote(f'cat > {path}')}]])')}", 5)
    win = wait_window(lambda c: c.get("title") == title)
    if not win:
        return False, "foot window did not appear"
    time.sleep(0.5)
    focus(win)
    state = sh("fcitx5-remote", 5)[1]
    seq = []
    if state != "2":
        seq += tap(29, 57)  # Ctrl+Space: pinyin on
    for k in (49, 23, 35, 30, 24):  # n i h a o
        seq += tap(k)
    seq += tap(57)  # space picks the first candidate
    seq += tap(28)  # Enter
    seq += tap(29, 57)  # Ctrl+Space: back to English
    seq += tap(29, 32)  # Ctrl+D ends cat
    keys(seq)
    time.sleep(1)
    got = open(path).read().strip() if os.path.exists(path) else ""
    if wait_window(lambda c: c.get("title") == title, 1):
        try:
            os.kill(win["pid"], 15)
        except ProcessLookupError:
            pass
    return got == "你好", f"typed {got!r} (fcitx5 state before: {state})"


def audio():
    wav = os.path.join(work, "tone.wav")
    import math, wave
    with wave.open(wav, "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(48000)
        w.writeframes(b"".join(struct.pack("<h", int(8000 * math.sin(2 * math.pi * 440 * i / 48000)))
                               for i in range(48000 // 2)))
    for cmd in ("pw-play", "paplay", "aplay -q"):
        rc, out = sh(f"{cmd} {wav}", 10)
        if rc == 0:
            return True, f"played with {cmd.split()[0]}"
    snd = "present" if os.path.exists("/dev/snd") else "absent"
    return False, f"no player worked; /dev/snd {snd}; last: {out[-160:]}"


def file_chooser():
    before = {c["address"] for c in clients()}
    p = subprocess.Popen(
        "gdbus call --session --dest org.freedesktop.portal.Desktop --object-path /org/freedesktop/portal/desktop "
        "--method org.freedesktop.portal.FileChooser.OpenFile '' 'Acceptance test' '{}'",
        shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    win = wait_window(lambda c: c["address"] not in before, 15)
    detail = f"dialog: {win['class']} | {win['title']}" if win else "no dialog appeared"
    if win:
        focus(win)
        keys(tap(1))  # Escape cancels the dialog
        time.sleep(0.5)
    try:
        out = p.communicate(timeout=5)[0].strip()
    except subprocess.TimeoutExpired:
        p.kill()
        out = "(portal call still waiting)"
    return win is not None, f"{detail}; portal: {out[:120]}"


CHECKS = [("file-libreoffice", file_libreoffice), ("file-nvim", file_nvim), ("clipboard", clipboard),
          ("chinese-input", chinese_input), ("audio", audio), ("file-chooser", file_chooser)]


def main():
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w") as out:
        for name, fn in CHECKS:
            t0 = time.monotonic()
            try:
                ok, detail = fn()
            except Exception as e:  # report and carry on
                ok, detail = False, f"error: {e}"
            rec = dict(check=name, result="pass" if ok else "fail", seconds=round(time.monotonic() - t0, 2),
                       detail=detail)
            out.write(json.dumps(rec, ensure_ascii=False) + "\n")
            print(f"{name:18} {'PASS' if ok else 'FAIL'} {rec['seconds']:>6} s  {detail}", flush=True)


if __name__ == "__main__":
    main()
