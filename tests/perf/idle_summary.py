#!/usr/bin/env python3
"""Summarise tests/perf/idle.sh's raw output (stdin)."""
import json
import sys

t = sys.stdin.read()
try:
    s = json.loads(t.split("=== SESSION")[1].split("=== HOST")[0])
    h = json.loads(t.split("=== HOST")[1])
except (IndexError, ValueError):
    print(t[-1500:])
    sys.exit(1)
print(f"desktop in the session: {s['processes']} processes, CPU {s['cpu_percent']} %, memory (PSS) {s['memory_mb']} MB")
print("  CPU:", ", ".join(f"{k} {v}" for k, v in s["top_cpu"]),
      "| memory MB:", ", ".join(f"{k} {v}" for k, v in s["top_memory_mb"]))
print(f"host side (display app, GPU server): {h['processes']} processes, CPU {h['cpu_percent']} %, memory (PSS) {h['memory_mb']} MB")
print(f"total: CPU {s['cpu_percent'] + h['cpu_percent']:.1f} % of one core, memory {s['memory_mb'] + h['memory_mb']:.0f} MB")
print("=== JSON")
print(json.dumps(dict(session=s, host=h)))
