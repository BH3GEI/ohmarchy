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
| `lib/screen-free.sh` | fails while `/data/local/vm.lock` is held (screen in use by someone else) |
| `perf/idle.sh` | B: idle CPU and memory of the desktop's own processes |
| `perf/coldstart.sh` | B: desktop cold start (restarts the desktop) |
| `stability/openclose.py` | C1: open and close apps 100 times |
| `stability/soak.sh` | C: 24 h soak, hourly `smoke.py` (start, status, stop) |
| `security/check.sh` | E: users, sudo, contexts, listeners, browser sandbox, seccomp |
| `apps/run.sh` | A1: every app opens a window within 3 s |
| `core/core_ops.py` | A2: files, clipboard, Chinese input, audio, file chooser |
| `audio/run.sh` | A3: sound latency to the speaker (the display app must be open) |
| `audio/avsync.sh` | A3: mpv sound vs picture |
| `compat/sysv_ipc.c` | SysV IPC on the HongMeng kernel |

The tests only clean up processes they started themselves (the app's own session
and its descendants, or the window they opened), never other processes of the same
user: other work, such as package builds, may be running in the session meanwhile.

The HarmonyOS screen is shared: whoever holds `/data/local/vm.lock` owns the
screen and focus. Tests that open or bring the display app ("Omarchy (native)") to
the front check `lib/screen-free.sh` first and do not run while the lock is held;
work that does not touch the screen (the session-side tests) goes on.

Results land in `tests/results/` (not committed).
