# /etc/profile.d/ohmarchy-ram.sh: Omarchy in RAM (route E) draws on the UEFI
# framebuffer through efidrm/simpledrm, without a GPU: everything renders on the
# CPU (Mesa llvmpipe); Qt Quick's own software renderer for Quickshell.
for d in /sys/class/drm/card*/device/driver; do
  case $(readlink "$d" 2>/dev/null) in
    */efidrm|*/simpledrm) export QT_QUICK_BACKEND=software LIBGL_ALWAYS_SOFTWARE=1; break ;;
  esac
done
unset d
