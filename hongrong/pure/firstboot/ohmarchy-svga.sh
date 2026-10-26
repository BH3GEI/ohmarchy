# /etc/profile.d/ohmarchy-svga.sh: on route B's SVGA device (vmwgfx), Omarchy's
# shell (Quickshell: wallpaper, top bar, notifications) created its layers but
# drew them black on SVGA3D, so the desktop had no wallpaper and no bar. Qt
# Quick's software renderer draws them on the CPU. tty1's login shell reads
# this, and uwsm passes it on to Hyprland and the shell it starts. 鸿融's
# virtio-gpu (virgl) keeps GPU rendering. Verified 2026-10-27 in OSEasy:
# after a reboot, wallpaper, bar and notifications are drawn.
for d in /sys/class/drm/card*/device/driver; do
  case $(readlink "$d" 2>/dev/null) in
    */vmwgfx) export QT_QUICK_BACKEND=software; break ;;
  esac
done
unset d
