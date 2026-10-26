#!/bin/bash
# release.sh: a GitHub release of built images (route B's installer ISO and
# disk image; route C's image later), always as a draft. Someone publishes it
# by hand on GitHub after checking it.
#   tools/release/release.sh MANIFEST [--dry-run] ASSET...
# MANIFEST (tools/release/<route>.conf, sourced as bash) sets:
#   TAG, TITLE          release tag and title
#   NOTES               markdown file with the release text (usage, limits)
#   GPL_PATHS=(...)     repo paths whose source goes into the GPL source archive
#   UPSTREAM=(...)      "URL SHA256" of unmodified upstream sources, attached
#                       together as one tar (e.g. the kernel the patches apply to)
#   COMPONENTS=(...)    "name|license|where its source is" rows for LICENSES.md
#   LICENSE_NOTE        optional paragraph at the end of LICENSES.md
# ASSETs are the built files (from the route's build). Files over SPLIT_MIB
# (default 2000: GitHub takes under 2 GiB per asset) go up in parts,
# NAME.part00, NAME.part01, ...; `cat NAME.part* > NAME` joins them.
# Every uploaded file and every joined asset is in SHA256SUMS.
# PKG_SOURCES: directory from gpl-sources.sh (the GPL/LGPL packages in the
# image, as makepkg --allsource archives); attached as one more asset. A draft is
# made even without it or with packages in its MISSING.txt: the notes then list
# what is missing at the top, and the draft must not be published until that list
# is empty (supervisor, 2026-10-26). LICENSES.md carries the written offer too.
# Big files that sit on the HarmonyOS host (the Mac's link to it is slow):
# HOST_UPLOAD=1 makes the draft with the local files only (no ASSET needed), and
# PKG_SOURCES may then hold only PACKAGES.txt and MISSING.txt (the archives are
# tarred and uploaded on the host). Then upload-on-host.sh there, and sums.sh
# here for SHA256SUMS from GitHub's digests; the commands are printed at the end.
# Staging: OUT (default work/release/TAG). Needs gh logged in, with push rights.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
[ $# -ge 1 ] || { sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
manifest=$1; shift
dry=0; [ "${1:-}" = --dry-run ] && { dry=1; shift; }
[ $# -ge 1 ] || [ "${HOST_UPLOAD:-0}" = 1 ] || { echo "release.sh: no assets given" >&2; exit 2; }
GPL_PATHS=() UPSTREAM=() COMPONENTS=()
# shellcheck source=/dev/null
. "$manifest"
: "${TAG:?manifest sets TAG}" "${TITLE:?manifest sets TITLE}" "${NOTES:?manifest sets NOTES}"
REPO=${REPO:-$(cd "$root" && gh repo view --json nameWithOwner -q .nameWithOwner)}
OUT=${OUT:-$root/work/release/$TAG}
SPLIT_MIB=${SPLIT_MIB:-2000}
commit=$(cd "$root" && git rev-parse HEAD)
[ -z "$(cd "$root" && git status --porcelain -- "${GPL_PATHS[@]}")" ] ||
    { echo "release.sh: uncommitted changes in the GPL paths; the source archive must match a commit" >&2; exit 1; }
rm -rf "$OUT"; mkdir -p "$OUT/up"
: > "$OUT/whole.sha256"
if [ -n "${PKG_SOURCES:-}" ] && [ "${HOST_UPLOAD:-0}" != 1 ]; then
    [ -s "$PKG_SOURCES/PACKAGES.txt" ] || { echo "release.sh: $PKG_SOURCES has no PACKAGES.txt (gpl-sources.sh)" >&2; exit 1; }
    pk=$OUT/ohmarchy-$TAG-package-sources.tar
    tar -C "$PKG_SOURCES" -cf "$pk" .
    set -- "$@" "$pk"
fi
gate=
[ -n "${PKG_SOURCES:-}" ] || gate="no PKG_SOURCES (gpl-sources.sh) given"
[ -z "${PKG_SOURCES:-}" ] || [ ! -s "$PKG_SOURCES/MISSING.txt" ] || gate="$(wc -l < "$PKG_SOURCES/MISSING.txt" | tr -d ' ') packages without source (MISSING.txt)"
[ -z "$gate" ] || echo "release.sh: $gate; the draft says so and must not be published before it is fixed" >&2

echo "== assets"
for a in "$@"; do
    [ -f "$a" ] || { echo "release.sh: no such file: $a" >&2; exit 1; }
    n=$(basename "$a")
    size=$(($(stat -c %s "$a" 2>/dev/null || stat -f %z "$a") / 1048576))
    (cd "$(dirname "$a")" && shasum -a 256 "$n") >> "$OUT/whole.sha256"
    if [ "$size" -gt "$SPLIT_MIB" ]; then
        split -b "${SPLIT_MIB}m" -d -a 2 "$a" "$OUT/up/$n.part"
        echo "  $n: $size MiB, in $(ls "$OUT/up/$n".part* | wc -l | tr -d ' ') parts"
    else
        ln "$a" "$OUT/up/$n" 2>/dev/null || cp "$a" "$OUT/up/$n"
        echo "  $n: $size MiB"
    fi
done

echo "== GPL source"
src=ohmarchy-$TAG-source
(cd "$root" && git archive --format=tar.gz --prefix="$src/" -o "$OUT/up/$src.tar.gz" "$commit" -- "${GPL_PATHS[@]}")
echo "  $src.tar.gz: ${GPL_PATHS[*]} at $commit"
if [ ${#UPSTREAM[@]} -gt 0 ]; then
    ups=ohmarchy-$TAG-upstream-source
    mkdir -p "$OUT/$ups"
    for u in "${UPSTREAM[@]}"; do
        url=${u%% *} want=${u#* }
        f=$OUT/$ups/$(basename "$url")
        curl -fsSL --retry 3 -o "$f" "$url"
        got=$(shasum -a 256 "$f" | cut -d' ' -f1)
        [ "$got" = "$want" ] || { echo "release.sh: $url: sha256 $got, expected $want" >&2; exit 1; }
        echo "$url" >> "$OUT/$ups/SOURCES"
        echo "  $(basename "$url") (upstream, sha256 checked)"
    done
    tar -C "$OUT" -cf "$OUT/up/$ups.tar" "$ups"
    echo "  -> $ups.tar"
fi

echo "== LICENSES.md"
{
    echo "# Licenses: $TITLE"
    echo
    echo "Built from [$REPO@${commit:0:7}](https://github.com/$REPO/tree/$commit)."
    echo "The GPL source for everything modified or written for this release is"
    echo "\`$src.tar.gz\` (the repository paths below at that commit); unmodified"
    echo "upstream sources the patches apply to are in \`ohmarchy-$TAG-upstream-source.tar\`"
    echo "as downloaded (URLs in its SOURCES file, sha256 in the manifest)."
    echo
    echo "| Component | License | Source |"
    echo "|---|---|---|"
    for c in "${COMPONENTS[@]}"; do echo "| ${c//|/ | } |"; done
    echo
    echo "Repository paths in \`$src.tar.gz\`: $(printf '`%s` ' "${GPL_PATHS[@]}")"
    [ -z "${LICENSE_NOTE:-}" ] || { echo; echo "$LICENSE_NOTE"; }
    echo
    echo "Written offer: for three years after this release, the complete corresponding"
    echo "source of any GPL or LGPL software in its images is available on request, at no"
    echo "more than the cost of providing it; ask through https://github.com/$REPO/issues."
    echo "源码可应要求提供（三年内有效，收费不超过提供成本），请在本仓库提 issue。"
} > "$OUT/up/LICENSES.md"

echo "== SHA256SUMS"
(cd "$OUT/up" && shasum -a 256 -- * > ../SHA256SUMS.parts)
{ cat "$OUT/SHA256SUMS.parts"; echo "# joined (cat NAME.part* > NAME):"; cat "$OUT/whole.sha256"; } > "$OUT/up/SHA256SUMS"
cat "$OUT/up/SHA256SUMS"

{ if [ -n "$gate" ]; then
      echo "> **补齐后才公开 / not to be published until fixed:** $gate"
      if [ -s "${PKG_SOURCES:-/nonexistent}/MISSING.txt" ]; then
          echo ">"
          echo "> <details><summary>缺源码的包 / packages without source ($(wc -l < "$PKG_SOURCES/MISSING.txt" | tr -d ' '))</summary>"
          echo ">"
          cut -d'|' -f1,2,4 "$PKG_SOURCES/MISSING.txt" | awk -F'|' '{ r = $3; if (length(r) > 90) r = substr(r, 1, 90) "…"; print "> - " $1 " " $2 ": " r }'
          echo ">"
          echo "> </details>"
      fi
      echo
  fi
  cat "$NOTES"; echo
  echo "## Download and check"
  echo
  echo 'Files over 2 GiB are in parts: `cat NAME.part* > NAME`. Then `sha256sum -c SHA256SUMS --ignore-missing`.'
  echo
  echo "Licenses and source: LICENSES.md, $src.tar.gz."; } > "$OUT/notes.md"

files=("$OUT"/up/*)
if [ "$dry" = 1 ]; then
    [ -z "$gate" ] || echo "== not releasable yet: $gate"
    echo "== dry run: would create draft $TAG on $REPO with ${#files[@]} files"
    exit 0
fi
echo "== draft release $TAG on $REPO"
if gh release view "$TAG" -R "$REPO" > /dev/null 2>&1; then
    [ "$(gh release view "$TAG" -R "$REPO" --json isDraft -q .isDraft)" = true ] ||
        { echo "release.sh: $TAG is already published; not touching it" >&2; exit 1; }
    gh release upload "$TAG" -R "$REPO" --clobber "${files[@]}"
    gh release edit "$TAG" -R "$REPO" --notes-file "$OUT/notes.md" --title "$TITLE"
else
    gh release create "$TAG" -R "$REPO" --draft --target "$commit" --title "$TITLE" \
        --notes-file "$OUT/notes.md" "${files[@]}"
fi
gh release view "$TAG" -R "$REPO" --json url,isDraft -q '.url + " (draft: " + (.isDraft|tostring) + ")"'
if [ "${HOST_UPLOAD:-0}" = 1 ]; then
    id=$(gh api "repos/$REPO/releases" --jq ".[] | select(.tag_name == \"$TAG\" and .draft) | .id" | head -1)
    echo "== next: on the host, with a token for $REPO as the first line of stdin:"
    echo "   upload-on-host.sh $REPO $id LOG ISO=NAME... ohmarchy-$TAG-package-sources.tar=ohmarchy-$TAG-package-sources.tar"
    echo "   then here: tools/release/sums.sh $REPO $TAG"
fi
