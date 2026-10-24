# Route D acceptance: Omarchy natively on HarmonyOS

What "usable" means for the native desktop ([native-desktop.md](native-desktop.md)),
how each part is tested, and the latest results. Every test is a script under
`tests/`; `tests/run-all.sh` runs them all and prints one table. Scripts take the
host and paths from the environment (`OHOS_HOST`, default `ohdev`; `ARCH_BASE`,
default `/data/local/archtest`; `ARCH_USER`, default `builder`), so they are not
tied to one machine.

Test machine: HUAWEI HM740 (Kirin X90, 20 threads, 32 GB), HarmonyOS 7.0
(HongMeng kernel 1.11.13.0).

| Area | Criterion | Test | Status |
|---|---|---|---|
| A. Compatibility | every Omarchy app opens a window within 3 s; core operations work | `tests/apps/run.sh` | A1: 73 of 78 open within 3 s (P95 1.2 s), 4 unsupported, 0 failed (with the system D-Bus). A2: 6 of 6 core operations pass (sound not yet heard by ear: to confirm on site). Sound: 75-104 ms to the speaker (median), A/V within 100 ms; not yet heard (host volume 0) |
| B. Performance | cold start to desktop <= 10 s; app launch P95 <= 3 s; workspace switch >= 110 fps; idle memory/CPU recorded; power vs the HarmonyOS desktop | `tests/perf/` | preliminary (machine under load): desktop start 6.2 s, launch P95 1.2 s, idle 0.5 % CPU / 1.0 GB without the app; fps and app-open idle to re-measure; power needs a run on battery |
| C. Stability | 100 open/close rounds without leftovers and < 5 % memory growth; 24 h soak with hourly smoke test; 20 screen off/on cycles; network loss and Wi-Fi change | `tests/stability/` | 100 rounds: all opened, +0.1 % memory, nothing hung. Soak, screen and network: pending |
| D. Upgrade and recovery | one-command reset to a clean environment; regression after `pacman -Syu`; log bundle | | pending |
| E. Security | desktop and apps as an ordinary user; `su` context only where needed; browser sandbox | `tests/security/check.sh` | desktop as an ordinary user, sudo needs a password, loopback-only listeners: pass. Open: Chromium without sandbox, host GPU server as root, sound port readable by host processes |
| F. Regression | `tests/run-all.sh`, one table | | pending |
| G. Other devices | | | to do: only one machine so far |

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
itself). A/V: the picture is the slow side here (mpv on the CPU, the host GPU path,
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
| Desktop cold start: `omarchy desktop start` until the Omarchy bar and background are up (session already running) | `tests/perf/coldstart.sh` | 6.0-6.3 s (3 rounds; Hyprland answers at 4.1-4.4 s, bar 4.7-5.1 s) | <= 10 s |
| App launch | `tests/apps/run.sh` (A1) | median 0.67 s, P95 1.22 s | P95 <= 3 s |
| Workspace switch | Phase 2 measurement (HarmonyOS composer fps, in-app GPU path) | 115-116 fps at 1920x1280 | >= 110 fps; to re-run as a script |
| Idle CPU and memory, desktop processes only | `tests/perf/idle.sh` | display app closed: 0.5 % of one core, 1.0 GB (PSS; Omarchy shell 430 MB, Hyprland 140 MB, fcitx5 67 MB). Display app open: about 14 % of one core more, in the app itself | recorded |
| Power vs the HarmonyOS desktop | | not measured: on mains with a full battery the battery reports 0 current; needs a run on battery | |

Found while measuring, fixed:

- PipeWire sent silence to the display app all the time: 10 % of a core for
  PipeWire alone. Its forwarding stream is now passive, so the sound graph sleeps
  when nothing plays (0.03 %); the app treats a quiet socket as silence.
- With the host GPU server, every desktop restart left one server process behind
  (about 80 MB each): on HongMeng it is not told its client went away.
  `omarchy desktop stop` now ends them.

Open: the display app's own idle CPU (about 14 % of a core with nothing changing on
screen; likely its 120 Hz frame callback running with no new frames).

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

## E. Security

`tests/security/check.sh`, 2026-10-24 17:50:

| Check | Result |
|---|---|
| Desktop processes (Hyprland, Omarchy shell, Xwayland, sound, input method) run as the ordinary desktop user | pass |
| Root in the session | only udisksd and upowerd (system bus services, as on any Linux), plus whatever someone runs as root (a package build's pacman during the check) |
| Desktop user gets root without a password | pass since 17:50 (was: fail). `builder` was in `wheel` with `NOPASSWD: ALL`, which matters more here than on a normal Linux: without user namespaces root in the session is root on the HarmonyOS host (`u:r:su:s0`). Now `/etc/sudoers.d/10-wheel` asks for the password (set per internal convention); Omarchy's own narrow NOPASSWD rules (DNS, timezone, browser theme policy) sort after it and still work without one (checked with `sudo -l`). `native/40-install-desktop.sh` does this as its last step (the install itself still runs passwordless); the old sudoers are backed up in the session's `/root/sudoers-backup-*` |
| Host side | the session's init and the host GPU server (`OHMARCHY_GPU=host`) run as root in `u:r:su:s0`; with the in-app GPU path the renderer runs inside the display app (an ordinary app sandbox) and only the broker is root |
| Listeners | pass: only 127.0.0.1:4714 (sound, below) |
| Browser sandbox | fail: Chromium runs with `--no-sandbox`. Without user namespaces it needs its setuid helper; with it the zygote starts in its own PID namespace (pid 1) but never completes its handshake. Ruled out: PID and network namespaces work as root, seccomp-bpf works, and turning Chromium's seccomp policy off does not help. Next to look at: how the helper passes the zygote's socket (SCM_RIGHTS) and its use of `/proc/self/ns` |
| seccomp-bpf | pass: the kernel takes filters (so a working setuid sandbox would get both layers) |

Open items:


- Sound: protocol-simple listens on 127.0.0.1:4714 in the host's network
  namespace, so any process on the HarmonyOS host can connect and receive the
  session's sound output (not send to it). To do: an abstract Unix socket relayed
  like the GPU's vtest-broker, or a peer-uid check. If the port is taken, PipeWire
  fails to load the module rather than picking another port.
