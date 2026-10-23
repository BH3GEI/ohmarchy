-- Entry for the native HarmonyOS display (ohmarchy-desktop): Omarchy's config plus
-- the headless output the display app shows. Defaults to the panel's 2880x1920 at
-- scale 1.5; OHMARCHY_DISPLAY_MODE / OHMARCHY_DISPLAY_SCALE trade sharpness for speed
-- (e.g. 1920x1280@60 at 1 renders 2.25x fewer pixels; the app scales it up).
dofile(os.getenv("HOME") .. "/.config/hypr/hyprland.lua")

hl.monitor({
  output = "HEADLESS-2",
  mode = os.getenv("OHMARCHY_DISPLAY_MODE") or "2880x1920@60",
  position = "0x0",
  scale = tonumber(os.getenv("OHMARCHY_DISPLAY_SCALE") or "1.5"),
})

hl.on("hyprland.start", function()
  hl.exec_cmd("hyprctl output create headless HEADLESS-2 && sleep 1 && exec wayvnc -o HEADLESS-2 127.0.0.1 5900")
end)
