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
set -uo pipefail
list=${1:?pkglist} out=${2:?outdir}
mkdir -p "$out"; out=$(cd "$out" && pwd)
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
: > "$out/MISSING.txt"; : > "$out/PACKAGES.txt"
# ALARM's tree without file contents (a full clone takes many minutes here); the
# directories of the packages asked for are fetched as they are needed
alarm=$work/alarm
# (GitHub is not always reachable from here; gh-proxy.com as the fallback)
for u in https://github.com/archlinuxarm/PKGBUILDs https://gh-proxy.com/https://github.com/archlinuxarm/PKGBUILDs; do
    timeout 300 git clone -q --depth 1 --filter=blob:none --sparse "$u" "$alarm" && break
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
            case $ref in commit=*) r=${ref#commit=} ;; tag=*) r=${ref#tag=} ;; branch=*) r=${ref#branch=} ;; esac
            [ "$ref" = "$u" ] && r=HEAD
            local repo; repo=$(basename "${url%.git}"); nm=${nm:-$repo}
            local g="$t/g-$nm" ok=
            git init -q "$g" && git -C "$g" remote add o "$url" &&
                timeout 600 git -C "$g" fetch -q --depth 1 o "$r" 2>/dev/null &&
                git -C "$g" archive --prefix="$nm/" -o "$t/s/$nm-$(git -C "$g" rev-parse --short FETCH_HEAD).tar.gz" FETCH_HEAD &&
                ok=$(git -C "$g" rev-parse --short FETCH_HEAD)
            local m=${GIT_MIRROR[$repo]:-}
            if [ -z "$ok" ] && [ -n "$m" ]; then  # a mirror (GitHub, through gh-proxy)
                rm -rf "$g"; git init -q "$g" && git -C "$g" remote add o "https://gh-proxy.com/$m" &&
                    timeout 900 git -C "$g" fetch -q --depth 1 o "$r" 2>/dev/null &&
                    git -C "$g" archive --prefix="$nm/" -o "$t/s/$nm-$(git -C "$g" rev-parse --short FETCH_HEAD).tar.gz" FETCH_HEAD &&
                    ok=$(git -C "$g" rev-parse --short FETCH_HEAD) && echo "$nm from mirror $m" >> "$log"
            fi
            if [ -z "$ok" ]; then  # hosts' snapshot URLs
                local sn= sr=$r
                [ "$r" = HEAD ] && sr=master   # snapshot URLs want a branch name
                case $url in
                *savannah.gnu.org*) sn="https://git.savannah.gnu.org/cgit/$repo.git/snapshot/$repo-$sr.tar.gz" ;;
                *github.com*) sn="https://gh-proxy.com/${url%.git}/archive/$sr.tar.gz" ;;
                esac
                [ -n "$sn" ] && curl -fsSL --retry 2 -m 900 -o "$t/s/$nm-$sr.tar.gz" "$sn" && ok=$sr
            fi
            [ -n "$ok" ] || { echo "$nm: no snapshot of $url $r" >> "$log"; rm -rf "$t"; return 1; }
            [ "$r" = HEAD ] && echo "$nm unpinned, HEAD $ok" >> "$log" || echo "$nm $r" >> "$log"
            ;;
        http://* | https://* | ftp://*)
            local fn=${nm:-$(basename "$u")}
            curl -fsSL --retry 2 -m 900 -o "$t/s/$fn" "$u" || { echo "$fn: download failed" >> "$log"; rm -rf "$t"; return 1; } ;;
        esac
    done < "$t/srcs"
    tar -C "$t" -czf "$out" --transform "s|^s|$(basename "$dir")|" s && rm -rf "$t"
}

# git sources whose own host does not serve a shallow fetch or snapshot here
# (savannah's cgit snapshots answer 301/400; its gnulib fetch times out)
declare -A GIT_MIRROR=([gnulib]=https://github.com/coreutils/gnulib)

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
    if [ -s "$f" ]; then echo "$name|$ver|$lic|(kept)" >> "$out/PACKAGES.txt"; continue; fi
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
