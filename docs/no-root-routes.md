# No-root routes on ohdev (J: Arch userspace in a HAP sandbox; L: ArkWeb/wasm)

Question (Yao, 2026-10-25): with **no root and no reliance on the native/HMV path**, can a
plain debug HAP run Omarchy's userspace on ohdev? Route **J** = unpack an Arch rootfs into a
normal HAP's own `el2` sandbox and run it there (no chroot/namespace — HongMeng has no user
namespace, no `PR_SET_KEEPCAPS`, and `clone(CLONE_FS)`+chroot in a child does not affect the
parent; so run in-place via `ld.so` as loader + path-prefix rewriting). Route **L** (ArkWeb +
WebAssembly) is tracked by a separate session.

## Step 1 — executable-memory / XPM probe (gates J)

A minimal debug HAP (`native/xpmprobe`, bundle `com.ohmarchy.xpmprobe`) runs, in its native
layer (`entry/src/main/cpp/xpmprobe.cpp`, tag `XPMPROBE`), each way to obtain runnable code
memory and to run code, logging pass/fail + errno, with `dmesg` captured around launch.
Runners: `device/jprobe/run.sh` (step 1), `run1b.sh` (1b), `run1c.sh` (1c).

### Step 1 result (2026-10-25, on-device)

| Test | Result |
|---|---|
| (a) `mmap` anon RWX | **FAIL** `EINVAL` |
| (b) `mmap` RW then `mprotect` +EXEC | **FAIL** `EINVAL` |
| (c) `memfd` dual-map (RW + RX) | **FAIL** `EACCES` on the RX map |
| (d) `dlopen` a **system** `.so` | **OK** |
| (e) `execve /system/bin/toybox` (verified system ELF) | **OK** |

Kernel log is explicit: the HAP is denied `ohos.permission.kernel.ALLOW_WRITABLE_CODE_MEMORY`;
XPM reports `"jit set mem violated"` and `anon or file mmap/mprotect not allow exec permission`;
SELinux denies `{ execute }` on the `memfd`/tmpfs page for `scontext=debug_hap`. So a plain
debug HAP **cannot create writable-executable (JIT) memory** — a no-root TCG/JIT path is
impossible (this is exactly why Aetherium's QEMU aborts in `tcg_region_init`; see
[device-aetherium.md](device-aetherium.md)). But the HAP *can* `dlopen` signed `.so`s and
`execve` a verified system ELF.

### Step 1b — `execve` an unsigned ELF from the sandbox

The probe runs a tiny **static** `exit(42)` ELF (and a dynamic one) placed in the sandbox
(`debug_hap_data_file`), with the child logging `errno` on `execve` failure.

**Result:** `execve` of the sandbox ELF **FAILS with `EACCES` (errno 13)** — both static and
dynamic — while `/system/bin/toybox` runs fine. The HAP can execute **verified** code but not
an unsigned binary in its own sandbox (HarmonyOS code-integrity / XPM gate on file-backed
exec). With step 1 (no writable-exec memory) this means **running Arch ELFs directly is
blocked**: no JIT, no userland-exec, no `execve` of unsigned sandbox binaries.

### Step 1c — the `.so` fallbacks

(f) `dlopen` an unsigned `.so` dropped in the sandbox; (g) `execve` an ELF packed into the
HAP's signed `libs/` (`libexit42.so`, the Termux-on-Android-10 trick).

**Result:**
- (f) `dlopen` of an **unsigned sandbox `.so`** → **FAIL, Permission denied** (same gate).
- (g) `execve` of the HAP-`libs/` ELF → **FAIL, `EACCES`**; it installs mode `0644` (not
  executable) and a no-root app cannot `chmod +x` a root-owned bundle lib.
- But `dlopen` of a **signed HAP `.so` works** — proven by `libxpm.so` itself, which the
  system `dlopen`s to run this probe's napi module.

## Route J verdict

Every way to run **new, unsigned** native code in a no-root HAP is blocked on ohdev:

| Mechanism | Result |
|---|---|
| Writable-exec / JIT memory (mmap RWX, mprotect RX, memfd dual-map) | **blocked** (no `ALLOW_WRITABLE_CODE_MEMORY`, XPM) |
| `execve` unsigned ELF in sandbox | **blocked** (`EACCES`) |
| `execve` ELF packed in HAP `libs/` | **blocked** (installed `0644`, `EACCES`) |
| `dlopen` unsigned `.so` in sandbox | **blocked** (`EACCES`) |
| `execve` a verified **system** binary | works |
| `dlopen` a `.so` **signed into the HAP** | **works** |

So a no-root HAP can only run code **signed into the HAP at build time**, and only by
`dlopen`+calling an entry symbol (no `execve`, no new processes from new binaries, no
run-time `pacman`). Route J is therefore **viable only as a build-time-bundled userspace**:
compile the Arch programs (bash, coreutils, …) as `.so`s, sign them into the HAP, and run them
in-process via a `dlopen` loader that jumps to a `main`-like symbol (the Termux-on-A10 idea,
but via `dlopen`, since HAP libs install non-executable so `execve` of them is refused). This
is a large porting effort and loses run-time package installation, dynamic `exec`, and
multi-process semantics. The simple forms of J ("unpack a rootfs and run it", "drop binaries
and `exec` them") are **not possible** without root/signing.

## Note: Aetherium's QEMU is a JIT (not TCI) build

`libqemu_full.so` has `__jit_debug_descriptor`/`__jit_debug_register_code` and **no** `tci_*`
functions, i.e. it was built as a normal JIT TCG, not `--enable-tcg-interpreter`. So it needs
executable memory to run (which is why it aborts in `tcg_region_init` in the HAP). A no-root
TCG path would require a separate TCI build; deprioritised — and in any case step 1 shows the
HAP cannot get the executable memory even a TCI's generated glue/threads path might need for
dynamically loaded code, while a pure-interpreter TCI would still be bound by the `.so`-only
rule above.

## Route J prototype — WORKS (2026-10-25)

Built busybox 1.36.1 as a HAP-loadable shared object (`libbusybox.so`,
`device/jloader/build-busybox.sh`, OHOS clang/musl, `FEATURE_SH_STANDALONE` so applets run
in-process) and a loader HAP (`native/jloader`, `com.ohmarchy.jloader`): `libjl.so` forks,
`dlopen`s the HAP-signed `libbusybox.so`, and calls its `main` as `sh -c <cmd>`, capturing the
child's output through a pipe.

On-device output (`device/jloader-run.sh`):

```
=== J loader: sh -c "...ls / | wc -l; echo pid=$$; { sleep 1 & echo bg_pid=$!; wait; }; ..."
child exit=0
===J-START===
pipe: 0 entries in /         # the ls|wc pipeline ran; "ls: can't open '/'" is the sandbox FS
pid=55935                    # $$ works
bg_pid=55988                 # sleep 1 & + wait — background job via fork
loop1 / loop2 / loop3        # for-loop
cmdsub=0                     # $(...) command substitution ran
===J-END===
```

So a **no-root** debug HAP runs a real `busybox sh` — pipelines, `$$`, background jobs
(`&`/`wait`), command substitution, loops — entirely via **`dlopen` of a HAP-signed `.so` +
`fork` + in-process applets**, with **no `execve`, no JIT, no root, no chroot**. Multi-process
semantics survive (fork is allowed; only *mapping new unsigned code* is blocked). The `ls`
"permission denied" on `/` is just the HAP sandbox's filesystem policy — pointed at a readable
directory it lists normally.

**This validates route J as a build-time-bundled userspace.** Next (J+D): fold the same
fork+dlopen mechanism into the D-line display app (`native/app`, `com.ohmarchy.display`) so the
app itself launches the signed `.so` userspace, then assess compiling Hyprland + aquamarine as
`.so`s to run in the app process. Not possible this way: run-time `pacman`/new unsigned
binaries (everything must be signed into the HAP at build time).
