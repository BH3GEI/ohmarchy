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
memory, and logs pass/fail + errno, with `dmesg -w` attached before launch to catch AVC/XPM:

- (a) anonymous `mmap(PROT_READ|WRITE|EXEC)` then call it
- (b) `mmap(RW)` then `mprotect(RX)` then call it
- (c) `memfd_create` + dual map (RW to write, RX to exec) then call it
- (d) `dlopen` a system `.so` (already-signed code)
- (e) `fork`+`execve` a binary (`/system/bin/toybox`; later an Arch ELF in the sandbox)

(a)/(b)/(c) decide whether a TCG JIT or a `ld.so`/userland-exec loader can ever run; (e)
decides whether we can spawn ELFs at all. **Result: pending the on-device run.**

## Note: Aetherium's QEMU is a JIT (not TCI) build

`libqemu_full.so` has `__jit_debug_descriptor`/`__jit_debug_register_code` and **no** `tci_*`
functions, i.e. it was built as a normal JIT TCG, not `--enable-tcg-interpreter`. So it needs
executable memory to run (which is why it aborts in `tcg_region_init` in the HAP — see
[device-aetherium.md](device-aetherium.md)). A no-root TCG path would require a separate TCI
build; deprioritised in favour of J.

## Step 2 — Arch userspace in the sandbox (if step 1 permits)

Pending step 1. Plan: unpack rootfs under `/data/.../<bundle>/files/arch`, run binaries via
`ld-linux-aarch64.so.1 --library-path <sandbox>/usr/lib <sandbox>/usr/bin/<prog>` if direct
`execve` is blocked; rewrite absolute path prefixes; bring up `bash`, `pacman`, `fastfetch`
first, then port the native route's Hyprland + display app. No root.
