# Route L: Linux in ArkWeb (browser emulator in an unprivileged HAP)

**Status: paused by decision 2026-10-25.** Yao decided the browser route is not
the direction. What exists: a working image build, page and signed HAP, verified
on a desktop browser. **Nothing was run on the device**: the HAP and disk image
were pushed to `ohdev:/data/local/tmp/routel/` but never installed, because
the screen was in use by other sessions for the whole window, from 08:56 to past 11:00 PDT. So the main open question, whether
ArkWeb in a third-party HAP gets wasm JIT, is **not answered**.

Idea: run a real Linux distro inside HarmonyOS's built-in browser engine via a
WebAssembly emulator, as an ordinary app. No root, no VM permission, independent
of routes D/H/I. Route H showed a debug HAP's own native code gets no executable
memory (QEMU TCG aborts in `tcg_region_init`); a browser engine's renderer is a
separate process that normally has a JIT entitlement, which is what this route
would rely on.

## Emulator choice: v86

Omarchy itself (aarch64 + Hyprland) is out of reach for any browser emulator, so
the realistic target is an Arch-family shell with pacman.

| Candidate | Guest | Speed | Arch-family userland | License | Verdict |
|---|---|---|---|---|---|
| **v86** | x86 (i686, SSE2, PAE) | JIT: x86 blocks compiled to wasm at runtime | Arch Linux 32 (i686), with pacman | BSD-2-Clause | **chosen** |
| TinyEMU | RISC-V 64 | interpreter, several times slower | Arch RISC-V possible | MIT | slower, no JIT |
| container2wasm | x86/RISC-V via Bochs/TinyEMU compiled to wasm | interpreter | any container image | Apache-2.0 | slower; whole image in the wasm blob |
| WebVM / CheerpX | x86 (JIT) | fast | Debian | proprietary, commercial use needs a license | not used (license would need Yao) |

v86 is the fastest open option and Arch Linux 32 is the closest thing to Arch it
can run: same pacman, same package layout, systemd, Arch's own kernel build.

## What was built (`webemu/`)

- `image/build-image.sh`: Arch Linux 32 (i686) by `pacstrap` from
  mirror.archlinux32.org, in an Alpine container (native pacman; the i686
  scriptlets and `mkinitcpio` run through qemu-user binfmt, colima on the Mac).
  140 packages (`base linux archlinux32-keyring less which`), kernel
  6.19.11-arch1, systemd 259, pacman 7.1 with keyring populated and sync
  databases included. Initramfs with only v86's drivers (`HOOKS=(base)`, PIIX
  IDE, ext4, virtio, ne2k, 9p): 6 MB. Root logs in on `ttyS0` automatically
  (no password). Output: `arch32.img` (ext4, 1.3 GB, 300 MB gzipped),
  `vmlinuz`, `initramfs.img`. `routel-bench` in the guest is a fixed workload.
- `web/`: the page. xterm.js serial console wired to v86's `ttyS0`; an engine
  probe (WebAssembly present? a hand-assembled wasm loop and the same loop in JS,
  timed); a wrapper around `WebAssembly.instantiate` that counts v86's runtime
  JIT compilations (success/failure); a status bar with MIPS, JIT blocks and
  boot marks; `ROUTEL ...` console lines for logs.
- `app/`: HAP `com.ohmarchy.webemu` ("Arch in ArkWeb"), one ArkTS page with a
  `Web` component. Everything is served under `https://routel.local/` by
  `onInterceptRequest`: page, v86, BIOS, kernel from rawfile, and the disk with
  HTTP byte ranges (`206`, `Content-Range`) from the sandbox
  (`files/arch32.img`) or, with `build.sh --with-image`, from rawfile.
  Console lines go to hilog (tag `routel`). Built and signed with native/app's
  `sign.sh` (linked); 21 MB without the disk. Builds cleanly; never installed.
- `tools/serve.py` + `tools/desktop-run.py`: the same page on a desktop
  (Range-capable server, headless Chrome, auto benchmark).
- `tools/device.sh`: install, copy the disk into the sandbox, start/stop, hilog,
  memory. Written, **not run** on the device.

## Numbers (desktop reference only)

MacBook (Apple Silicon), headless Chrome 155, guest 512 MB, two runs:

| | run 1 | run 2 |
|---|---|---|
| page start to first serial byte | 15.3 s | 8.7 s (smaller initramfs) |
| to `login:` | 31.7 s | 26.8 s |
| to root shell prompt | 37.1 s | 31.9 s |
| `sha256sum` 4 MiB | 598 ms | 623 ms |
| `bzip2 -9` 4 MiB (repetitive text, slow case) | 6838 ms | 8669 ms |
| `gzip -6` 4 MiB | 241 ms | 274 ms |
| bash loop, 100k iterations | 8385 ms | 9157 ms |
| `pacman -Q` (140 packages) | 404 ms | 414 ms |
| v86 rate while busy | 400 to 1800 MIPS | |
| v86 JIT modules compiled / failed | 928 / 0 (88 MB of wasm) | |
| JS heap | 30 to 80 MB | |

Engine probe (1e8 iterations): JIT Chrome, wasm 134 ms and JS 545 ms;
`--js-flags=--jitless` Chrome, **no WebAssembly at all** and JS 2711 ms
(node 24: 538 ms vs 2104 ms jitless). So on the device the probe alone would
answer the JIT question: `wasm: false` means v86 cannot run at all (V8 disables
wasm in jitless mode); `wasm: true` with a loop near ~150 ms and v86's JIT
counter growing with 0 failures means the renderer has JIT.

## Not done

- On the device: install, launch, boot, screenshots, time to prompt,
  `routel-bench`, app/render memory, JIT probe. Inputs are ready in
  `ohdev:/data/local/tmp/routel/` (`webemu.hap`, `arch32.img`,
  `arch32.img.gz`, about 1.6 GB; safe to delete).
- Keyboard and HarmonyOS IME into xterm.js: untested on the device (works with
  a desktop keyboard).
- Networking in the guest (pacman downloads): v86 would need a relay (WebSocket
  or its fetch-based adapter, which mirrors do not allow because of CORS).
  Packages are installed at image build time only.

## Reproduce

```sh
DOCKER_HOST=unix://$HOME/.colima/default/docker.sock webemu/image/build-image.sh   # ~8 min
webemu/fetch.sh                                   # v86 0.5.472, xterm.js 6.0.0, BIOS
python3 webemu/tools/serve.py 8086 &              # desktop comparison
python3 webemu/tools/desktop-run.py "http://127.0.0.1:8086/index.html?autobench=1"
webemu/app/build.sh --no-install                  # HAP; then:
#   push webemu.hap and arch32.img to /data/local/tmp/routel (device/push-resumable.sh),
#   webemu/tools/device.sh install; device.sh disk; device.sh start; device.sh log
```
