#!/usr/bin/env python3
"""Summarise a launch test result (JSON lines from launch_all.py)."""
import json
import sys

rows = [json.loads(l) for l in open(sys.argv[1]) if l.strip().startswith("{")]
by = {}
for r in rows:
    by.setdefault(r["result"], []).append(r)
print(f"{len(rows)} apps: " + ", ".join(f"{k} {len(v)}" for k, v in sorted(by.items())))
timed = sorted((r for r in rows if r["seconds"] is not None), key=lambda r: r["seconds"])
if timed:
    p95 = timed[min(len(timed) - 1, int(0.95 * len(timed)))]["seconds"]
    print(f"launch time: median {timed[len(timed) // 2]['seconds']} s, P95 {p95} s")
    print("slowest: " + ", ".join(f"{r['id']} {r['seconds']} s" for r in timed[-3:][::-1]))
for k in ("slow", "fail", "timeout", "crash"):
    for r in by.get(k, []):
        last = r["log"].strip().splitlines()[-1] if r.get("log") else ""
        print(f"{k:8} {r['id']}: {r['seconds']} s, frame {r['frame']}, {r['window']}, log: {last[:160]}")
