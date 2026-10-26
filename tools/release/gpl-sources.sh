#!/bin/bash
# gpl-sources.sh: the complete sources (makepkg --allsource) of every GPL or LGPL
# package in an image, at the image's exact versions, for a release
# (GPLv2 section 3: the binaries come with their source; supervisor, 2026-10-26).
# Runs as an ordinary user on an Arch/ALARM system with base-devel and git
# (route D's session will do); needs network.
#   tools/release/gpl-sources.sh PKGLIST OUTDIR
# PKGLIST is pkglist.sh's output. Per package base, the build files come from
# Arch Linux ARM's PKGBUILDs when ALARM carries the package at that version
# (its own builds), otherwise from Arch's packaging repository at the tag of
# that version. OUTDIR gets PKGBASE-VERSION.src.tar.gz each, MISSING.txt for
# what could not be fetched (to be resolved by hand before publishing) and
# PACKAGES.txt (package, version, licenses, where the build files came from).
#   JOBS=6 tools/release/gpl-sources.sh PKGLIST OUTDIR   in parallel
set -uo pipefail
list=${1:?pkglist} out=${2:?outdir}
# JOBS=N: N workers on interleaved shares of the list (most time is waiting on
# slow hosts), each into OUTDIR/part-K, merged into OUTDIR at the end
if [ "${JOBS:-1}" -gt 1 ] && [ -z "${GPL_SOURCES_WORKER:-}" ]; then
    mkdir -p "$out"
    for k in $(seq 1 "$JOBS"); do
        awk -v n="$JOBS" -v k="$k" 'NR % n == k % n' "$list" > "$out/list-$k"
        GPL_SOURCES_WORKER=1 bash "$0" "$out/list-$k" "$out/part-$k" > "$out/part-$k.log" 2>&1 &
    done
    wait
    : > "$out/PACKAGES.txt"; : > "$out/MISSING.txt"
    for k in $(seq 1 "$JOBS"); do
        cat "$out/part-$k/PACKAGES.txt" >> "$out/PACKAGES.txt"; cat "$out/part-$k/MISSING.txt" >> "$out/MISSING.txt"
        mv "$out/part-$k"/*.src.tar.gz "$out/" 2>/dev/null
        rm -rf "$out/part-$k" "$out/list-$k"
    done
    echo "$(wc -l < "$out/PACKAGES.txt") package bases with source, $(wc -l < "$out/MISSING.txt") missing (MISSING.txt)"
    exit 0
fi
mkdir -p "$out"; out=$(cd "$out" && pwd)
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
# GitHub often does not answer from here (connects time out after ~2 min):
# for this run only, git and makepkg's downloads go to github.com through
# gh-proxy.com (the user's own git and makepkg settings stay as they are)
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=url.https://gh-proxy.com/https://github.com/.insteadOf \
       GIT_CONFIG_VALUE_0=https://github.com/
cat > "$work/dl" <<'DL'
#!/bin/bash
# makepkg DLAGENT: curl, with github.com through gh-proxy
out=$1 url=$2
case $url in https://github.com/* | https://codeload.github.com/* | https://objects.githubusercontent.com/*) url=https://gh-proxy.com/$url ;; esac
exec /usr/bin/curl -qgb "" -fLC - --retry 3 --retry-delay 3 -o "$out" "$url"
DL
chmod +x "$work/dl"
{ cat /etc/makepkg.conf
  echo "DLAGENTS=('file::/usr/bin/curl -qgC - -o %o %u' 'ftp::/usr/bin/curl -qgfC - --ftp-pasv --retry 3 --retry-delay 3 -o %o %u'"
  echo "          'http::/usr/bin/curl -qgb \"\" -fLC - --retry 3 --retry-delay 3 -o %o %u' 'https::$work/dl %o %u'"
  echo "          'rsync::/usr/bin/rsync --no-motd -z %u %o' 'scp::/usr/bin/scp -C %u %o')"; } > "$work/makepkg.conf"
export MAKEPKG_CONF=$work/makepkg.conf
# a rerun keeps the archives already made (also a worker's, JOBS being the
# same: same shares) and their PACKAGES.txt lines
cp "$out/PACKAGES.txt" "$work/prev" 2>/dev/null || : > "$work/prev"
: > "$out/MISSING.txt"; : > "$out/PACKAGES.txt"
# ALARM's tree without file contents (a full clone takes many minutes here); the
# directories of the packages asked for are fetched as they are needed
alarm=$work/alarm
# (GitHub is not always reachable from here; gh-proxy.com as the fallback)
# Every git gets `timeout -s KILL`: on the HarmonyOS host a git fetch once spun
# for hours at 90% CPU and plain `timeout` (TERM) did not end it
for u in https://github.com/archlinuxarm/PKGBUILDs https://gh-proxy.com/https://github.com/archlinuxarm/PKGBUILDs; do
    timeout -s KILL 300 git clone -q --depth 1 --filter=blob:none --sparse "$u" "$alarm" && break
    rm -rf "$alarm"
done
[ -d "$alarm" ] || { echo "no ALARM PKGBUILDs" >&2; exit 1; }

# GPL-2.0-only, GPL-3.0-or-later, LGPL-2.1, AGPL, and the old names GPL2, LGPL3, ...
gpl() { grep -q -i -E '(^| )(A|L)?GPL' <<< "$1"; }

# snapshot DIR OUT LOG: DIR's build files (no VCS checkouts) plus, for each
# git+URL source of its PKGBUILD, URL at its #commit=/#tag= ref as a tarball;
# an unpinned source at the current HEAD, its commit noted in LOG (the build's
# exact one cannot be known). Plain sources are downloaded as makepkg would.
snapshot() {
    local dir=$1 out=$2 log=$3 t
    : > "$log"
    t=$(mktemp -d) || return 1
    mkdir -p "$t/s"
    # only the packaging repo's own files: a failed makepkg leaves bare clones here
    (cd "$dir" && { git ls-files 2>/dev/null || find . -maxdepth 1 -type f -printf '%P\n'; } |
        while read -r x; do mkdir -p "$t/s/$(dirname "$x")" && cp "$x" "$t/s/$x"; done)
    (cd "$dir" && bash -c '. ./PKGBUILD >/dev/null 2>&1; printf "%s\n" "${source[@]}"') > "$t/srcs"
    while read -r sr; do
        local nm=${sr%%::*} u=${sr#*::}
        [ "$nm" = "$sr" ] && nm=
        case $u in
        git+*)
            u=${u#git+}; local ref=${u#*#} url=${u%%#*} r=HEAD
            url=${url%%\?*}; ref=${ref%%\?*}   # "?signed": a verification hint, not part of the URL
            case $ref in commit=*) r=${ref#commit=} ;; tag=*) r=${ref#tag=} ;; branch=*) r=${ref#branch=} ;; esac
            [ "$ref" = "$u" ] && r=HEAD
            local repo; repo=$(basename "${url%.git}"); nm=${nm:-$repo}
            local g="$t/g-$nm" ok=
            git init -q "$g" && git -C "$g" remote add o "$url" &&
                { timeout -s KILL 300 git -C "$g" fetch -q --depth 1 o "$r" 2>/dev/null ||
                  timeout -s KILL 300 git -C "$g" fetch -q --depth 1 o "$r" 2>/dev/null; } &&   # one retry: slow hosts
                git -C "$g" archive --prefix="$nm/" -o "$t/s/$nm-$(git -C "$g" rev-parse --short FETCH_HEAD).tar.gz" FETCH_HEAD &&
                ok=$(git -C "$g" rev-parse --short FETCH_HEAD)
            local m=${GIT_MIRROR[$repo]:-}
            if [ -z "$ok" ] && [ -n "$m" ]; then  # a mirror (GitHub, through gh-proxy)
                rm -rf "$g"; git init -q "$g" && git -C "$g" remote add o "https://gh-proxy.com/$m" &&
                    timeout -s KILL 900 git -C "$g" fetch -q --depth 1 o "$r" 2>/dev/null &&
                    git -C "$g" archive --prefix="$nm/" -o "$t/s/$nm-$(git -C "$g" rev-parse --short FETCH_HEAD).tar.gz" FETCH_HEAD &&
                    ok=$(git -C "$g" rev-parse --short FETCH_HEAD) && echo "$nm from mirror $m" >> "$log"
            fi
            if [ -z "$ok" ]; then  # hosts' snapshot URLs
                local sn= sr=$r
                [ "$r" = HEAD ] && sr=master   # snapshot URLs want a branch name
                case $url in
                *savannah.gnu.org*) sn="https://git.savannah.gnu.org/cgit/$repo.git/snapshot/$repo-$sr.tar.gz" ;;
                *github.com*) sn="https://gh-proxy.com/${url%.git}/archive/$sr.tar.gz" ;;
                *sourceware.org/git/*) sn="https://sourceware.org/git/?p=$repo.git;a=snapshot;h=$sr;sf=tgz" ;;
                *gitlab.*) sn="${url%.git}/-/archive/$sr/$repo-$sr.tar.gz" ;;
                esac
                [ -n "$sn" ] && curl -fsSL --retry 2 -m 900 -o "$t/s/$nm-$sr.tar.gz" "$sn" && ok=$sr
            fi
            if [ -z "$ok" ] && [ "$r" != HEAD ]; then
                # a release tag: the upstream release tarball of that version
                # (GNU mirror at TUNA, savannah's download area)
                local v=${r#v}; v=${v#"$repo"-}; local tb
                for tb in "https://mirrors.tuna.tsinghua.edu.cn/gnu/$repo/$repo-$v.tar.xz" \
                          "https://mirrors.tuna.tsinghua.edu.cn/gnu/$repo/$repo-$v.tar.gz" \
                          "https://download.savannah.nongnu.org/releases/$repo/$repo-$v.tar.xz" \
                          "https://download.savannah.nongnu.org/releases/$repo/$repo-$v.tar.gz"; do
                    curl -fsSL --retry 2 -m 900 -o "$t/s/$(basename "$tb")" "$tb" 2>/dev/null &&
                        { ok="release $v"; echo "$nm: upstream release tarball $(basename "$tb") for tag $r" >> "$log"; break; }
                    rm -f "$t/s/$(basename "$tb")"
                done
            fi
            [ -n "$ok" ] || { echo "$nm: no snapshot of $url $r" >> "$log"; rm -rf "$t"; return 1; }
            [ "$r" = HEAD ] && echo "$nm unpinned, HEAD $ok" >> "$log" || echo "$nm $r" >> "$log"
            ;;
        http://* | https://* | ftp://*)
            local fn=${nm:-$(basename "$u")}
            "$work/dl" "$t/s/$fn" "$u" > /dev/null 2>&1 || { echo "$fn: download failed" >> "$log"; rm -rf "$t"; return 1; } ;;
        esac
    done < "$t/srcs"
    tar -C "$t" -czf "$out" --transform "s|^s|$(basename "$dir")|" s && rm -rf "$t"
}

# git sources whose own host does not serve a shallow fetch or snapshot here
# (savannah's cgit snapshots answer 301/400; its gnulib fetch times out)
declare -A GIT_MIRROR=([gnulib]=https://github.com/coreutils/gnulib [gcc]=https://github.com/gcc-mirror/gcc
                       [glibc]=https://github.com/bminor/glibc [binutils-gdb]=https://github.com/bminor/binutils-gdb)

declare -A done=()
min_free=${MIN_FREE_GB:-8}   # stop before the disk fills up (sources can be large)
while IFS='|' read -r name ver base lic; do
    gpl "$lic" || continue
    if [ "$(df -Pk "$out" | awk 'NR==2{print int($4/1048576)}')" -lt "$min_free" ]; then
        echo "$name|$ver|$lic|not fetched: less than ${min_free} GB free on $out" >> "$out/MISSING.txt"; continue
    fi
    [ -n "${done[$base]:-}" ] && continue
    done[$base]=1
    f=$out/$base-$ver.src.tar.gz
    if [ -s "$f" ]; then
        l=$(awk -F'|' -v n="$name" -v v="$ver" '$1 == n && $2 == v { print; exit }' "$work/prev")
        echo "${l:-$name|$ver|$lic|(kept)}" >> "$out/PACKAGES.txt"
        continue
    fi
    d=$work/$base src=
    # ALARM's own build of this version?
    for r in core extra alarm aur; do
        p=$alarm/$r/$base/PKGBUILD
        git -C "$alarm" cat-file -e "HEAD:$r/$base/PKGBUILD" 2>/dev/null || continue
        git -C "$alarm" sparse-checkout add "$r/$base" 2>/dev/null
        v=$(cd "$(dirname "$p")" && bash -c '. ./PKGBUILD >/dev/null 2>&1; echo "${epoch:+$epoch:}$pkgver-$pkgrel"')
        [ "$v" = "$ver" ] && { cp -r "$(dirname "$p")" "$d"; src="archlinuxarm/PKGBUILDs $r/$base"; break; }
    done
    if [ -z "$src" ]; then  # Arch's packaging repo, tag = version with ':' as '-'
        tag=${ver//:/-}
        git clone -q --depth 1 --branch "$tag" \
            "https://gitlab.archlinux.org/archlinux/packaging/packages/$base.git" "$d" 2>/dev/null &&
            src="gitlab.archlinux.org packages/$base tag $tag"
    fi
    if [ -z "$src" ]; then
        echo "$name|$ver|$lic|no build files at this version" >> "$out/MISSING.txt"; continue
    fi
    # --allsource: PKGBUILD, local files and every downloaded source in one archive;
    # with git sources it would clone whole repositories (libtool: gnulib, slow and
    # failing here), so those go straight to snapshots of their pinned refs
    : > "$work/$base.log"
    if ! grep -q 'git+' "$d/PKGBUILD" &&
        (cd "$d" && makepkg --allsource --skippgpcheck --nocheck > "$work/$base.log" 2>&1); then
        mv "$d"/*.src.tar.gz "$f"
        echo "$name|$ver|$lic|$src" >> "$out/PACKAGES.txt"
        echo "  $base $ver ($src)"
    elif snapshot "$d" "$f" "$work/$base.snap.log"; then
        # git sources too big or slow to clone whole here (libtool's gnulib):
        # the build files plus a snapshot of each git source at its pinned ref
        echo "$name|$ver|$lic|$src; git sources as snapshots ($(tr '\n' ' ' < "$work/$base.snap.log"))" >> "$out/PACKAGES.txt"
        echo "  $base $ver ($src, git snapshots)"
    else
        echo "$name|$ver|$lic|makepkg --allsource failed: $(tail -1 "$work/$base.log"); snapshot: $(tail -1 "$work/$base.snap.log")" >> "$out/MISSING.txt"
    fi
done < "$list"
echo "$(wc -l < "$out/PACKAGES.txt") package bases with source, $(wc -l < "$out/MISSING.txt") missing (MISSING.txt)"
