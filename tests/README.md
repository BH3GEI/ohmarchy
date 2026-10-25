# Route D acceptance tests

Scripts behind [docs/acceptance.md](../docs/acceptance.md). They run on the machine
that drives the HarmonyOS host over ssh (`OHOS_HOST`, default `ohdev`) and execute in
the native Arch session (`ARCH_BASE`, default `/data/local/archtest`) as the desktop
user (`ARCH_USER`, default `builder`).

| Path | What |
|---|---|
| `run-all.sh` | F: everything below, one table (`SKIP="c1 b-coldstart"` to leave tests out) |
| `lib/remote.sh` | upload a script, run it detached on the host or in the session, poll for the result |
| `lib/session-py.sh` | run a Python test in the desktop session with its environment |
| `perf/idle.sh` | B: idle CPU and memory of the desktop's own processes |
| `perf/coldstart.sh` | B: desktop cold start (restarts the desktop) |
| `perf/workspace.sh` | B: workspace switch frame rate (display app in front) |
| `perf/app-threads.sh` | B: the display app's CPU per thread |
| `perf/power.sh` | B: power proxy (CPU time, clocks) for one state |
| `stability/dpms.py` | C: display off and on on Hyprland's side |
| `stability/bgfg.sh` | C: display app to the background and back |
| `stability/network.sh` | C: one site and DNS unreachable for 30 s |
| `stability/openclose.py` | C1: open and close apps 100 times |
| `stability/soak.sh` | C: 24 h soak, hourly `smoke.py` (start, status, stop) |
| `security/check.sh` | E: users, sudo, contexts, listeners, browser sandbox, seccomp |
| `apps/run.sh` | A1: every app opens a window within 3 s |
| `core/core_ops.py` | A2: files, clipboard, Chinese input, audio, file chooser |
| `audio/run.sh` | A3: sound latency to the speaker (the display app must be open) |
| `audio/avsync.sh` | A3: mpv sound vs picture |
| `compat/sysv_ipc.c` | SysV IPC on the HongMeng kernel |
| `demo/d.sh` | demo of route D: desktop start, app, terminal and fastfetch, workspaces (fps), Firefox, Omarchy menu and Files, docker hello-world; a screenshot per step (needs the screen) |
| `demo/i.sh` | demo of route I: VM start time, hello-world, compose with a bind mount, 0644 files (uses vm.lock) |

The tests only clean up processes they started themselves (the app's own session
and its descendants, or the window they opened), never other processes of the same
user: other work, such as package builds, may be running in the session meanwhile.

Results land in `tests/results/` (not committed).
