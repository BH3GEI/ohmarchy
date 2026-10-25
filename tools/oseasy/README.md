# tools/oseasy

The goal named `tools/oseasy/` for the Oseasy-route scripts. By the supervisor's
decision the whole project lives on `main` (not a `wip/oseasy` branch), and the
Oseasy scripts are kept under [`../../oseasy/`](../../oseasy) next to the guest
driver in [`../../driver/vmwgfx-oseasy-7.2/`](../../driver/vmwgfx-oseasy-7.2),
rather than split under `tools/`. This page exists so the named path resolves.

- Scripts and probes: [`oseasy/`](../../oseasy) — `probe.sh`, `vmlock.sh`,
  `measure-fps.sh`, `guest-bench.sh`, `guest/` (hang-capture, boot-diag), `probe/`.
- Guest display driver: [`driver/vmwgfx-oseasy-7.2/`](../../driver/vmwgfx-oseasy-7.2).
- Write-up and comparison table: [`docs/oseasy-whole-os.md`](../../docs/oseasy-whole-os.md),
  pointer at [`docs/vm-oseasy.md`](../../docs/vm-oseasy.md).
- Run logs: [`oseasy/runs/`](../../oseasy/runs).
