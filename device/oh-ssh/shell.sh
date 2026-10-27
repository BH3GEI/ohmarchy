#!/system/bin/sh
# ohsshd login shell: load /etc/profile, then hand off to the real sh
[ -r /etc/profile ] && . /etc/profile
exec /system/bin/sh "$@"
