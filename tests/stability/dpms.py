#!/usr/bin/env python3
"""Display off and on, ROUNDS times (C), on Hyprland's side: DPMS off, wait, DPMS on,
then check that Hyprland is the same process, the output reports DPMS on, a window
opened afterwards maps and renders (grim sees a non-uniform frame), and the window
list is as before. Runs in the desktop session as the desktop user
(tests/lib/session-py.sh). HarmonyOS's own screen off needs someone at the machine.
  argument or ROUNDS: rounds (default 20)"""
import json
import os
import shlex
import subprocess
import sys
import time

ROUNDS = int(sys.argv[1] if len(sys.argv) > 1 else os.environ.get("ROUNDS", "20"))
OUT = os.environ.get("OUT", "/tmp/ohm-tests/dpms.jsonl")


def sh(cmd, timeout=10):
    try:
        return subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout).stdout
    except subprocess.TimeoutExpired:
        return ""


def hypr(what):
    try:
        return json.loads(sh(f"hyprctl {what} -j", 5) or "null")
    except json.JSONDecodeError:
        return None


def dpms(action):
    sh(f"hyprctl eval {shlex.quote(f'hl.dispatch(hl.dsp.dpms({{ action = \"{action}\" }}))')}", 5)


def frame_ok(win):
    x, y = win["at"]
    w, h = win["size"]
    png = "/tmp/ohm-tests/dpms.ppm"
    sh(f"grim -t ppm -g '{x},{y} {w}x{h}' {png}", 10)
    try:
        data = open(png, "rb").read()
    except OSError:
        return False
    px = data[-w * h * 3:]
    return len(set(px[i:i + 3] for i in range(0, len(px), 3 * 97))) > 1


def main():
    pid = sh("pgrep -x Hyprland").split()
    base = sorted(c["address"] for c in hypr("clients") or [])
    ok = 0
    with open(OUT, "w") as out:
        for i in range(ROUNDS):
            dpms("off")
            time.sleep(2)
            off = [m.get("dpmsStatus") for m in hypr("monitors") or []]
            dpms("on")
            time.sleep(1)
            on = [m.get("dpmsStatus") for m in hypr("monitors") or []]
            title = f"ohm-dpms-{i}"
            sh(f"hyprctl eval {shlex.quote(f'hl.exec_cmd([[foot -T {title} sleep 20]])')}", 5)
            win = None
            for _ in range(50):
                win = next((c for c in hypr("clients") or [] if c.get("title") == title), None)
                if win:
                    break
                time.sleep(0.1)
            time.sleep(0.8)
            frame = frame_ok(win) if win else False
            if win:
                os.kill(win["pid"], 15)
                time.sleep(0.5)
            same = sh("pgrep -x Hyprland").split() == pid
            clients = sorted(c["address"] for c in hypr("clients") or [])
            r = dict(round=i + 1, off=off, on=on, window=bool(win), frame=frame, hyprland_same=same,
                     clients_same=clients == base)
            r["ok"] = all([off and not any(off), on and all(on), win, frame, same, clients == base])
            ok += r["ok"]
            out.write(json.dumps(r) + "\n")
            print(f"round {i + 1}: {'ok' if r['ok'] else r}", flush=True)
    print(f"summary {ok} of {ROUNDS} rounds ok", flush=True)


if __name__ == "__main__":
    main()
