#!/usr/bin/env python3
"""Launch every Omarchy app in the native desktop and time it.

Runs inside the Arch session as the desktop user (tests/apps/run.sh does that).
For each app: start it through Hyprland (hl.exec_cmd, so it gets the session's own
environment, as from the launcher), poll `hyprctl clients -j` / `hyprctl layers -j`
until a new mapped window (or shell panel) appears, screenshot that region with grim
and check it is not uniformly black or white, then close it and kill what it left
behind. Only processes this test started are killed: each app runs in its own
session (setsid), and cleanup takes that session and its descendants, never other
processes of the same user (builds may be running as that user).

Results go to $OUT (JSON lines), one record per app:
  id, name, exec, result (pass|slow|fail|timeout|crash|skip), seconds, frame,
  window, leftovers, log (last lines of the app's stderr/stdout)
Thresholds: pass <= 3 s, slow <= 10 s, fail beyond; timeout after 20 s.
"""
import glob
import json
import os
import shlex
import signal
import statistics
import subprocess
import sys
import time

OUT = os.environ.get("OUT", "/tmp/ohm-tests/launch.jsonl")
ONLY_FILE = os.environ.get("ONLY_FILE", "/tmp/ohm-tests/only")
_only = os.environ.get("ONLY") or (open(ONLY_FILE).read().strip() if os.path.exists(ONLY_FILE) else "")
ONLY = set(filter(None, _only.split(",")))
TIMEOUT = float(os.environ.get("APP_TIMEOUT", "20"))
PASS_S, SLOW_S = 3.0, 10.0
LOGDIR = os.path.join(os.path.dirname(OUT), "logs")

# Omarchy menu entries that only open a window or panel (from omarchy-menu.jsonc).
# Entries that change the system (power, install/remove/update, toggles, DNS, theme,
# branding, capture/recording, factory reset) are deliberately not run.
MENU_ITEMS = [
    ("menu.about", "About", "omarchy-launch-about"),
    ("menu.keybindings", "Keybindings", "omarchy-menu-keybindings"),
    ("menu.tmux-keybindings", "Tmux keybindings", "omarchy-menu-tmux-keybindings"),
    ("menu.emoji", "Emoji", "omarchy-menu-emoji"),
    ("menu.learn-omarchy", "Learn: Omarchy", "omarchy-launch-webapp 'https://omarchy.org/manual/'"),
    ("menu.learn-hyprland", "Learn: Hyprland", "omarchy-launch-webapp 'https://wiki.hypr.land/'"),
    ("menu.learn-arch", "Learn: Arch", "omarchy-launch-webapp 'https://wiki.archlinux.org/title/Main_page'"),
    ("menu.learn-neovim", "Learn: Neovim", "omarchy-launch-webapp 'https://www.lazyvim.org/keymaps'"),
    ("menu.learn-bash", "Learn: Bash", "omarchy-launch-webapp 'https://devhints.io/bash'"),
    ("menu.community", "Community", "omarchy-launch-discord-community"),
    ("menu.speedtest", "Network Speed Test", "omarchy-shell shell summon omarchy.speedtest"),
    ("menu.disk-speedtest", "Disk Speed Test", "omarchy-shell shell summon omarchy.disk-speedtest"),
    ("menu.reminders", "Reminders: show all", "omarchy-reminder show"),
    ("menu.edit-looknfeel", "Edit: look and feel", 'omarchy-launch-config-editor "$HOME/.config/hypr/looknfeel.lua"'),
    ("menu.edit-monitors", "Edit: monitors", 'omarchy-launch-config-editor "$HOME/.config/hypr/monitors.lua"'),
    ("menu.edit-bindings", "Edit: keybindings", 'omarchy-launch-config-editor "$HOME/.config/hypr/bindings.lua"'),
    ("menu.edit-input", "Edit: input", 'omarchy-launch-config-editor "$HOME/.config/hypr/input.lua"'),
    ("menu.terminal", "Terminal", "omarchy-launch-terminal"),
    ("menu.browser", "Browser", "omarchy-launch-browser"),
    ("menu.editor", "Editor", "omarchy-launch-editor"),
    ("menu.files", "Files", "omarchy-launch-nautilus"),
]
# Desktop entries that open no window by design.
NO_WINDOW = {"foot-server": "starts the foot server only"}
# Commands to use instead of the entry's own, where the entry needs an argument or
# a server to show anything (as when opened from a file or after foot --server).
OVERRIDE = {
    "imv": "imv \"$(readlink -f ~/.local/state/omarchy/current/background)\"",
    "footclient": "(foot --server &) ; sleep 0.5; footclient",
}
# Entries that cannot work on the HongMeng kernel, with the reason. Still run (so a
# change shows up), but reported as unsupported rather than failed.
UNSUPPORTED = {
    "uuctl": "manages systemd user units; there is no systemd",
    "menu.reminders": "reminders are systemd user timers; there is no systemd",
    "qvidcap": "no V4L2 camera device: HarmonyOS does not expose its camera to Linux",
}


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


def layers():
    """Set of (namespace, address) of all layer surfaces."""
    out, data = set(), hypr("layers") or {}
    for mon in data.values():
        for lvl in mon.get("levels", {}).values():
            for s in lvl:
                out.add((s.get("namespace", ""), s.get("address", "")))
    return out


def own_pids(marker):
    """The app's processes: the session the launch wrapper started (its pid is in
    `marker`) and everything descended from it."""
    try:
        root = int(open(marker).read())
    except (OSError, ValueError):
        return []
    parent, session = {}, {}
    for d in os.listdir("/proc"):
        if not d.isdigit():
            continue
        try:
            stat = open(f"/proc/{d}/stat").read()
        except OSError:
            continue
        fields = stat[stat.rindex(")") + 2:].split()
        parent[int(d)], session[int(d)] = int(fields[1]), int(fields[3])
    ours = {p for p, sid in session.items() if sid == root}
    for p in parent:
        q, seen = p, 0
        while q > 1 and seen < 64:
            if q == root or q in ours:
                ours.add(p)
                break
            q, seen = parent.get(q, 0), seen + 1
    ours.discard(os.getpid())
    return sorted(ours)


def desktop_entries():
    rows, seen = [], set()
    files = sorted(glob.glob(os.path.expanduser("~/.local/share/applications/*.desktop"))) + \
        sorted(glob.glob("/usr/share/applications/*.desktop"))
    for f in files:
        d = {}
        with open(f, errors="ignore") as fh:
            section = None
            for line in fh:
                line = line.rstrip("\n")
                if line.startswith("["):
                    section = line
                    continue
                if section == "[Desktop Entry]" and "=" in line and not line.startswith("#"):
                    k, v = line.split("=", 1)
                    d.setdefault(k, v)
        if d.get("Type") != "Application" or d.get("NoDisplay", "").lower() == "true" \
                or d.get("Hidden", "").lower() == "true" or not d.get("Exec"):
            continue
        app_id = os.path.basename(f)[:-8]
        if app_id in seen:  # the user's copy overrides the system one
            continue
        seen.add(app_id)
        args = [a for a in shlex.split(d["Exec"]) if not (len(a) == 2 and a[0] == "%")]
        cmd = shlex.join(args)
        if d.get("Terminal", "").lower() == "true":
            cmd = "xdg-terminal-exec " + cmd
        rows.append((app_id, d.get("Name", app_id), cmd))
    return rows


def frame_check(win):
    """'ok', 'black', 'white' or 'n/a' for the window's region on screen."""
    x, y = win["at"]
    w, h = win["size"]
    if w < 8 or h < 8:
        return "n/a"
    ppm = "/tmp/ohm-frame.ppm"
    sh(f"grim -t ppm -g '{x},{y} {w}x{h}' {ppm}", 10)
    try:
        data = open(ppm, "rb").read()
    except OSError:
        return "n/a"
    parts = data.split(b"\n", 3)
    px = parts[3][:: max(3, (len(parts[3]) // 20000) * 3)]
    mean, dev = sum(px) / len(px), statistics.pstdev(px)
    if dev < 4 and mean < 12:
        return "black"
    if dev < 4 and mean > 243:
        return "white"
    return "ok"


def close(new_clients, new_pids):
    # Close the windows the way a user does (Hyprland's close, as SUPER+W): a
    # signal makes some apps count a crash (Firefox then offers Troubleshoot Mode
    # at its next start). Signals only for what is still there after that.
    # (by address: without input yet, focusing a window does not take, so a plain
    # close would hit nothing)
    for c in new_clients:
        sh(f"hyprctl eval {shlex.quote('hl.dispatch(hl.dsp.window.close({ window = \"address:' + c['address'] + '\" }))')}", 5)
    for _ in range(30):
        open_now = {c["address"] for c in hypr("clients") or []}
        if not any(c["address"] in open_now for c in new_clients):
            break
        time.sleep(0.1)
    open_now = {c["address"] for c in hypr("clients") or []}
    for c in new_clients:
        if c["address"] not in open_now:
            continue
        try:
            os.kill(c["pid"], signal.SIGTERM)
        except (ProcessLookupError, PermissionError):
            pass
    # an app may take a while to shut down after its last window (Firefox writes its
    # session): give it up to 5 s before signalling what is left
    for _ in range(50):
        if not any(os.path.exists(f"/proc/{p}") for p in new_pids):
            break
        time.sleep(0.1)
    left = [p for p in new_pids if os.path.exists(f"/proc/{p}")]
    for p in left:
        try:
            os.kill(p, signal.SIGTERM)
        except (ProcessLookupError, PermissionError):
            pass
    time.sleep(1)
    still = [p for p in left if os.path.exists(f"/proc/{p}")]
    for p in still:
        try:
            os.kill(p, signal.SIGKILL)
        except (ProcessLookupError, PermissionError):
            pass
    return len(still)


def run_one(app_id, name, cmd):
    cmd = OVERRIDE.get(app_id, cmd)
    rec = dict(id=app_id, name=name, exec=cmd, result=None, seconds=None, frame=None, window=None,
               leftovers=0, log="")
    if app_id in NO_WINDOW:
        rec.update(result="skip", log=NO_WINDOW[app_id])
        return rec
    log = os.path.join(LOGDIR, app_id.replace("/", "_") + ".log")
    base_clients = {c["address"] for c in hypr("clients") or []}
    base_layers = layers()
    marker = log + ".pid"
    try:
        os.remove(marker)
    except OSError:
        pass
    wrapped = f"echo $$ > {marker}; exec sh -c {shlex.quote(cmd)}"
    lua = f'hl.exec_cmd([[setsid sh -c {shlex.quote(wrapped)} > {log} 2>&1]])'
    t0 = time.monotonic()
    sh(f"hyprctl eval {shlex.quote(lua)}", 5)
    found = None
    while time.monotonic() - t0 < TIMEOUT:
        clients = [c for c in hypr("clients") or [] if c["address"] not in base_clients and c.get("mapped")]
        if clients:
            found = ("window", clients)
            break
        new_layers = [l for l in layers() - base_layers if l[0] not in ("", "hyprpicker")]
        if new_layers:
            found = ("panel", new_layers)
            break
        time.sleep(0.1)
    elapsed = time.monotonic() - t0
    new_pids = own_pids(marker)
    if found is None:
        alive = [p for p in new_pids if os.path.exists(f"/proc/{p}")]
        rec["result"] = "timeout" if alive else "crash"
    else:
        rec["seconds"] = round(elapsed, 2)
        rec["result"] = "pass" if elapsed <= PASS_S else "slow" if elapsed <= SLOW_S else "fail"
        if found[0] == "window":
            win = found[1][0]
            rec["window"] = f'{win["class"]} | {win["title"][:60]}'
            time.sleep(1.5)
            win = next((c for c in hypr("clients") or [] if c["address"] == win["address"]), win)
            rec["frame"] = frame_check(win)
            if rec["frame"] in ("black", "white") and rec["result"] == "pass":
                rec["result"] = "fail"
        else:
            rec["window"] = "panel: " + ", ".join(sorted({l[0] for l in found[1]}))
            rec["frame"] = "n/a"
    clients = [c for c in hypr("clients") or [] if c["address"] not in base_clients]
    if found and found[0] == "panel":
        # the Omarchy shell names a panel's layer omarchy-NAME and mostly hides it as
        # omarchy.NAME; not always (the speed tests' layers are omarchy-network-speedtest
        # and so on), so those are named too
        sh("omarchy-menu close; omarchy-shell -q shell hide omarchy.speedtest; "
           "omarchy-shell -q shell hide omarchy.disk-speedtest; pkill -u $(id -u) -x omasnap", 5)
        for ns in sorted({l[0] for l in layers() - base_layers}):
            if ns.startswith("omarchy-"):
                sh(f"omarchy-shell -q shell hide omarchy.{ns[len('omarchy-'):]}", 5)
        time.sleep(0.5)
        if any(l[0] not in ("", "hyprpicker") for l in layers() - base_layers):
            rec["leftovers"] += 1
    rec["leftovers"] += close(clients, own_pids(marker))
    try:
        rec["log"] = "".join(open(log, errors="ignore").readlines()[-6:])[-600:]
    except OSError:
        pass
    if app_id in UNSUPPORTED and rec["result"] != "pass":
        rec["result"] = "unsupported"
        rec["reason"] = UNSUPPORTED[app_id]
    return rec


def main():
    os.makedirs(LOGDIR, exist_ok=True)
    items = desktop_entries() + MENU_ITEMS
    if ONLY:
        items = [i for i in items if i[0] in ONLY]
    print(f"{len(items)} apps", flush=True)
    with open(OUT, "w") as out:
        for app_id, name, cmd in items:
            rec = run_one(app_id, name, cmd)
            out.write(json.dumps(rec, ensure_ascii=False) + "\n")
            out.flush()
            print(f'{rec["result"]:8} {rec["seconds"] or "-":>6} {rec["frame"] or "-":6} {app_id}', flush=True)
            time.sleep(1)


if __name__ == "__main__":
    sys.exit(main())
