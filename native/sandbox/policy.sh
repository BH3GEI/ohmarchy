# Sourced by ohm-sandbox: the sandbox's policy (policy.conf, format and meaning in
# policy.conf.default). Read line by line and matched strictly; nothing in the file
# is ever evaluated. Without the file: the defaults. Anything wrong in it: the whole
# file is rejected and the strictest policy applies (no network), never part of it.
# After policy_load:
#   POL_SOURCE   default | file | rejected     POL_REASON  why rejected
#   POL_NET      pasta | off | host            POL_ALLOW   extra abstract prefixes
#   POL_SHARES   lines "host inside ro|rw"     POL_KEEP / POL_DROPX  capability names
#   POL_DEV      device names (fuse net/tun)

# the capability bounding set dropped by default, by name (ohm-sandbox's DROP)
POL_BASE_DROP="mknod sys_admin sys_module sys_rawio sys_boot sys_time sys_pacct sys_tty_config mac_override mac_admin syslog net_admin audit_control audit_read wake_alarm block_suspend linux_immutable bpf perfmon checkpoint_restore setpcap"
POL_KEEPABLE="net_admin syslog sys_tty_config linux_immutable perfmon checkpoint_restore wake_alarm block_suspend audit_read"
POL_DEVS="fuse net/tun"

cap_num() {
    case "$1" in
    chown) echo 0;; dac_override) echo 1;; dac_read_search) echo 2;; fowner) echo 3;;
    fsetid) echo 4;; kill) echo 5;; setgid) echo 6;; setuid) echo 7;; setpcap) echo 8;;
    linux_immutable) echo 9;; net_bind_service) echo 10;; net_broadcast) echo 11;;
    net_admin) echo 12;; net_raw) echo 13;; ipc_lock) echo 14;; ipc_owner) echo 15;;
    sys_module) echo 16;; sys_rawio) echo 17;; sys_chroot) echo 18;; sys_ptrace) echo 19;;
    sys_pacct) echo 20;; sys_admin) echo 21;; sys_boot) echo 22;; sys_nice) echo 23;;
    sys_resource) echo 24;; sys_time) echo 25;; sys_tty_config) echo 26;; mknod) echo 27;;
    lease) echo 28;; audit_write) echo 29;; audit_control) echo 30;; setfcap) echo 31;;
    mac_override) echo 32;; mac_admin) echo 33;; syslog) echo 34;; wake_alarm) echo 35;;
    block_suspend) echo 36;; audit_read) echo 37;; perfmon) echo 38;; bpf) echo 39;;
    checkpoint_restore) echo 40;;
    *) return 1;;
    esac
}

in_list() {  # word list...
    w=$1; shift
    for x in $*; do [ "$x" = "$w" ] && return 0; done
    return 1
}

policy_defaults() {
    POL_NET=pasta; POL_ALLOW=; POL_SHARES=; POL_KEEP=; POL_DROPX=; POL_DEV=
}

# a host path or path inside: absolute, plain characters, no "..", no "//"
pol_path_ok() {
    case "$1" in
    /*) ;;
    *) return 1;;
    esac
    case "$1" in
    *..*|*//*|*[!A-Za-z0-9._/@+-]*) return 1;;
    esac
    return 0
}

pol_share_ok() {  # host inside mode
    pol_path_ok "$1" && pol_path_ok "$2" || { echo "share: paths must be absolute, plain, without .."; return 1; }
    case "$3" in ro|rw) ;; *) echo "share: the mode is ro or rw"; return 1;; esac
    h=${1%/}; i=${2%/}
    case "$h" in
    ""|/dev|/dev/*|/proc|/proc/*|/sys|/sys/*|/system|/system/*|/vendor|/vendor/*|/data|$S|$S/*)
        echo "share: $1 may not be shared"; return 1;;
    esac
    case "$i" in
    ""|/proc|/proc/*|/sys|/sys/*|/dev|/dev/*|/run|/run/*|/tmp|/tmp/*|/usr|/usr/*|/etc|/etc/*)
        echo "share: not inside at $2"; return 1;;
    esac
    [ -d "$h" ] || { echo "share: $1 is not a folder on the host"; return 1; }
    return 0
}

# parse $1 into POL_*; on error: echo the reason, return 1
pol_parse() {
    policy_defaults
    seen=" "
    n=0
    while IFS= read -r line || [ -n "$line" ]; do
        n=$((n + 1))
        line=${line%%#*}
        set -f; set -- $line; set +f
        [ $# -eq 0 ] && continue
        [ "$2" = "=" ] || { echo "line $n: expected key = value"; return 1; }
        k=$1; shift 2
        case "$k" in
        share) ;;
        network|abstract_allow|cap_keep|cap_drop_extra|dev)
            case "$seen" in *" $k "*) echo "line $n: $k given twice"; return 1;; esac
            seen="$seen$k ";;
        *) echo "line $n: unknown key $k"; return 1;;
        esac
        case "$k" in
        network)
            [ $# -eq 1 ] && in_list "$1" pasta off host || { echo "line $n: network is pasta, off or host"; return 1; }
            POL_NET=$1;;
        abstract_allow)
            for p in "$@"; do
                case "$p" in *[!A-Za-z0-9._/-]*) echo "line $n: abstract_allow: bad prefix $p"; return 1;; esac
            done
            POL_ALLOW="$*";;
        share)
            [ $# -eq 3 ] || { echo "line $n: share = HOST_PATH PATH_INSIDE ro|rw"; return 1; }
            r=$(pol_share_ok "$1" "$2" "$3") || { echo "line $n: $r"; return 1; }
            POL_SHARES="$POL_SHARES$1 $2 $3
";;
        cap_keep)
            for c in "$@"; do
                in_list "$c" $POL_KEEPABLE || { echo "line $n: cap_keep: $c may not be kept"; return 1; }
            done
            POL_KEEP="$*";;
        cap_drop_extra)
            for c in "$@"; do
                cap_num "$c" > /dev/null || { echo "line $n: cap_drop_extra: no capability $c"; return 1; }
            done
            POL_DROPX="$*";;
        dev)
            for d in "$@"; do
                in_list "$d" $POL_DEVS || { echo "line $n: dev: $d is not one of $POL_DEVS"; return 1; }
            done
            POL_DEV="$*";;
        esac
    done < "$1"
    if [ "$POL_NET" = host ] && in_list net/tun $POL_DEV; then
        echo "dev: net/tun is not allowed with network = host"; return 1
    fi
    return 0
}

policy_load() {
    POL_REASON=
    if [ ! -f "$S/policy.conf" ]; then
        policy_defaults; POL_SOURCE=default
    elif POL_REASON=$(pol_parse "$S/policy.conf") && pol_parse "$S/policy.conf" > /dev/null; then
        POL_SOURCE=file
    else
        policy_defaults; POL_NET=off; POL_SOURCE=rejected
    fi
}

# the bounding set to drop, by number (for ohm-capdrop)
policy_drop() {
    out=
    for c in $POL_BASE_DROP $POL_DROPX; do
        in_list "$c" $POL_KEEP && continue
        nn=$(cap_num "$c")
        in_list "$nn" $(echo "$out" | tr , ' ') || out="$out${out:+,}$nn"
    done
    echo "$out"
}

# one line per thing looser than the default
policy_relaxations() {
    [ "$POL_NET" = host ] && echo "network relaxed to host (the host's 127.0.0.1 reachable)"
    [ -n "$POL_ALLOW" ] && echo "abstract_allow relaxed: $POL_ALLOW"
    printf '%s' "$POL_SHARES" | while read -r h i m; do
        [ -n "$h" ] && echo "share relaxed: $h -> $i $m"
    done
    for c in $POL_KEEP; do echo "cap relaxed: keep $c"; done
    for d in $POL_DEV; do echo "dev relaxed: $d"; done
}

# into the helper's log (and the start output)
policy_log() {
    t=$(date '+%F %T')
    case "$POL_SOURCE" in
    rejected) echo "$t policy.conf rejected ($POL_REASON); strictest policy used (network off)" | tee -a "$S/sandboxd.log";;
    default) echo "$t policy: defaults (no policy.conf)" >> "$S/sandboxd.log";;
    esac
    policy_relaxations | while IFS= read -r l; do echo "$t $l"; done | tee -a "$S/sandboxd.log"
}

# ohm-sandbox policy check: what the next start will apply, in plain words
policy_check() {
    policy_load
    nrel=$(policy_relaxations | grep -c .)
    case "$POL_SOURCE" in
    rejected) echo "当前：配置文件无效，下次启动按最严执行（不联网）。原因：$POL_REASON";;
    default)  echo "当前：没有 policy.conf，按默认执行（默认就是推荐的安全设置）。";;
    file)     [ "$nrel" -eq 0 ] && echo "当前：按配置文件执行，和默认一样，没有放宽。" ||
                  echo "当前：按配置文件执行，比默认放宽了 $nrel 项（下面标 ! 的）。";;
    esac
    echo
    case "$POL_NET" in
    pasta) echo "  网络      pasta     [硬] 能上网；连不到本机 127.0.0.1 上的服务；不对外开放端口。";;
    off)   echo "  网络      off       [硬] 不联网，只有沙箱自己的回环。";;
    host)  echo "! 网络      host      [硬] HIGH RISK：和本机共用网络，沙箱能连到本机 127.0.0.1 上的所有服务。";;
    esac
    if [ -z "$POL_SHARES" ]; then
        echo "  共享目录  无        [硬] 看不到本机任何文件。"
    else
        printf '%s' "$POL_SHARES" | while read -r h i m; do
            [ "$m" = ro ] && w="能读不能改" || w="能读也能改"
            echo "! 共享目录  $h -> $i ($m)  [硬] 沙箱里的 root ${w}这个目录里的所有文件。"
        done
    fi
    names=
    for c in $POL_BASE_DROP $POL_DROPX; do
        in_list "$c" $POL_KEEP $names || names="$names${names:+ }$c"
    done
    echo "  能力      去掉 $(echo $names | wc -w | tr -d ' ') 项：$names"
    echo "            [硬] 沙箱里的 root 不能挂载、加载内核模块、建设备节点、改 MAC。"
    for c in $POL_KEEP; do echo "! 能力      保留 $c  [硬] 比默认多一项权限。"; done
    [ -n "$POL_DROPX" ] && echo "  能力      额外去掉 $POL_DROPX  [硬] 比默认更严。"
    echo "  /dev      null zero full random urandom tty ptmx dma_heap${POL_DEV:+ $POL_DEV}  [硬]"
    for d in $POL_DEV; do echo "! /dev      $d  [硬] 比默认多一个设备。"; done
    echo "  抽象 socket  只放行 ohmsbx- 和沙箱里自己绑定的${POL_ALLOW:+，另加 $POL_ALLOW}  [软] 尽力而为，不是安全边界：静态程序和沙箱里的 root 能绕过。"
    [ -n "$POL_ALLOW" ] && echo "! 抽象 socket  放行 $POL_ALLOW  [软]"
    echo
    echo "改动在下次启动 Linux（下次打开 app）时生效；Reset Linux 不会改这个文件。"
    if [ -f "$S/run/policy.effective" ] && [ -f "$PIDF" ]; then
        now=$(policy_summary)
        [ "$now" = "$(cat "$S/run/policy.effective")" ] || echo "注意：正在运行的 Linux 用的还是上次启动时的设置，和上面不同；下次启动才生效。"
    fi
    [ "$POL_SOURCE" = rejected ] && return 1
    return 0
}

# a one-line digest of the policy, kept with the running sandbox
policy_summary() {
    echo "net=$POL_NET allow=$POL_ALLOW drop=$(policy_drop) dev=$POL_DEV shares=$(printf '%s' "$POL_SHARES" | tr '\n' ';')"
}
