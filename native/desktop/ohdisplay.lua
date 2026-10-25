-- Entry for the native HarmonyOS display (ohmarchy-desktop): Omarchy's config plus
-- the headless output the display app shows. Defaults to 1920x1280 at scale 1, which
-- the app scales up to the window: every frame is read back from the GPU, so pixels
-- cost time. OHMARCHY_DISPLAY_MODE=2880x1920@60 OHMARCHY_DISPLAY_SCALE=1.5 is the
-- panel's own resolution: sharper, about half the frame rate.
dofile(os.getenv("HOME") .. "/.config/hypr/hyprland.lua")

hl.monitor({
  output = "HEADLESS-2",
  mode = os.getenv("OHMARCHY_DISPLAY_MODE") or "1920x1280@120",
  position = "0x0",
  scale = tonumber(os.getenv("OHMARCHY_DISPLAY_SCALE") or "1"),
})

-- Repaint the whole output on any change. With per-region damage (the default, 2),
-- regions not repainted in a frame keep stale pixels on screen: after the Omarchy
-- menu closed and a window opened, the menu stayed drawn over the terminal until the
-- next full repaint (rehearsal 2026-10-26). Buffer contents apparently don't survive
-- the swapchain on the app's present path; until that is found, full frames.
hl.config({ debug = { damage_tracking = 1 } })

-- Route D's replacements for a few Omarchy commands (/opt/ohmarchy/overrides, e.g.
-- omarchy-launch-webapp: web apps in Firefox, which can sandbox itself here).
-- Omarchy puts its own bin directory first in the apps' PATH; this goes before it.
hl.env("PATH", "/opt/ohmarchy/overrides:" .. (os.getenv("OMARCHY_PATH") or "/usr/share/omarchy") .. "/bin:"
  .. (os.getenv("PATH") or "/usr/local/bin:/usr/bin"))

-- Without systemd, environment.d is not applied: read Omarchy's and the user's.
for _, dir in ipairs({ "/usr/share/omarchy/default/environment.d", os.getenv("HOME") .. "/.config/environment.d" }) do
  local list = io.popen("ls " .. dir .. "/*.conf 2>/dev/null")
  for file in list:lines() do
    for line in io.lines(file) do
      local k, v = line:match("^%s*([%w_]+)=(.*)$")
      if k then hl.env(k, v) end
    end
  end
  list:close()
end

-- Input method: fcitx5 (Omarchy's; its systemd unit does not run here), or with
-- OHMARCHY_IME=harmony the HarmonyOS IME through the display app and ohime.
local harmonyIme = os.getenv("OHMARCHY_IME") == "harmony"
if harmonyIme then
  hl.env("QT_IM_MODULE", "wayland")
end

-- The display app gets frames and sends input over aquamarine's export socket
-- (AQ_HEADLESS_EXPORT), so nothing captures the screen.
hl.on("hyprland.start", function()
  hl.exec_cmd("hyprctl output create headless HEADLESS-2")
  hl.exec_cmd(harmonyIme and "ohime" or "fcitx5 -d --disable notificationitem")
end)
