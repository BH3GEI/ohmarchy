#!/usr/bin/env python3
"""Open and close apps ROUNDS times (C): each round opens the next app of APPS
through Hyprland, waits for its window, closes it, and checks nothing of it is left.
Memory of the desktop's long-lived processes (Hyprland, the Omarchy shell, the
buses, sound, input method; PSS) is sampled before and after, and every 10 rounds.
Runs in the desktop session as the desktop user (tests/lib/session-py.sh). Only the
processes it started are ever killed. Prints a summary line; JSON lines go to $OUT.
  argument or ROUNDS: rounds (default 100)
"""
import json
import os
import shlex
import signal
import subprocess
import sys
import time

ROUNDS = int(sys.argv[1] if len(sys.argv) > 1 else os.environ.get("ROUNDS", "100"))
OUT = os.environ.get("OUT", "/tmp/ohm-tests/openclose.jsonl")
LOGDIR = "/tmp/ohm-tests/openclose"
# Installed Omarchy apps of different toolkits: foot, GTK 4 (Nautilus, Disks),
# GTK 3 (Evince, Pinta), imv, Flutter (LocalSend). Nautilus stays resident after its
# window closes, by design; that shows as a leftover that exits on SIGTERM.
APPS = ["foot -T ohm-oc", "nautilus --new-window", "evince", "gnome-disks", "imv "
        + shlex.quote(os.path.realpath(os.path.expanduser("~/.local/state/omarchy/current/background"))),
        "pinta", "localsend"]
LONG_LIVED = {"Hyprland", "quickshell", "Xwayland", "dbus-daemon", "pipewire", "wireplumber", "pipewire-pulse",
              "fcitx5", "xdg-desktop-portal", "xdg-desktop-portal-gtk", "xdg-desktop-portal-hyprland",
              "udiskie", "gvfsd", "at-spi-bus-launcher"}


def sh(cmd, timeout=10):
    try:
        return subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout).stdout
    except subprocess.TimeoutExpired:
        return ""


def clients():
    try:
        return json.loads(sh("hyprctl clients -j", 5) or "[]")
    except json.JSONDecodeError:
        return []


def procs():
    out = {}
    for d in os.listdir("/proc"):
        if d.isdigit():
            try:
                stat = open(f"/proc/{d}/stat").read()
                f = stat[stat.rindex(")") + 2:].split()
                out[int(d)] = (stat[stat.index("(") + 1:stat.rindex(")")], int(f[1]), int(f[3]))
            except (OSError, ValueError):
                pass
    return out


def own_pids(marker):
    try:
        root = int(open(marker).read())
    except (OSError, ValueError):
        return []
    ps = procs()
    ours = {p for p, (_, _, sid) in ps.items() if sid == root}
    for p in ps:
        q, n = p, 0
        while q in ps and q > 1 and n < 64:
            if q == root or q in ours:
                ours.add(p)
                break
            q, n = ps[q][1], n + 1
    ours.discard(os.getpid())
    return sorted(ours)


def desktop_pss_mb():
    total = 0
    for p, (comm, _, _) in procs().items():
        if comm in LONG_LIVED:
            try:
                for line in open(f"/proc/{p}/smaps_rollup"):
                    if line.startswith("Pss:"):
                        total += int(line.split()[1])
            except OSError:
                pass
    return round(total / 1024, 1)


def kill(pids, sig):
    for p in pids:
        try:
            os.kill(p, sig)
        except (ProcessLookupError, PermissionError):
            pass


def one(i, cmd):
    log = os.path.join(LOGDIR, f"{i}.log")
    marker = log + ".pid"
    base = {c["address"] for c in clients()}
    wrapped = f"echo $$ > {marker}; exec sh -c {shlex.quote(cmd)}"
    t0 = time.monotonic()
    sh(f"hyprctl eval {shlex.quote(f'hl.exec_cmd([[setsid sh -c {shlex.quote(wrapped)} > {log} 2>&1]])')}", 5)
    win = None
    while time.monotonic() - t0 < 20 and win is None:
        win = next((c for c in clients() if c["address"] not in base and c.get("mapped")), None)
        time.sleep(0.1)
    opened = round(time.monotonic() - t0, 2) if win else None
    time.sleep(0.5)
    # close the way a user does (the window's close), then make sure
    if win:
        focus = 'hl.dispatch(hl.dsp.focus({ window = "address:' + win["address"] + '" }))'
        sh(f"hyprctl eval {shlex.quote(focus)}", 5)
        sh(f"hyprctl eval {shlex.quote('hl.dispatch(hl.dsp.window.close())')}", 5)
    for _ in range(30):
        if not any(c["address"] == (win or {}).get("address") for c in clients()) and not own_pids(marker):
            break
        time.sleep(0.1)
    left = own_pids(marker)
    kill(left, signal.SIGTERM)
    time.sleep(0.5)
    still = own_pids(marker)
    kill(still, signal.SIGKILL)
    return dict(round=i, app=cmd.split()[0], opened=opened, leftover_after_close=len(left), killed=len(still))


def main():
    os.makedirs(LOGDIR, exist_ok=True)
    mem0 = desktop_pss_mb()
    worst, fails, leftovers, mems = 0, 0, 0, [mem0]
    with open(OUT, "w") as out:
        for i in range(ROUNDS):
            r = one(i, APPS[i % len(APPS)])
            fails += r["opened"] is None
            leftovers += r["leftover_after_close"] > 0
            if r["opened"]:
                worst = max(worst, r["opened"])
            if (i + 1) % 10 == 0:
                time.sleep(2)
                r["desktop_mb"] = desktop_pss_mb()
                mems.append(r["desktop_mb"])
                print(f"round {i + 1}: desktop {r['desktop_mb']} MB", flush=True)
            out.write(json.dumps(r) + "\n")
    time.sleep(5)
    mem1 = desktop_pss_mb()
    growth = (mem1 - mem0) / mem0 * 100 if mem0 else 0
    summary = dict(rounds=ROUNDS, no_window=fails, rounds_with_leftovers=leftovers, slowest_open_s=worst,
                   desktop_mb_before=mem0, desktop_mb_after=mem1, growth_percent=round(growth, 1))
    print("summary", json.dumps(summary), flush=True)
    with open(OUT, "a") as out:
        out.write(json.dumps(dict(summary=summary)) + "\n")


if __name__ == "__main__":
    main()
