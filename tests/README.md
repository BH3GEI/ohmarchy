# Route D acceptance tests

Scripts behind [docs/acceptance.md](../docs/acceptance.md). They run on the machine
that drives the HarmonyOS host over ssh (`OHOS_HOST`, default `ohdev`) and execute in
the native Arch session (`ARCH_BASE`, default `/data/local/archtest`) as the desktop
user (`ARCH_USER`, default `builder`).

| Path | What |
|---|---|
| `lib/remote.sh` | upload a script, run it detached on the host or in the session, poll for the result |
| `lib/session-py.sh` | run a Python test in the desktop session with its environment |
| `apps/run.sh` | A1: every app opens a window within 3 s |
| `core/core_ops.py` | A2: files, clipboard, Chinese input, audio, file chooser |
| `compat/sysv_ipc.c` | SysV IPC on the HongMeng kernel |

The tests only clean up processes they started themselves (the app's own session
and its descendants, or the window they opened), never other processes of the same
user: other work, such as package builds, may be running in the session meanwhile.

Results land in `tests/results/` (not committed).
