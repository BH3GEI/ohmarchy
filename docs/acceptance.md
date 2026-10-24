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
| A. Compatibility | every Omarchy app opens a window within 3 s; core operations work | `tests/apps/run.sh` | A1: 72 of 78 open within 3 s (P95 1.4 s), 6 unsupported, 0 failed. A2: 5 of 6 core operations pass; audio unsupported (no sound device) |
| B. Performance | cold start to desktop <= 10 s; app launch P95 <= 3 s; workspace switch >= 110 fps; idle memory/CPU recorded; power vs the HarmonyOS desktop | | pending |
| C. Stability | 100 open/close rounds without leftovers and < 5 % memory growth; 24 h soak with hourly smoke test; 20 screen off/on cycles; network loss and Wi-Fi change | | pending |
| D. Upgrade and recovery | one-command reset to a clean environment; regression after `pacman -Syu`; log bundle | | pending |
| E. Security | desktop and apps as an ordinary user; `su` context only where needed; browser sandbox | | pending |
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

Unsupported, with the reason (reported as such by the test, not as failures):

| Entry | Why |
|---|---|
| Docker, menu > Docker | no container runtime: no cgroup v2 or user namespaces for dockerd; pkexec also needs polkit on a system bus |
| Disks (gnome-disks) | needs udisks2 on the system D-Bus, which does not run in the session |
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
| audio | play a tone with pw-play, paplay, then aplay | unsupported: no `/dev/snd`, no sound server; needs a bridge to HarmonyOS audio |
| file-chooser | ask the desktop portal for an Open File dialog | pass, xdg-desktop-portal-gtk dialog in 1.3 s |

LibreOffice's text export starts with a byte-order mark; the test reads it with
`utf-8-sig`. A Hyprland that has had no input yet gives a new window no keyboard
focus; the HarmonyOS app always moves the pointer first, so the test does too.
