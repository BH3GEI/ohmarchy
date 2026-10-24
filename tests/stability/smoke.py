#!/usr/bin/env python3
"""Hourly smoke test for the soak (C). Runs in the desktop session as the desktop
user; does not need the display app. Prints one JSON line:
  hyprland_pid (a change means it restarted), window (foot opens and closes),
  clipboard, file (write and read back), sound (pw-play into PipeWire),
  system_bus, desktop_mb (PSS of the long-lived desktop processes)."""
import json
import os
import shlex
import subprocess
import tempfile
import time

LONG_LIVED = {"Hyprland", "quickshell", "Xwayland", "dbus-daemon", "pipewire", "wireplumber", "pipewire-pulse",
              "fcitx5", "xdg-desktop-portal", "xdg-desktop-portal-gtk", "xdg-desktop-portal-hyprland", "udiskie"}


def sh(cmd, timeout=15):
    try:
        p = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout)
        return p.returncode, p.stdout.strip()
    except subprocess.TimeoutExpired:
        return -1, "timeout"


def clients():
    try:
        return json.loads(sh("hyprctl clients -j", 5)[1] or "[]")
    except json.JSONDecodeError:
        return []


def window():
    title = f"ohm-smoke-{os.getpid()}"
    sh(f"hyprctl eval {shlex.quote(f'hl.exec_cmd([[foot -T {title} sleep 30]])')}", 5)
    t0 = time.monotonic()
    win = None
    while time.monotonic() - t0 < 10 and not win:
        win = next((c for c in clients() if c.get("title") == title), None)
        time.sleep(0.1)
    if not win:
        return False
    os.kill(win["pid"], 15)
    for _ in range(30):
        if not any(c.get("title") == title for c in clients()):
            return True
        time.sleep(0.1)
    return False


def desktop_mb():
    total = 0
    for d in os.listdir("/proc"):
        if d.isdigit():
            try:
                if open(f"/proc/{d}/comm").read().strip() in LONG_LIVED:
                    total += sum(int(l.split()[1]) for l in open(f"/proc/{d}/smaps_rollup") if l.startswith("Pss:"))
            except (OSError, ValueError):
                pass
    return round(total / 1024, 1)


def check(fn):
    """A hung or failing check counts as failed instead of ending the run."""
    try:
        return fn()
    except Exception as e:  # noqa: BLE001
        return f"error: {e}"[:120]


def main():
    r = {"time": time.strftime("%Y-%m-%d %H:%M:%S")}
    rc, out = sh("pgrep -x Hyprland")
    r["hyprland_pid"] = int(out.split()[0]) if rc == 0 and out else None
    r["window"] = check(window) if r["hyprland_pid"] else False
    text = f"soak {time.time()}"

    def clipboard():
        subprocess.run(["wl-copy"], input=text, text=True, timeout=10)
        time.sleep(0.3)
        return sh("wl-paste --no-newline", 10)[1] == text

    r["clipboard"] = check(clipboard)
    with tempfile.NamedTemporaryFile("w+") as f:
        f.write(text)
        f.flush()
        r["file"] = open(f.name).read() == text
    wav = "/tmp/ohm-tests/smoke.wav"
    if not os.path.exists(wav):
        sh(f"ffmpeg -loglevel error -f lavfi -i sine=f=440:d=0.3 -ar 48000 {wav}", 30)
    r["sound"] = sh(f"pw-play {wav}", 15)[0] == 0
    r["system_bus"] = sh("busctl --system list --no-pager", 10)[0] == 0
    r["desktop_mb"] = desktop_mb()
    r["ok"] = all(r[k] is True for k in ("window", "clipboard", "file", "sound", "system_bus"))
    print(json.dumps(r), flush=True)


if __name__ == "__main__":
    main()
