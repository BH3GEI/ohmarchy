# Route D acceptance: Omarchy natively on HarmonyOS

What "usable" means for the native desktop ([native-desktop.md](native-desktop.md)),
how each part is tested, and the latest results. Every test is a script under
`tests/`; `tests/run-all.sh` runs them all and prints one table. Scripts take the
host and paths from the environment (`OHOS_HOST`, default `ohdev`; `ARCH_BASE`,
default `/data/local/archtest`; `ARCH_USER`, default `builder`), so they are not
tied to one machine.

Test machine: HUAWEI HM740 (Kirin X90, 20 threads, 32 GB), HarmonyOS 7.0
(HongMeng kernel 1.11.13.0).

## Summary (2026-10-24 21:45)

| Item | Status | What | Evidence |
|---|---|---|---|
| A1 every app opens in 3 s | pass | 73 of 78 pass, 0 failed, 4 unsupported (no camera, no systemd, no container runtime), 1 skip (foot-server); P95 1.22 s | [73ce712](https://github.com/BH3GEI/ohmarchy/commit/73ce712), [3735447](https://github.com/BH3GEI/ohmarchy/commit/3735447) |
| A2 core operations | pass | files (LibreOffice, Neovim), clipboard, Chinese input, sound, file chooser: 6 of 6 | [83432cf](https://github.com/BH3GEI/ohmarchy/commit/83432cf), [5bfbae5](https://github.com/BH3GEI/ohmarchy/commit/5bfbae5) |
| A3 sound | pass, plus on site | over the app-only socket (23:45): first sound median 101 ms (max 133), during playback median 72 ms (max 77); A/V within 100 ms; not yet heard by ear (host volume 0) | [5bfbae5](https://github.com/BH3GEI/ohmarchy/commit/5bfbae5), [e1605aa](https://github.com/BH3GEI/ohmarchy/commit/e1605aa) |
| B cold start <= 10 s | pass | about 8 s (session 2.0 s + desktop 5.7-6.1 s) | [68e71a7](https://github.com/BH3GEI/ohmarchy/commit/68e71a7) |
| B app launch P95 <= 3 s | pass | 1.22 s | [73ce712](https://github.com/BH3GEI/ohmarchy/commit/73ce712) |
| B workspace switch >= 110 fps | pass | 119.4 fps | [2a4852d](https://github.com/BH3GEI/ohmarchy/commit/2a4852d) |
| B idle memory/CPU | recorded | desktop 0.5 % of a core, display app 1.9 %, 1.0 GB | [2a4852d](https://github.com/BH3GEI/ohmarchy/commit/2a4852d), [c5c680f](https://github.com/BH3GEI/ohmarchy/commit/c5c680f) |
| B power | proxy done, on site | idle costs nothing over baseline; es2gears same CPU as in the VM at twice the frame rate. Battery drain needs a run on battery | [2a4852d](https://github.com/BH3GEI/ohmarchy/commit/2a4852d) |
| C open/close 100 times | pass | 100 of 100, memory +0.1 % | [3461eb8](https://github.com/BH3GEI/ohmarchy/commit/3461eb8) |
| C 24 h soak | running | hourly smoke since 17:52, ends 2026-10-25 17:52 | [7c6dec5](https://github.com/BH3GEI/ohmarchy/commit/7c6dec5) |
| C display off/on, app background/foreground | pass | DPMS 20 of 20; app to background and back 20 of 20 | [4a3c1f8](https://github.com/BH3GEI/ohmarchy/commit/4a3c1f8), [2a4852d](https://github.com/BH3GEI/ohmarchy/commit/2a4852d) |
| C network loss | pass, plus on site | site and DNS outages: back within 0.1 s; a real Wi-Fi switch needs someone at the machine | [0fb8873](https://github.com/BH3GEI/ohmarchy/commit/0fb8873) |
| C HarmonyOS screen off | on site | the only remote switch suspends the whole machine | (checklist below) |
| D reset, upgrade check, logs | pass | fresh install about 30 min; reset 56 s; `check-upgrade.sh`; log bundle | [e090e8e](https://github.com/BH3GEI/ohmarchy/commit/e090e8e), [b569eec](https://github.com/BH3GEI/ohmarchy/commit/b569eec) |
| E security | pass with open items | ordinary user, sudo with password, no TCP ports, GPU and sound sockets only for the app's uid, Firefox sandboxed. Open: Chromium itself (started by hand) without sandbox; `su` SELinux domain | [3461eb8](https://github.com/BH3GEI/ohmarchy/commit/3461eb8), [e1605aa](https://github.com/BH3GEI/ohmarchy/commit/e1605aa), [8f7acc9](https://github.com/BH3GEI/ohmarchy/commit/8f7acc9), [f1636a5](https://github.com/BH3GEI/ohmarchy/commit/f1636a5) |
| F one-command regression | pass | `tests/run-all.sh` | [6e5d491](https://github.com/BH3GEI/ohmarchy/commit/6e5d491) |
| G other devices | open | one machine so far; tests take host, path and user from the environment | |

Not claimed: "100 % usable". Each line above is what the named test measured on
this machine; what needs a person at the machine is listed at the end.

Detail by area:

| Area | Criterion | Test | Status |
|---|---|---|---|
| A. Compatibility | every Omarchy app opens a window within 3 s; core operations work | `tests/apps/run.sh` | A1: 73 of 78 open within 3 s (P95 1.2 s), 4 unsupported, 0 failed (with the system D-Bus). A2: 6 of 6 core operations pass (sound not yet heard by ear: to confirm on site). Sound: 75-104 ms to the speaker (median), A/V within 100 ms; not yet heard (host volume 0) |
| B. Performance | cold start to desktop <= 10 s; app launch P95 <= 3 s; workspace switch >= 110 fps; idle memory/CPU recorded; power vs the HarmonyOS desktop | `tests/perf/` | cold start about 8 s (session 2.0 s + desktop 5.7-6.1 s), launch P95 1.2 s, workspace switch 119 fps, idle: the app 1.9 % of a core, the desktop 0.5 %, 1.0 GB; power proxy: idle native desktop costs nothing over baseline, es2gears the same CPU as in the VM at twice the frame rate. Battery drain: needs a run on battery |
| C. Stability | 100 open/close rounds without leftovers and < 5 % memory growth; 24 h soak with hourly smoke test; 20 screen off/on cycles; network loss and Wi-Fi change | `tests/stability/` | 100 rounds: all opened, +0.1 % memory, nothing hung. Network outage and DNS outage: recover within 0.1 s. Soak running since 17:52. Display off/on on Hyprland's side (DPMS): 20 of 20. App to background and back: 20 of 20. HarmonyOS screen off: needs someone on site, as does a real Wi-Fi switch |
| D. Upgrade and recovery | one-command reset to a clean environment; regression after `pacman -Syu`; log bundle | `native/install.sh`, `reset.sh`, `check-upgrade.sh`, `collect-logs.sh` | fresh install from nothing in a second environment: about 30 min; reset to the clean image: 56 s; `-Syu` check: tool works, nothing to upgrade yet (a regression run needs time to pass); log bundle: done |
| E. Security | desktop and apps as an ordinary user; `su` context only where needed; browser sandbox | `tests/security/check.sh` | desktop as an ordinary user, sudo needs a password, no listening ports, sound and GPU sockets only for the display app's uid, default browser and web apps in Firefox (sandboxed): pass. Open: Chromium itself (when started by hand) without sandbox; broker and session init in the `su` SELinux domain |
| F. Regression | `tests/run-all.sh`, one table | `tests/run-all.sh` | done: runs A1, A2, A3, B, C1, E and prints one table (PASS/FAIL/SKIP/INFO); screen tests skip while the screen is someone else's |
| G. Other devices | | | only one machine so far. The tests take the host, base path and user from `OHOS_HOST`, `ARCH_BASE`, `ARCH_USER`; nothing else names this device |

## A. Compatibility

### A1. Every app opens

`tests/apps/run.sh` takes every visible `.desktop` entry (the user's copy wins over
the system one) and the Omarchy menu entries that only open a window or panel. It
starts each through Hyprland (`hl.exec_cmd`, so with the session's own environment,
as from the launcher), times it until a new mapped window or shell panel appears
(`hyprctl clients -j` / `hyprctl layers -j`, polled every 100 ms, 20 s timeout),
screenshots that region with grim and rejects a uniformly black or white frame,
then closes it and kills whatever it left behind.

Pass: window within 3 s and a real frame. Slow: 3-10 s. Fail: beyond 10 s, no
window, or a black/white frame.

Menu entries not run, because they change the system rather than open an app:
power (lock, suspend, hibernate, logout, reboot, shutdown), install/remove/update
of packages, browsers, services, editors, terminals, dev environments and games,
release channel, factory reset, toggles (night light, idle, touchpad, ...), DNS,
bar position, branding, theme/background/font changes, screen capture and
recording.

Results, 2026-10-24 (desktop on the host GPU path, `OHMARCHY_GPU=host`; the machine
was also compiling a kernel, load around 24, so these are upper bounds; the
official numbers are re-run when it is idle):

| | Count |
|---|---|
| Entries tested | 78 (56 desktop entries, 22 menu entries) |
| Window within 3 s, real frame | 72 (includes foot-server's skip: no window by design) |
| Slow (3-10 s) | 0 |
| Failed | 0 |
| Unsupported on the HongMeng kernel | 6 |

Launch time over all that opened: median 0.8 s, P95 1.4 s. Slowest: Fcitx 5
Configuration 1.82 s, Pinta 1.61 s, Basecamp (web app) 1.58 s.

Fixed during the run: qv4l2 (missing `qt6-5compat`) and Disk Usage (missing
`dua-cli`), both now installed by `native/40-install-desktop.sh`; imv and
footclient only failed in the test (imv shows a black canvas without a file,
footclient needs `foot --server`), which now opens them that way.

Re-run 2026-10-24 16:20 after the system D-Bus was added (`ohmarchy-sysbus`,
started with the desktop; load still around 21 from a kernel build): 73 pass, 1
skip (foot-server), 4 unsupported, 0 failed; median 0.67 s, P95 1.22 s. Nothing
that passed before fails now. Changes: Disks (gnome-disks) opens (udisks2 runs, and
sees no disks: the session's `/dev` has none, so it cannot change any); the Docker
entry now opens its terminal UI in 0.3 s, but there is still no Docker daemon. imv
failed once because the test opened the theme background from the old
`~/.config/omarchy/current`; this Omarchy keeps it in `~/.local/state/omarchy/current`
(fixed; passes).

Unsupported, with the reason (reported as such by the test, not as failures):

| Entry | Why |
|---|---|
| Docker (daemon), menu > Docker | no container runtime: no cgroup v2 or user namespaces for dockerd |
| uuctl, menu > Reminders | systemd user units and timers; there is no systemd |
| qvidcap | no V4L2 camera: HarmonyOS does not expose its camera to Linux |

### A2. Core operations

`tests/lib/session-py.sh core tests/core/core_ops.py` runs `tests/core/core_ops.py`
in the desktop session as the desktop user. Keys are typed through the same input
socket the HarmonyOS app uses (`@ohmarchy-display`), after focusing the window and
moving the pointer onto it.

Results, 2026-10-24 (host GPU path):

| Check | What it does | Result |
|---|---|---|
| file-libreoffice | write Chinese + English text, convert to .odt with LibreOffice, convert back, compare | pass, 2.6 s |
| file-nvim | write the text from Neovim, read it back | pass, 0.1 s |
| clipboard | `wl-copy` in one client, `wl-paste` in another | pass, 0.5 s |
| chinese-input | type `nihao` + space through fcitx5 pinyin into foot, expect 你好 | pass, 4.9 s |
| audio | play a tone with pw-play, paplay, then aplay | pass, 0.6 s (PipeWire to the display app, below) |
| file-chooser | ask the desktop portal for an Open File dialog | pass, xdg-desktop-portal-gtk dialog in 1.3 s |

Re-run 16:55 with sound and the system D-Bus: all 6 pass.

LibreOffice's text export starts with a byte-order mark; the test reads it with
`utf-8-sig`. A Hyprland that has had no input yet gives a new window no keyboard
focus; the HarmonyOS app always moves the pointer first, so the test does too.

### A3. Sound

How it works: PipeWire, its Pulse server and WirePlumber start with the desktop
(`ohmarchy-desktop`). Everything plays into one sink, "HarmonyOS"
(`native/desktop/ohmarchy-audio.conf`); PipeWire's protocol-simple module streams
that sink's monitor (48 kHz, S16LE, stereo, 240-frame quantum) on
127.0.0.1:4714 to the display app, which plays it with OHAudio
(`native/app/entry/src/main/cpp/audio.cpp`): a ring of 20-80 ms, then an
`OH_AudioRenderer` in fast mode (5 ms callbacks of 240 frames; the system confirmed
fast mode). The renderer only runs while there is sound, so an idle desktop holds
no audio focus. HarmonyOS lists the stream as `com.ohmarchy.display` on
FastRendererSink (speaker), 48 kHz, no resampling.

`tests/audio/run.sh` times each beep from the moment it is handed to the Pulse
server to the moment the speaker plays it (the app reads the renderer's
timestamp; both sides use CLOCK_MONOTONIC). `tests/audio/avsync.sh` plays a video
with a white flash and a beep every second in mpv and compares when each reaches
the app. Results 2026-10-24, load around 21 (kernel build), desktop on the host
GPU path:

| | Median | Max | Target |
|---|---|---|---|
| First sound after silence (`paplay`, renderer starting) | 89-104 ms | 140 ms | <= 200 ms |
| Sound during playback (paced stream, 20 ms client buffer) | 75-80 ms | 87 ms | <= 200 ms |
| Underruns during a 10 s tone | 0 | | |
| mpv: sound minus picture | -37 ms (sound first) | -87 .. +24 ms | within 100 ms |

The same latency held after `omarchy desktop restart` (the app reconnects by
itself). After sound moved to the app-only socket (`ohmarchy-audio-relay`, 20:00) it got
slower (warm median 137 ms, one cold beep 222 ms): `pw-record` writes through
stdio, which buffers when stdout is not a terminal. Run unbuffered (`stdbuf -o0`)
the session side takes 17-37 ms; on screen at 23:45: first sound median 101 ms
(max 133), during playback median 72 ms (max 77). A/V: the picture is the slow side here (mpv on the CPU, the host GPU path,
load 21; 8 of 10 flashes made it, the rest were dropped frames); one more
HarmonyOS vsync (about 8 ms) is not counted on the picture side. To re-measure on
the in-app GPU path when the machine is idle.

Not verified yet: hearing it. HarmonyOS's media volume was 0 during the tests and
no one was at the machine, so it stays to be confirmed by ear on site. What is
verified without sound: the PCM the app hands to the renderer carries each beep
(the onset detector fires on samples above 64), and the renderer's play position
moves past those samples on the speaker sink. A capture at FastRendererSink itself
would be silent at volume 0: the gain stage (hpaeGainNode) before the sink applies
the volume. Microphone input is not done.

## B. Performance

Preliminary, 2026-10-24 17:00-17:20, while a kernel package was building in the
session (load around 21) and the screen was in use by another test line (so
nothing that shows the display app ran). Official numbers when the machine is idle.

| Criterion | Test | Result | Target |
|---|---|---|---|
| Cold start: Arch session plus desktop until the Omarchy bar and background are up | `tests/perf/coldstart.sh` (desktop, 5 rounds) and `arch.sh start` timed in the second environment (session, 3 rounds), 2026-10-24 21:20, machine quiet | session 2.0 s + desktop 5.7-6.1 s (Hyprland answers at 3.9 s, bar 4.5-4.7 s): about 8 s. Not counted: HarmonyOS's own boot and opening the app | <= 10 s |
| App launch | `tests/apps/run.sh` (A1) | median 0.67 s, P95 1.22 s | P95 <= 3 s |
| Workspace switch | `tests/perf/workspace.sh` (HarmonyOS compositor frame timestamps while switching every 0.45 s for 10 s, in-app GPU path) | 119.4 fps (2026-10-24 18:35, machine quiet) | >= 110 fps |
| Idle CPU and memory, desktop processes only | `tests/perf/idle.sh` | display app closed: 0.5 % of one core, 1.0 GB (PSS; Omarchy shell 430 MB, Hyprland 140 MB, fcitx5 67 MB). Display app open, idle: 1.9 % of one core in the app (`tests/perf/app-threads.sh`; was about 14 % before its frame-rate vote dropped to 10 Hz when nothing changes) | recorded |
| Power vs the HarmonyOS desktop | `tests/perf/power.sh` (below) | proxy only: see the table below. Battery drain needs a run on battery (on mains with a full battery it reports 0 current) | |

Found while measuring, fixed:

- `omarchy desktop start` (and restart: at boot and when the app connects) returned
  only after 12.5 s: it still waited up to 10 s for wayvnc, which is no longer
  started. It now waits for Hyprland to answer: 2.45 s.

- PipeWire sent silence to the display app all the time: 10 % of a core for
  PipeWire alone. Its forwarding stream is now passive, so the sound graph sleeps
  when nothing plays (0.03 %); the app treats a quiet socket as silence.
- With the host GPU server, every desktop restart left one server process behind
  (about 80 MB each): on HongMeng it is not told its client went away.
  `omarchy desktop stop` now ends them.

- The display app's frame callback, needed to ask for 120 Hz, ran on every vsync
  even with nothing changing: about 14 % of a core. Its vote now drops to 10 Hz after
  a second without frames and goes back up with the first new one: 1.9 %.

Power proxy, 2026-10-24 18:39-18:54, in a window with the machine to ourselves (no
builds or transfers; screen and hypervisor locks held). 60 s each, whole machine,
sampled every 0.5 s: CPU busy in % of all 20 cores. Each half measured with the
other one off (the 鸿融 VM powered off from the guest for the native runs, the
native desktop stopped for the VM runs). The CPU and GPU clocks stayed at the same
values in every state (CPU clusters 2.0-2.3 GHz, GPU 850 MHz: on mains the governors
hold them), so they do not tell the states apart; CPU time does.

| State | CPU busy | Over baseline |
|---|---|---|
| Baseline: native desktop and VM both off, HarmonyOS desktop | 7.1 % | |
| Native desktop idle, display app in front | 6.5 % | none (within noise) |
| Native, es2gears running (in-app GPU path; it shows 117-120 fps, Phase 2) | 15.5 % | +8.4 points |
| 鸿融 VM idle, its Omarchy desktop in front | 7.2 % | none (within noise) |
| 鸿融 VM, es2gears running (60 fps on screen, Phase 2) | 16.0 % | +8.9 points |

So for the same CPU the native desktop puts twice the frames on screen. HarmonyOS's
own per-app energy accounting (XpowerManager, `dubai.db` `hourly_app_energy`) does
not help here: it books only the display app's process to the app (the Linux
session's processes are root, outside any app), and flushes about every half hour.
A real power comparison needs the machine on battery.


## C. Stability

### C1. Open and close 100 times

`tests/lib/session-py.sh openclose tests/stability/openclose.py 1800 100` opens 7
installed apps in turn (foot, Nautilus, Evince, Disks, imv, Pinta, LocalSend:
foot, GTK 3/4 and Flutter) through Hyprland, closes each with Hyprland's close (as
SUPER+W does), then checks what it left. Memory is the PSS of the desktop's
long-lived processes (Hyprland, Omarchy shell, Xwayland, buses, sound, input
method, portals).

Result 2026-10-24 17:30-17:48 (load around 20): 100 of 100 opened (slowest 1.28 s);
memory 714.3 MB before, 715.2 MB after (+0.1 %; every 10 rounds within 712-715 MB);
nothing had to be killed. 15 rounds left a process after the window closed: all
Nautilus, which stays resident by design and exits on SIGTERM.

### C2. Network loss

`tests/stability/network.sh`. The session uses the host's network, and the ssh
link to the host must not drop, so the host's Wi-Fi is not touched; the outages are
narrow instead:

| Outage (30 s) | How | Result 2026-10-24 18:10 |
|---|---|---|
| One site unreachable | `ip rule ... priority 100 blackhole` for www.baidu.com's addresses only (the host routes by policy rules, so a route in the main table has no effect); removed after, and by a timer should the test die | pass: down during, back 0.1 s after |
| DNS unreachable | the session's own `/etc/resolv.conf` points to 192.0.2.1, then restored | pass: names fail during, back 0.1 s after |

Measured with curl (a new connection each time). Not done: a long-running browser
across the outage, and a real Wi-Fi switch or disconnect (needs someone at the
machine: if the host's Wi-Fi did not come back, the machine would be out of reach).

### C4. Display off and on

`tests/lib/session-py.sh dpms tests/stability/dpms.py 600 20`: Hyprland's DPMS off
for 2 s, then on; after each round a new window must map and render (grim sees a
real frame), Hyprland must be the same process and the window list unchanged.
2026-10-24 18:14: 20 of 20 rounds ok.

HarmonyOS's own screen off cannot be tested remotely: the only command-line
switch, `power-shell suspend`, suspends the whole machine, which could leave it out
of reach. Needs someone at the machine. The closest remote stand-in, sending the
display app to the background and back (HarmonyOS destroys and recreates its
surface, as at screen off): `tests/stability/bgfg.sh` brings Settings to the front,
then the display app again, makes the desktop draw and checks that new frames reach
the app's surface. 2026-10-24 18:37: 20 of 20; the app and Hyprland kept running
throughout.

### C3. Soak

`tests/stability/soak.sh start` runs `smoke.py` every hour for 24 h on the host
(detached), in the desktop session: Hyprland's pid (a change means a restart), a
window opens and closes, clipboard, file write, sound into PipeWire, system bus,
desktop memory. Started 2026-10-24 17:52; first run all ok, desktop 714 MB.
Desktop restarts by the tests themselves (cold start) are logged in the results.
Desktop stopped and started on purpose during the soak: 18:29:41/18:29:59 (switch to
the in-app GPU path), 18:47:31 (power baseline) to 18:54:27. The 18:52 run fell into that gap (no desktop: all checks false) and does not count.
The 19:52 run failed too, also my doing: after the exclusive window the desktop was
left on the in-app GPU path with the display app closed. On that path the app is
the GPU, so with it closed Hyprland waits for it and the session stalls (`wl-copy`
hung; the smoke script stopped with a timeout). Back on the host GPU path at 20:14
(as at the start of the soak), smoke all ok at 20:15. The smoke script now records
a hung check as failed instead of stopping. Further planned restarts: 19:57 and
20:02 (sound relay, broker), 20:14 (back to the host GPU path).

## D. Upgrade and recovery

A second environment, `/data/local/archtest-native`, built from nothing (not a copy
of the first) with `sh native/install.sh builder <gpu-bin-dir>` (ARCH_BASE set; all
at nice 19, beside the other work on the machine): Arch Linux ARM download and
image 19:08, Arch setup 19:11, Omarchy 19:15, sparsecp 19:28, desktop build 19:28;
done about 19:38 (one stop to fix an unset variable in the last line of
`40-install-desktop.sh`). 907 packages, 14 GB used in a 64 GB sparse image.

| | How | Result 2026-10-24 |
|---|---|---|
| Reset to clean | `sh reset.sh` on the host: stops the desktop and session, puts back `arch-clean.img` (kept by `install.sh` after installing; `reset.sh snapshot` to retake), starts the session | 56 s; a file left in the home directory was gone after, package count back to 907 |
| After `pacman -Syu` | `sh arch.sh run check-upgrade.sh`: everything in `/opt/ohmarchy` (our patched Hyprland and aquamarine) and the preloaded shims still resolves its libraries, Hyprland runs, the packaged Hyprland version our patches match | pass before and after `-Syu` in the new environment, and in the day-old first one. The new environment had nothing to upgrade yet, so the real regression run (with updates pending) is still to do; if it fails, `40-install-desktop.sh` again rebuilds against the new libraries |

`reset.sh` copies with `bin/sparsecp` (built from `native/sparsecp.c` by
`install.sh`): the host's toybox `cp` and `dd` write every byte, which would turn the
14 GB image into 64 GB.

Log bundle: `sh /data/local/archtest/collect-logs.sh [dir]` on the host writes
one `ohmarchy-logs-<time>.tar.gz` (default in /data/local/tmp): host side (session,
GPU server, boot, soak logs, the display app's hilog lines, its version, processes,
memory, crash list) and session side (desktop, Hyprland, sound logs, processes,
package versions, disk, test results). No passwords or user files.

## E. Security

`tests/security/check.sh`, 2026-10-24 17:50, updated 20:15:

| Check | Result |
|---|---|
| Desktop processes (Hyprland, Omarchy shell, Xwayland, sound, input method) run as the ordinary desktop user | pass |
| Root in the session | only udisksd and upowerd (system bus services, as on any Linux), plus whatever someone runs as root (a package build's pacman during the check) |
| Desktop user gets root without a password | pass since 17:50 (was: fail). `builder` was in `wheel` with `NOPASSWD: ALL`, which matters more here than on a normal Linux: without user namespaces root in the session is root on the HarmonyOS host (`u:r:su:s0`). Now `/etc/sudoers.d/10-wheel` asks for the password (set per internal convention); Omarchy's own narrow NOPASSWD rules (DNS, timezone, browser theme policy) sort after it and still work without one (checked with `sudo -l`). `native/40-install-desktop.sh` does this as its last step (the install itself still runs passwordless); the old sudoers are backed up in the session's `/root/sudoers-backup-*` |
| Host side | the session's init runs as root in `u:r:su:s0`. The GPU broker (default, in-app GPU path) binds its sockets as root, then handles everything as the desktop user (uid 60000); a root parent stays only to run the desktop restart when the app connects. It hands the desktop's GPU connections only to the display app's uid (SO_PEERCRED; before, any host process could have connected as "the app"; refusal of uid 0 tested). Both still in the `su` domain: a domain of its own needs SELinux policy we cannot load. The host GPU server (`OHMARCHY_GPU=host`, for tests) still runs as root |
| Listeners | pass: no TCP ports. Sound now goes over the abstract socket `@ohmarchy-audio`, served by `ohmarchy-audio-relay` only to the display app's uid (SO_PEERCRED; refusals of uid 60000 and 0 tested); the app in turn plays only from a server with the compositor's uid. Before, PipeWire's protocol-simple listened on 127.0.0.1:4714, where any host process could listen in |
| Browser sandbox | default browser: pass. Firefox is now Omarchy's default browser (`40-install-desktop.sh`): its tab, media, socket and utility processes run under seccomp-bpf (`Seccomp: 2`) with its file broker; tested headless, the page rendered. Web apps: fail: Chromium (Omarchy's web apps) runs with `--no-sandbox`. Without user namespaces it needs its setuid helper; with it the zygote starts in its own PID namespace (pid 1) but never completes its handshake. Under strace (as root, `-u` the desktop user, so the helper keeps setuid) the zygote stops on a `brk` trap (SIGTRAP, TRAP_BRKPT) early in its startup: a Chromium `CHECK` fails; which one needs symbols. Ruled out, each tested on its own: PID and network namespaces (root), chroot into `/proc/self/fdinfo` (the helper's chroot), SCM_RIGHTS and SCM_CREDENTIALS over SOCK_SEQPACKET (the pid is translated correctly across PID namespaces), `capset` dropping all capabilities, seccomp-bpf (and Chromium's seccomp policy off does not help) No debug symbols for ALARM's Chromium (debuginfod.archlinux.org: 404; ALARM has no debuginfod), so the failing check is not identified |
| seccomp-bpf | pass: the kernel takes filters (so a working setuid sandbox would get both layers) |

Open items:

- Chromium without a sandbox, when started by hand. Omarchy's web apps (Basecamp,
  HEY, WhatsApp, ...) now open in Firefox: route D's `omarchy-launch-webapp` in
  `/opt/ohmarchy/overrides`, which `ohdisplay.lua` puts ahead of Omarchy's own bin
  in the apps' PATH (Omarchy puts its bin first, so `/usr/local/bin` is not
  enough). They get Firefox's toolbar instead of Chromium's app window; all 9 open
  in 1.2-1.6 s (A1). `OHMARCHY_WEBAPP_BROWSER=chromium` restores Omarchy's
  launcher.
- The broker and the session init run in the `su` SELinux domain (all-powerful on
  the host); a narrower domain needs policy that cannot be loaded from here.

## On site: what needs someone at the machine

Everything else above runs remotely. These need a person at the HM740; each takes a
few minutes except the battery test. Commands marked "Mac" run from the
repository on the machine that drives the host (`ssh ohdev` works there); the
others are on the HM740 itself. Hold `/data/local/screen.lock` for 1-4 (tell the
other test lines first).

1. **Hear the sound** (A3). Turn the media volume up to about half. Open
   "Omarchy (native)". Mac: `tests/audio/run.sh`; you should hear ten short beeps,
   evenly spaced, no crackle. Then in the native desktop open a terminal and run
   `mpv --fs` on any video with speech; lips and voice should match. Put the volume
   back to where it was.
2. **Screen off and on** (C). With "Omarchy (native)" open and a terminal in it:
   press the power button, wait 10 s, press it again, unlock. The desktop must
   come back showing the same windows, and typing in the terminal must work.
   Do it 20 times (or let the screen time out a few of those times). Note any
   round where the window stays black or the desktop restarts (the open windows
   are gone).
3. **Wi-Fi change** (C). With a page open in Firefox in the native desktop: turn
   Wi-Fi off for 30 s and on again; then, if there is a second network, switch to
   it and back. After each, reload the page: it must load within a few seconds.
   Mac, afterwards: `tests/stability/soak.sh status` to see that the soak noticed
   nothing.
4. **Battery power** (B). Charge to at least 80 %, unplug, keep the brightness
   fixed (auto-brightness off), close other apps. For each state run (Mac)
   `LABEL="..." MINUTES=30 tests/perf/battery.sh` and leave the machine alone:
   - HarmonyOS desktop only (native desktop stopped: `ssh ohdev sh
     /data/local/archtest/bin/omarchy desktop stop`, 鸿融 VM shut down);
   - "Omarchy (native)" open, idle;
   - "Omarchy (native)" open, `es2gears_wayland` running in it;
   - 鸿融 VM open on its Omarchy desktop, idle (native desktop stopped);
   - 鸿融 VM, `es2gears_wayland` running in it.
   Record the watts each prints. Plug back in.
5. **Start at boot** (only with Yao's go-ahead to reboot). Reboot the HM740 and
   log in. Within about a minute "Omarchy (native)" opened from the dock must show
   the desktop; `ssh ohdev cat /data/local/archtest/boot-start.log` shows when it
   started.
