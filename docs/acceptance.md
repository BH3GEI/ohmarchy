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
| A. Compatibility | every Omarchy app opens a window within 3 s; core operations work | `tests/apps/run.sh` | in progress |
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

Results: see below (filled in by the latest run).
