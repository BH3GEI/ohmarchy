#!/usr/bin/env python3
"""Idle CPU and memory of the desktop's processes inside the Arch session (run as
root in the session by tests/perf/idle.sh). Counts only the desktop: everything
under start-hyprland, the session and system buses with what they started, the
sound daemons, the input method; never other work in the session (builds, shells).
Prints one JSON object."""
import json
import os
import sys
import time

SECONDS = float(sys.argv[1]) if len(sys.argv) > 1 else 30
ROOTS = {"start-hyprland", "dbus-daemon", "pipewire", "wireplumber", "pipewire-pulse", "fcitx5"}
HZ = os.sysconf("SC_CLK_TCK")


def procs():
    out = {}
    for d in os.listdir("/proc"):
        if not d.isdigit():
            continue
        try:
            stat = open(f"/proc/{d}/stat").read()
            comm = stat[stat.index("(") + 1:stat.rindex(")")]
            f = stat[stat.rindex(")") + 2:].split()
            out[int(d)] = dict(comm=comm, ppid=int(f[1]), ticks=int(f[11]) + int(f[12]))
        except (OSError, ValueError):
            pass
    return out


def desktop(ps):
    roots = {p for p, i in ps.items() if i["comm"] in ROOTS}
    mine = set()
    for p in ps:
        q, n = p, 0
        while q in ps and n < 64:
            if q in roots:
                mine.add(p)
                break
            q, n = ps[q]["ppid"], n + 1
    return mine


def pss_kb(pid):
    try:
        for line in open(f"/proc/{pid}/smaps_rollup"):
            if line.startswith("Pss:"):
                return int(line.split()[1])
    except OSError:
        pass
    try:  # no smaps_rollup: resident set
        return int(open(f"/proc/{pid}/statm").read().split()[1]) * os.sysconf("SC_PAGE_SIZE") // 1024
    except OSError:
        return 0


a = procs()
mine = desktop(a)
t0 = time.monotonic()
time.sleep(SECONDS)
b = procs()
dt = time.monotonic() - t0
cpu = {}
for p in mine & set(b):
    used = (b[p]["ticks"] - a[p]["ticks"]) / HZ / dt * 100
    cpu[b[p]["comm"]] = cpu.get(b[p]["comm"], 0) + used
mem = {}
for p in mine & set(b):
    mem[b[p]["comm"]] = mem.get(b[p]["comm"], 0) + pss_kb(p)
print(json.dumps(dict(seconds=round(dt, 1), processes=len(mine & set(b)),
                      cpu_percent=round(sum(cpu.values()), 2), memory_mb=round(sum(mem.values()) / 1024, 1),
                      top_cpu=sorted(((k, round(v, 2)) for k, v in cpu.items()), key=lambda x: -x[1])[:6],
                      top_memory_mb=sorted(((k, round(v / 1024, 1)) for k, v in mem.items()), key=lambda x: -x[1])[:6])))
