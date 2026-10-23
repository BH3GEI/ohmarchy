#!/system/bin/sh
# Native Arch Linux ARM session on the HongMeng kernel (run as root on the host).
#   arch.sh start            mount arch.img once in a private mount+pid namespace
#   arch.sh status           session pid, loop devices, mount count
#   arch.sh run FILE [ARG..] run a bash script in the session as root; a FILE on
#                            the host is copied in first (with an etc/ next to it)
#   arch.sh stop             sync, kill the session, detach its loop device
# The image is only ever mounted by the session process, never twice.
B=${ARCH_BASE:-$(cd "$(dirname "$0")" && pwd)}
IMG=$B/arch.img
R=$B/arch
PIDF=$B/session.pid

alive() {
    [ -f "$PIDF" ] && P=$(cat "$PIDF") && [ -d "/proc/$P" ] &&
        tr '\0' ' ' < "/proc/$P/cmdline" | grep -q -e 'arch.sh _session' -e 'catatonit' -e 'arch-init'
}

# losetup -a only lists /dev/loopN nodes; ask each /dev/block/loopN instead.
attached() {
    for d in /dev/block/loop*; do
        losetup "$d" 2>/dev/null | grep -qF "($IMG)" && return 0
    done
    return 1
}

case "$1" in
start)
    if alive; then echo "already running: $P"; exit 0; fi
    [ -f "$IMG" ] || { echo "no image at $IMG"; exit 1; }
    if attached; then echo "refusing: $IMG is attached to a loop already"; exit 1; fi
    rm -f "$PIDF"
    mkdir -p "$R"
    nohup unshare -m -p -f sh "$0" _session < /dev/null > "$B/session.log" 2>&1 &
    i=0; while [ $i -lt 30 ] && ! alive; do sleep 1; i=$((i+1)); done
    alive && echo "started: $P" || { echo "failed to start"; cat "$B/session.log"; exit 1; }
    ;;
_session)
    set -e
    # toybox mount -o loop fails (EFAULT); attach a loop by hand. losetup -f
    # names /dev/loopN, but only loop0 has a node there; all are in /dev/block.
    # Attaching a busy loop fails with EBUSY, so take the first that works.
    n=0
    until losetup "/dev/block/loop$n" "$IMG" 2>/dev/null; do
        n=$((n+1)); [ -b "/dev/block/loop$n" ] || { echo "no free loop device"; exit 1; }
    done
    L=/dev/block/loop$n
    mount -t ext4 "$L" "$R"
    mount -t proc proc "$R/proc"
    mount -o bind,ro /sys "$R/sys"
    # Minimal /dev: HongMeng cannot bind a device node onto a file, so mknod.
    mount -t tmpfs -o mode=755,nosuid tmpfs "$R/dev"
    mknod -m 666 "$R/dev/null" c 1 3
    mknod -m 666 "$R/dev/zero" c 1 5
    mknod -m 666 "$R/dev/full" c 1 7
    mknod -m 666 "$R/dev/random" c 1 8
    mknod -m 666 "$R/dev/urandom" c 1 9
    mknod -m 666 "$R/dev/tty" c 5 0
    # mknod -m is masked by umask here; set modes explicitly.
    chmod 666 "$R/dev/null" "$R/dev/zero" "$R/dev/full" "$R/dev/random" "$R/dev/urandom" "$R/dev/tty"
    mkdir -p "$R/dev/pts" "$R/dev/shm"
    mount -t devpts -o newinstance,ptmxmode=0666 devpts "$R/dev/pts" 2>/dev/null \
        || mount -o bind /dev/pts "$R/dev/pts"
    # HongMeng's devpts has no pts/ptmx; use the classic node.
    mknod "$R/dev/ptmx" c 5 2 && chmod 666 "$R/dev/ptmx"
    mount -t tmpfs -o mode=1777,nosuid,nodev tmpfs "$R/dev/shm"
    ln -sf /proc/self/fd "$R/dev/fd"
    ln -sf /proc/self/fd/0 "$R/dev/stdin"
    ln -sf /proc/self/fd/1 "$R/dev/stdout"
    ln -sf /proc/self/fd/2 "$R/dev/stderr"
    mount -t tmpfs -o mode=1777 tmpfs "$R/tmp"
    mount -t tmpfs -o mode=755 tmpfs "$R/run"
    set +e
    echo "session up on $L"
    echo "$L" > "$B/session.loop"
    # Host pid of this shell (/proc here is still the host's procfs).
    cut -d' ' -f4 /proc/self/stat > "$PIDF"
    # catatonit as pid 1 reaps orphans. Before it is installed (first setup),
    # a bash loop holds the namespace. env -i: nothing of the host's
    # environment goes into the session.
    [ -x "$R/usr/bin/catatonit" ] && exec chroot "$R" /usr/bin/env -i /usr/bin/catatonit -P
    exec chroot "$R" /usr/bin/env -i /usr/bin/bash -c 'exec -a arch-init bash -c "while :; do sleep 3600; done"'
    ;;
run)
    alive || { echo "not running"; exit 1; }
    shift; f=$1; shift
    if [ -f "$f" ]; then
        d=/tmp/arch-run.$$
        mkdir -p "/proc/$P/root$d"
        cp "$f" "/proc/$P/root$d/"
        [ -d "$(dirname "$f")/etc" ] && cp -r "$(dirname "$f")/etc" "/proc/$P/root$d/"
        f=$d/$(basename "$f")
    fi
    # toybox nsenter parses options anywhere on the line: without -- it takes
    # env's -i as its own and the host environment leaks in.
    exec nsenter -t "$P" -m -p -- chroot "$R" /usr/bin/env -i HOME=/root \
        TERM=xterm-256color LANG=C.UTF-8 PATH=/usr/local/sbin:/usr/local/bin:/usr/bin \
        /usr/bin/bash "$f" "$@"
    ;;
status)
    alive && echo "running: $P" || echo "stopped"
    attached && echo "image attached: $(cat "$B/session.loop" 2>/dev/null)" || echo "image not attached"
    ;;
stop)
    alive || { echo "not running"; exit 0; }
    nsenter -t "$P" -m sync
    # pid-namespace init ignores SIGTERM from outside; SIGKILL tears the namespace down.
    kill -9 "$P"
    i=0; while [ $i -lt 20 ] && [ -d "/proc/$P" ]; do sleep 1; i=$((i+1)); done
    rm -f "$PIDF"
    sleep 1
    # The namespace teardown unmounts the image but leaves the loop bound.
    L=$(cat "$B/session.loop" 2>/dev/null)
    if [ -n "$L" ] && losetup "$L" 2>/dev/null | grep -qF "($IMG)"; then
        losetup -d "$L" 2>/dev/null
    fi
    rm -f "$B/session.loop"
    attached && echo "warning: $IMG still attached" || echo "stopped"
    ;;
*)
    echo "usage: $0 start|status|run FILE [ARG..]|stop"; exit 1 ;;
esac
