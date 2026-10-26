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

declare -A done=()
while IFS='|' read -r name ver base lic; do
    gpl "$lic" || continue
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
    # --allsource: PKGBUILD, local files and every downloaded source in one archive
    if (cd "$d" && makepkg --allsource --skippgpcheck --nocheck > "$work/$base.log" 2>&1); then
        mv "$d"/*.src.tar.gz "$f"
        echo "$name|$ver|$lic|$src" >> "$out/PACKAGES.txt"
        echo "  $base $ver ($src)"
    else
        echo "$name|$ver|$lic|makepkg --allsource failed: $(tail -1 "$work/$base.log")" >> "$out/MISSING.txt"
    fi
done < "$list"
echo "$(wc -l < "$out/PACKAGES.txt") package bases with source, $(wc -l < "$out/MISSING.txt") missing (MISSING.txt)"
