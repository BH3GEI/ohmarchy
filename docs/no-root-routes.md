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

### Stage 0 — C++26 toolchain probe (GO)

Hyprland 0.56 is C++26. Findings:
- **OHOS SDK toolchain is too old:** clang **15.0.4** / libc++ **15004** — no `-std=c++26`, and
  `<expected>`/`<format>` are absent (added in libc++ 16/17). Cannot build Hyprland.
- **Upstream clang 23 works:** homebrew `llvm` (clang 23.1.4) compiles C++26 language features
  (concepts, deducing-`this`, `consteval`, ranges) and emits **aarch64-ohos** objects
  (`--target=aarch64-linux-ohos --sysroot=<OHOS>`). The compiler barrier is cleared.
- **libc++ must be built from source for the musl target.** Homebrew's macOS libc++ headers
  can't be reused (Darwin availability markup + a Darwin locale/rune-table backend baked in →
  `unknown rune table`/`availability` errors). The fix is a from-source **libc++ + libc++abi
  built for `aarch64-linux-ohos` with `-DLIBCXX_HAS_MUSL_LIBC=ON`**, statically linked. This is
  a standard procedure (musl distros do it) and is **stage-1 prerequisite #0**.

**Decision: GO.** Toolchain = upstream clang 23 + a libc++23 built for OHOS musl; the remaining
risk shifts from "compiler too old" (cleared) to "build libc++ + the stack against OHOS musl".

### Stage 1 — libc++23 + the Wayland base stack for OHOS musl (DONE)

All built offline on a Mac, aarch64-linux-ohos, static libs; **no build products on ohdev**.
Recipe: `device/userspace/build-stage1.sh` (+ `ohos.cross.sample`, `native.ini.sample`).

**Prerequisite #0 — libc++23 (clang 23 + musl).** Built libc++/libc++abi/libunwind from the
LLVM 23.1.4 tree with the cmake *runtimes* build, `-DLIBCXX_HAS_MUSL_LIBC=ON`,
`-DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY` (homebrew clang has no OHOS crt/builtins for the
configure link test), `-DLLVM_INCLUDE_TESTS=OFF` + sparse-checkout `llvm/utils/llvm-lit`, and
`-I<llvm-project/libc>` on CXXFLAGS (charconv needs `shared/fp_bits.h` from LLVM libc). Output:
`libc++.a` 2.5M, `libc++abi.a` 739K, `libunwind.a` 138K, `libc++experimental.a` 2.3K;
`__config_site` has `_LIBCPP_HAS_MUSL_LIBC 1`. **End-to-end verified:** a C++26 program using
`std::expected`/`std::format`/ranges compiles to an aarch64-ohos object against this libc++.

**Toolchain note:** the four C libraries below are built with the **OHOS NDK's own clang 15**
(it ships matching crt + `libclang_rt.builtins` for the musl target, so executables/`.so` link
with no extra flags). The clang-23 + libc++23 toolchain is reserved for the Stage-3 C++ stack.
macOS host tools: meson (pip venv), ninja, **bison ≥2.3a** (Apple's 2.3 fails xkbcommon's YACC
check → `brew install bison`), expat (for the native wayland-scanner).

| lib | version | artifact | size |
|---|---|---|---|
| libffi | 3.4.6 | libffi.a | 105K |
| pixman | 0.44.2 | libpixman-1.a | 2.8M |
| libdrm | 2.4.124 | libdrm.a (no vendor drivers) | 364K |
| libxkbcommon | 1.7.0 | libxkbcommon.a (no x11/registry/tools) | 1.2M |
| wayland | 1.23.1 | libwayland-client.a 238K / -server.a 351K / -cursor.a 81K / -egl.a 6.4K | — |

wayland needs a **wayland-scanner that runs on the build host**: built natively on the Mac
(`-Dscanner=true -Dlibraries=false`) into a separate native prefix, then the target libs are
cross-built with `-Dscanner=false` and a meson **native file** whose `pkg_config_path` points at
the native `wayland-scanner.pc`. libffi is wayland's only hard dep. All `.a` confirmed AArch64;
`.pc` files land in `$PREFIX/lib/pkgconfig` for the downstream builds. **Next: Stage 2 (mesa
virgl, no-llvm).**

### Stage 2 — mesa (virgl, no-LLVM) for OHOS musl (DONE)

Built offline on a Mac (NDK clang 15), **no build products on ohdev**. Recipe:
`device/userspace/build-stage2.sh`. mesa **24.3.4**, `-Dgallium-drivers=virgl -Dllvm=disabled
-Dvulkan-drivers= -Dplatforms=wayland -Dglx=disabled -Degl -Dgles2 -Dgbm`.

Added target deps: **zlib 1.3.1** (libz.a 117K — its Darwin Makefile forces Apple `libtool`
which rejects ELF objects, so the lib is built by hand), **expat 2.6.4** (libexpat.so 167K — a
runtime `NEEDED` of libEGL; the tools subdir errors but the lib installs), and host data
**wayland-protocols 1.38** (into the native prefix). mesa host-build python needs `mako` +
`packaging` (its mako check imports `packaging.version`; distutils is gone in py3.12+) + `pyyaml`.

| artifact | size |
|---|---|
| libEGL.so | 681K |
| libGLESv2.so | 86K |
| libgbm.so | 194K |
| libgallium-24.3.4.so (**holds the virgl driver**) | 14M |
| libexpat.so (runtime dep) | 167K |
| **deployable total** | **~16M** |

virgl confirmed inside libgallium (`pipe_virtio_gpu_create_screen` + the full `virgl_*` gallium
API). All `.so` are AArch64. libEGL's runtime `NEEDED`: libgallium, libgbm, libglapi, libexpat,
plus OHOS `libc++_shared.so` + musl `libc.so` — all satisfiable on device. The guest-side virgl
pipe talks to a host virglrenderer; wiring that to Aetherium's in-app GL path is the Stage-2→3
integration risk already flagged. **Next: Stage 3 (Hypr C++ stack with clang 23 + libc++23).**

### Stage 3 — Hypr C++ stack for OHOS musl (IN PROGRESS)

The hard stage. Toolchain = homebrew **clang 23** + the from-source **libc++23** (OHOS musl).
Recipe: `device/userspace/build-stage3.sh` + `ohos-cmake.toolchain.sample`.

**Toolchain fixes discovered (all now encoded in the toolchain file):**
1. **libc++ must be PIC** — the static `libc++.a` is linked into each `.so`, so libc++23 was
   rebuilt with `-DCMAKE_POSITION_INDEPENDENT_CODE=ON` (else `R_AARCH64_ADD_ABS_LO12_NC …
   recompile with -fPIC`).
2. **libunwind `.S` must target OHOS** — the first libc++ build assembled
   `UnwindRegistersSave/Restore.S` for the host (Mach-O), which lld rejects; fixed with
   `-DCMAKE_ASM_COMPILER_TARGET=aarch64-linux-ohos`. (libc++.a/libc++abi.a were already correct
   ELF; only libunwind's two asm objects were affected.)
3. **clang 23's OHOS driver links GCC-style** — it looks for `crtbeginS.o`/`crtendS.o` and
   builtins in its own (empty) resource dir, whereas the NDK ships `clang_rt.crtbegin.o` +
   `libclang_rt.builtins.a`. Bridged with a compat dir (NDK crt renamed + builtins + our
   libc++/libc++abi/libunwind via `-B`/`-L`) and a fake `-resource-dir`.
4. **libc++ is static-linked into every component** — OHOS ships `libc++_shared.so` v15, ABI-
   incompatible with our v23, so we never link it.

**Built so far (shared libs, AArch64, self-contained but for libc.so):**

| lib | version | size |
|---|---|---|
| libhyprutils.so | 0.14.3 | 4.2M |
| libhyprlang.so | 0.6.8 | 1.8M |

hyprlang's `hyprlang_test`/`hyprlang_fuzz` **executables also linked** — full compile+link of
C++26 for OHOS confirmed, not just archiving. **This clears the Stage-0 top risk** ("Hyprland
C++26 won't build on the available toolchain") at the library level.

**Remaining:** the C support stack (cairo, pango, glib/gio, harfbuzz, freetype, fontconfig,
libjpeg-turbo, libwebp, re2+abseil, muparser, lcms2, lua 5.5, libuuid, xcursor, libeis, udis86),
the C++ header/tools (glaze, glslang, hyprwayland-scanner, hyprland-protocols), then hyprgraphics
/ hyprcursor / aquamarine, and finally Hyprland 0.56.2 with D's two hongmeng patches + the
HongMeng shims. glib/gio is the heaviest cross-compile; libinput is skipped (input is injected).
