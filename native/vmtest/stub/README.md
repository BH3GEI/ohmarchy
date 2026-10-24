# VM-API stub for the runtime probe

`@hms.virtService.vmManager.d.ts` is a **stub** type declaration (not a real Huawei
SDK file). It is reverse-engineered from the call sites in OSEasy's
(`com.oseasy1.ohvm`) `ets/modules.abc`:

- module specifier `@hms:virtService.vmManager`
- exported `virtualization` namespace: `createVm(bundleName, config)`, `startVm`,
  `stopVm`, `pauseVm`, `resumeVm`, `destroyVm`, `getVmAvailableCpuNumRange`, …
- abc also contains the constants `UNTRUSTED_CALLER` / `untrusted_caller`,
  `callerBundleName`, `publisherBundleName`, `hasPermissions` — i.e. the service
  validates the calling app's identity.

To reproduce the build: copy this file into
`/Applications/DevEco-Studio.app/Contents/sdk/default/hms/ets/api/` so hvigor can
resolve the import, then `./build.sh`. It compiles — the public SDK ships no such
declaration, so this stub is the only build-time requirement. At runtime the real
on-device module is what resolves (or refuses).
