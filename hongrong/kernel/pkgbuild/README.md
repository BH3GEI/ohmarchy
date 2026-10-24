# linux-aarch64 with the 鸿融 patches

`PKGBUILD` is Arch Linux ARM's `core/linux-aarch64` (archlinuxarm/PKGBUILDs,
7.2.12-1) with four changes: `pkgrel=1.1`, sources from the TUNA kernel mirror,
`../patches/*.patch` added as `hmv-*.patch` and applied after ALARM's patches,
and no `-chromebook` package (it needs vboot-utils).

Build it next to ALARM's other files:

```sh
git clone --depth 1 https://github.com/archlinuxarm/PKGBUILDs
cd PKGBUILDs/core/linux-aarch64
cp /path/to/ohmarchy/hongrong/kernel/pkgbuild/PKGBUILD .
for p in /path/to/ohmarchy/hongrong/kernel/patches/*.patch; do cp "$p" "hmv-$(basename "$p")"; done
makepkg -s
```

For a newer ALARM release, take its PKGBUILD and redo the four changes; the
patches are against 7.2.11 and apply to 7.2.12 unchanged.

Boot the kernel with `arm64.hmv_idreg_quirk` (see
[../../../docs/hmv-idreg-report.md](../../../docs/hmv-idreg-report.md)).

Built on the HarmonyOS PC (Arch Linux ARM in a chroot on the HongMeng kernel),
2026-10-24: 20 cores, about 25 minutes. Notes from that build:

- fakeroot hangs unless `libhongmeng-msgrcv.so` is preloaded
  ([../../../docs/native-compat.md](../../../docs/native-compat.md)).
- Do not build as a user whose processes something else may kill: the native
  desktop's app-launch test SIGTERMs every new process of its own uid, which
  took out `make` twice. A dedicated build user avoids it.
