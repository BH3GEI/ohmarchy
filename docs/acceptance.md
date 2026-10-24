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
| A. Compatibility | every Omarchy app opens a window within 3 s; core operations work | `tests/apps/run.sh` | A1: 73 of 78 open within 3 s (P95 1.2 s), 4 unsupported, 0 failed (with the system D-Bus). A2: 6 of 6 core operations pass. Sound: 75-104 ms to the speaker (median), A/V within 100 ms; not yet heard (host volume 0) |
| B. Performance | cold start to desktop <= 10 s; app launch P95 <= 3 s; workspace switch >= 110 fps; idle memory/CPU recorded; power vs the HarmonyOS desktop | | pending |
| C. Stability | 100 open/close rounds without leftovers and < 5 % memory growth; 24 h soak with hourly smoke test; 20 screen off/on cycles; network loss and Wi-Fi change | | pending |
| D. Upgrade and recovery | one-command reset to a clean environment; regression after `pacman -Syu`; log bundle | | pending |
| E. Security | desktop and apps as an ordinary user; `su` context only where needed; browser sandbox | | pending; open items listed under E below |
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

Not verified yet: actually hearing it. HarmonyOS's media volume was 0 during the
tests and no one was at the machine; the stream ran on the speaker sink. Microphone
input is not done.

## E. Security: open items

- Sound: protocol-simple listens on 127.0.0.1:4714 in the host's network
  namespace, so any process on the HarmonyOS host can connect and receive the
  session's sound output (not send to it). To do: an abstract Unix socket relayed
  like the GPU's vtest-broker, or a peer-uid check. If the port is taken, PipeWire
  fails to load the module rather than picking another port.
