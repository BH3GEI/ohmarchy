# Route A: Omarchy apps in HarmonyOS's Linux engine

HarmonyOS PCs ship an official Linux engine (融合开发引擎): an openEuler container
with a terminal but no GUI. A third-party launcher from AppGallery,
**融合开发图像引擎** ("专业 Linux GUI 软件启动器", `com.mikannqaq.developer.linuxEngine`),
installs an X11 bridge into that container and shows each Linux app as a
native HarmonyOS window (Wayland and Vulkan buffers through Venus on the
machine's GPU). That is enough for Omarchy's terminal tools. A full Hyprland
session does not fit into this per-window model.

## Steps

1. Install 融合开发引擎 and start it. Open its openEuler terminal and finish the
   first-run setup, creating your own user.
2. Install 融合开发图像引擎 from AppGallery and run its pairing install inside
   the container. If it stops and asks for a restart because SELinux must be
   disabled, power the engine off and on, then run the pairing install again.
   The launcher then lists the container's apps (XTerm, editor, files).
3. Copy `linux-engine/*.sh` into HarmonyOS's Download folder (下载). Inside the
   container it is `/mnt/linux_share/storage/Users/currentUser/Download`.
4. Open XTerm from the launcher and run:

   ```sh
   bash /mnt/linux_share/storage/Users/currentUser/Download/install-omarchy-nvim.sh
   bash /mnt/linux_share/storage/Users/currentUser/Download/install-omarchy-cli.sh
   ```

   Progress goes to `omarchy-nvim.log`, `omarchy-cli.log` and the matching `.result`
   files in the same folder.
   To use your own Omarchy neovim setup, first run
   `tar -czf omarchy-nvim.tgz -C ~/.config nvim` on an Omarchy machine and put
   `omarchy-nvim.tgz` in the Download folder.

## Notes

- openEuler has no neovim package, so the script uses the static ARM64 build.
  fastfetch, btop and lazygit are static ARM64 release binaries too.
- `github.com` downloads from the container often fail with
  `Proxy CONNECT aborted`; the scripts retry through the `gh-proxy.com` mirror.
- Omarchy's `lua/plugins/theme.lua` is a symlink into the Omarchy theme
  switcher's state directory. The script replaces it with a concrete theme
  (tokyonight by default; set `COLORSCHEME`/`THEME_PLUGIN` to change it).
- Driving XTerm from the host with `uitest uiInput inputText`: the first text
  sent after focusing an X11 window loses its first characters. Send a short
  throwaway command first.
