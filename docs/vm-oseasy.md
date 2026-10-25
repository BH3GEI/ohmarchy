# Omarchy in Oseasy

The work on the Oseasy route lives in [oseasy-whole-os.md](oseasy-whole-os.md):
install source and version, the VMM and its devices, image checks, the port
(guest driver `vmwgfx-oseasy`, installer ISO), every run, and the comparison
table Oseasy vs 鸿融 vs native.

All work is on `main` (as agreed); there is no separate branch. The planned
`wip/oseasy` branch was replaced by `main` of
[BH3GEI/ohmarchy](https://github.com/BH3GEI/ohmarchy) (the fork of
[ymote/ohmarchy](https://github.com/ymote/ohmarchy)), where every line of the
project is kept. The scripts are in [`oseasy/`](../oseasy) rather than
`tools/oseasy/`, and the driver is in
[`driver/vmwgfx-oseasy-7.2/`](../driver/vmwgfx-oseasy-7.2).
