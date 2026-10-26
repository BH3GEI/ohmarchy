#!/bin/bash
# sums.sh REPO TAG: SHA256SUMS for a draft release from GitHub's own sha256 of
# each asset (the API's "digest"), uploaded to it (replacing an older one). For
# assets uploaded from the HarmonyOS host (upload-on-host.sh), where nothing is
# hashed. Split files are listed by part: check the parts, then join them.
set -euo pipefail
repo=$1 tag=$2
dir=$(mktemp -d); trap 'rm -rf "$dir"' EXIT
gh api "repos/$repo/releases" --jq ".[] | select(.tag_name == \"$tag\" and .draft) | .assets[] | select(.name != \"SHA256SUMS\") | (.digest // \"none\") + \"  \" + .name" |
    sed 's/^sha256://' | sort -k2 > "$dir/SHA256SUMS"
grep -q '^none ' "$dir/SHA256SUMS" && { echo "sums.sh: an asset has no digest yet:" >&2; grep '^none ' "$dir/SHA256SUMS" >&2; exit 1; }
cat "$dir/SHA256SUMS"
gh release upload "$tag" -R "$repo" --clobber "$dir/SHA256SUMS"
