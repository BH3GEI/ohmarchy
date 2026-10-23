#!/usr/bin/env python3
"""Drive the HarmonyOS emulator's UI by visible text (uitest dumpLayout), over hdc.

usage: ui.py tap TEXT [--nth N] [--timeout S] [--prefix|--contains]   wait for TEXT, tap its center
       ui.py wait TEXT [--timeout S] [--prefix|--contains]            wait until TEXT is on screen
       ui.py has TEXT [--prefix|--contains]                           exit 0 if TEXT is on screen now
       ui.py texts                                         list visible texts with bounds
       ui.py tapxy X Y | key CODE | type X Y STR           raw input (device pixels)

Matching is on the whole text unless --prefix or --contains (buttons such as
"🖥️ 普通启动 (VNC)" carry an emoji). --nth picks among several matches
in screen order (top to bottom, left to right), 0-based; negative counts from
the end. Only hdc targets 127.0.0.1:* (the emulator) are used.
"""
import argparse, json, os, re, subprocess, sys, tempfile, time

HDC = os.environ.get('HDC', 'hdc')


def target():
    out = subprocess.run([HDC, 'list', 'targets'], capture_output=True, text=True).stdout
    for line in out.split():
        if line.startswith('127.0.0.1:'):
            return line
    sys.exit('emulator not connected to hdc')


T = None


def hdc(*args):
    return subprocess.run([HDC, '-t', T, *args], capture_output=True, text=True).stdout


def texts():
    hdc('shell', 'uitest dumpLayout -p /data/local/tmp/ui.json')
    with tempfile.TemporaryDirectory() as d:
        p = os.path.join(d, 'ui.json')
        hdc('file', 'recv', '/data/local/tmp/ui.json', p)
        try:
            root = json.load(open(p))
        except (OSError, ValueError):
            return []
    found = []

    def walk(n):
        a = n.get('attributes', {})
        t = (a.get('text') or '').strip()
        m = re.match(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', a.get('bounds', ''))
        if t and m:
            x1, y1, x2, y2 = map(int, m.groups())
            if x2 > x1 and y2 > y1:
                found.append((t, (x1 + x2) // 2, (y1 + y2) // 2))
        for c in n.get('children', []):
            walk(c)
    walk(root)
    found.sort(key=lambda f: (f[2], f[1]))
    return found


def find(text, mode, timeout):
    match = {'exact': lambda t: t == text, 'prefix': lambda t: t.startswith(text),
             'contains': lambda t: text in t}[mode]
    end = time.time() + timeout
    while True:
        hits = [f for f in texts() if match(f[0])]
        if hits or time.time() >= end:
            return hits
        time.sleep(1)


def main():
    global T
    ap = argparse.ArgumentParser(usage=__doc__.split('\n\n')[1])
    ap.add_argument('cmd')
    ap.add_argument('args', nargs='*')
    ap.add_argument('--nth', type=int, default=0)
    ap.add_argument('--timeout', type=float, default=20)
    ap.add_argument('--prefix', action='store_true')
    ap.add_argument('--contains', action='store_true')
    o = ap.parse_args()
    T = target()
    if o.cmd == 'texts':
        for t, x, y in texts():
            print(f'{x:5d} {y:5d}  {t}')
    elif o.cmd in ('tap', 'wait', 'has'):
        mode = 'contains' if o.contains else 'prefix' if o.prefix else 'exact'
        hits = find(o.args[0], mode, 0 if o.cmd == 'has' else o.timeout)
        if not hits:
            if o.cmd == 'has':
                sys.exit(1)
            sys.exit(f'not on screen after {o.timeout:.0f}s: {o.args[0]!r}')
        if o.cmd == 'tap':
            _, x, y = hits[o.nth]
            hdc('shell', f'uitest uiInput click {x} {y}')
    elif o.cmd == 'tapxy':
        hdc('shell', f'uitest uiInput click {o.args[0]} {o.args[1]}')
    elif o.cmd == 'key':
        hdc('shell', f'uitest uiInput keyEvent {o.args[0]}')
    elif o.cmd == 'type':
        hdc('shell', f'uitest uiInput inputText {o.args[0]} {o.args[1]} {o.args[2]}')
    else:
        sys.exit(__doc__)


if __name__ == '__main__':
    main()
