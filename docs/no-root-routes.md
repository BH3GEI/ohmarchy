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

## libc decision for the Hyprland stack: musl rebuild (path a), not nested glibc (path b)

D's Hyprland/aquamarine/mesa are glibc-built; the `jl` spawner runs inside the app's **OHOS
musl** process. Two options were weighed (evidence from a real aarch64 `glibc` 2.43 package):

- **(a) recompile the stack with OHOS clang/musl.** busybox already proves musl builds work
  (`device/jloader/build-busybox.sh`); Alpine ships musl patches for Hyprland, wlroots and
  mesa to start from.
- **(b) nested glibc: map a signed glibc `ld.so` in the musl process and jump to it.**

(b) is **not viable**:
1. A glibc `.so` imports versioned symbols `GLIBC_2.x` (the package shows up to GLIBC_2.43)
   that OHOS musl does not provide, so it cannot be `dlopen`'d into the musl process directly.
2. The decisive blocker is TLS. glibc `libc.so.6` has a `PT_TLS` segment and thread-local
   `errno`/`__resp`/`__h_errno`; glibc and musl keep the thread-control-block at the same
   AArch64 thread pointer (`TPIDR_EL0`) but with **incompatible layouts**. A thread can hold
   only one TCB, so the instant glibc code touches TLS (errno, malloc arena, stdio — i.e.
   almost immediately) it misreads musl's TCB and corrupts; and glibc's `ld.so` setting up its
   own TCB would clobber musl's and break the host app (ArkUI/render/vtest threads). Running
   glibc code only on dedicated threads with their own `TPIDR` (never calling back into musl)
   is theoretically possible but extremely fragile and still needs every glibc lib signed into
   the HAP — far more work than (a) for a worse result.

**Decision: path (a).** The Hyprland-stack port is a musl rebuild (Hyprland/aquamarine/wlroots/
mesa with OHOS clang/musl, linked `-shared` with a `main`/entry, `dlopen`'d by the `jl`
spawner), reusing Alpine's musl patches; D's existing glibc Arch packages are **not** reusable
in-process. A no-TLS "hello" could be made to run via (b), but it would not generalise, so an
empirical (b) run is not worth the device time.
## Hyprland-stack musl-rebuild assessment (path a)

Everything must be **recompiled against OHOS `libc.so`** with OHOS clang, linked `.so`, signed
into the HAP, and `dlopen`'d by the `jl` spawner. Alpine binaries can't be reused (Alpine musl
≠ OHOS musl); only its APKBUILDs/patches are borrowed. Grounded on D's on-device `ldd`
(Hyprland **0.56.2**, aquamarine **0.15.1**).

**Full glibc tree is huge, but most of it is droppable.** `ldd /opt/ohmarchy/bin/Hyprland` =
175 libs; with mesa deduped, 183 libs / **272 MiB** (excl. the 51 MiB `libgallium`). The bulk
is removable for the in-app headless build:
- `libLLVM` **163 MiB** — only for mesa's llvmpipe. **Dropped** by building mesa with
  `-Dgallium-drivers=virgl -Dllvm=disabled -Dvulkan-drivers= -Dplatforms=wayland -Dglx=disabled`
  (also removes SPIRV-Tools 3.8M + glslang 3.6M). GPU goes through mesa's **virgl** frontend →
  `vtest` → the host Maleoon `libvirglrenderer.so` the app already loads (`virpipe`, surfaceless
  EGL; `HYPRLAND_SURFACELESS_GALLIUM_DRIVER=virpipe`, `native/omarchy:86`). mesa then ≈ a few MB.
- **Drop xwayland** (removes the whole X11/xcb set), **systemd/libudev/libinput/libseat**
  (input is injected via `@ohmarchy-display` + aquamarine's headless patch), `libicudata` 32M
  (pull only if a kept lib truly needs ICU), `librsvg`/`libglycin`/`libjxl` (image formats, keep
  only what hyprgraphics needs).

**Must keep (the real build set):** `wayland` + `wayland-protocols`, `libxkbcommon`, `pixman`,
`libdrm` (core only), `cairo`, `pango`, `glib2`/`gio`, `harfbuzz`, `freetype2`, `fontconfig`,
`libpng`/`libjpeg-turbo`/`libwebp`(/`libjxl` if needed), `re2` + ~60 `abseil` libs, `lua`,
`muparser`, `tomlplusplus`, `libzip`, `libdisplay-info`, and the Hypr stack:
`hyprlang`/`hyprutils`/`hyprcursor`/`hyprgraphics`, `aquamarine` (libaquamarine.so.14),
`Hyprland`. C++ runtime: OHOS `libc++_shared` (not glibc `libstdc++`). Estimated HAP libs after
slimming: **~25–40 MiB** (vs 272).

**D's patches to carry over (required):**
- `native/desktop/patches/hyprland-0.56.2-hongmeng.patch` (491 lines) — surfaceless EGL render
  + readback, no dmabuf/gbm scanout.
- `native/desktop/patches/aquamarine-0.15.1-hongmeng.patch` (551 lines) — headless backend +
  DMAHeap, output/input over `@ohmarchy-display`.
- Sources via `native/desktop/fetch-sources.sh` → `native/desktop/src/{Hyprland,aquamarine}`.

**HongMeng-kernel shims (also needed in-app):** D's `native/desktop/*.c` LD_PRELOAD shims
`hongmeng-statx`, `hongmeng-uname`, `hongmeng-msgrcv`, `ohzc-memcpy` work around kernel quirks.
In the HAP there is no `LD_PRELOAD` across a `dlopen`, so these must be **compiled into the
build** (patched into the libs or linked into the spawner) or fixed in OHOS musl.

**Most likely to fail (D's experience + mine):**
1. **Hyprland itself** — C++26, needs very new clang/libc++; OHOS libc++ may lag → the top risk.
2. **mesa virgl winsys** — `vtest` is a unix socket; in-app it must become an internal
   connection (the app already hosts vtest), so the winsys needs repointing.
3. **glib2/gio** — platform assumptions; Alpine patches needed.
4. **libinput/udev** — just don't build them (input is injected).

**Recommendation:** feasible after slimming (~25–40 MiB, no LLVM). Staged proof: (1)
`wayland+xkbcommon+pixman+libdrm`; (2) `mesa` (virgl, no-llvm); (3) the Hypr C++ stack with D's
two patches + the HongMeng shims compiled in. Critical-path risks: Hyprland C++26 and the mesa
virgl winsys rework. Await agent-63's go for the full rebuild.
