#!/usr/bin/env python3
"""Comparison run on a desktop: open the route L page (served by serve.py) in a
fresh headless Chrome, boot, run routel-bench by itself, print the ROUTEL lines.
Usage: desktop-run.py [url] [timeout_s] [extra chrome args...]"""
import sys, time
from playwright.sync_api import sync_playwright
url = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8086/index.html?autobench=1"
limit = float(sys.argv[2]) if len(sys.argv) > 2 else 900
done = False
def on_console(m):
    global done
    t = m.text
    if t.startswith("ROUTEL"):
        print(t, flush=True)
        if "mark bench_done" in t or "fatal" in t:
            done = True
with sync_playwright() as p:
    b = p.chromium.launch(channel="chrome", headless=True, args=sys.argv[3:])
    pg = b.new_page(viewport={"width": 1280, "height": 800})
    pg.on("console", on_console)
    pg.goto(url)
    t0 = time.time()
    while not done and time.time() - t0 < limit:
        pg.wait_for_timeout(1000)
    pg.wait_for_timeout(1500)
    pg.screenshot(path="/tmp/routel-desktop.png")
    b.close()
