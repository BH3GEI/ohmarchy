-- Entry for the native HarmonyOS display (ohmarchy-desktop): Omarchy's config plus
-- the headless output the display app shows. Defaults to 1920x1280 at scale 1, which
-- the app scales up to the window: every frame is read back from the GPU, so pixels
-- cost time. OHMARCHY_DISPLAY_MODE=2880x1920@60 OHMARCHY_DISPLAY_SCALE=1.5 is the
-- panel's own resolution: sharper, about half the frame rate.
dofile(os.getenv("HOME") .. "/.config/hypr/hyprland.lua")

hl.monitor({
  output = "HEADLESS-2",
  mode = os.getenv("OHMARCHY_DISPLAY_MODE") or "1920x1280@60",
  position = "0x0",
  scale = tonumber(os.getenv("OHMARCHY_DISPLAY_SCALE") or "1"),
})

-- The display app gets frames and sends input over aquamarine's export socket
-- (AQ_HEADLESS_EXPORT), so nothing captures the screen.
hl.on("hyprland.start", function()
  hl.exec_cmd("hyprctl output create headless HEADLESS-2")
end)
