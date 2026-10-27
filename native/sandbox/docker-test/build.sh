#!/bin/bash
# build.sh: the test builds of containerd, dockerd and runc for the native
# sandbox, cross-compiled for linux/arm64 (on a Mac: Go, git and
# aarch64-linux-musl-gcc for runc's C part). README.md says what each patch does.
#   build.sh [WORK]     sources and binaries in WORK (default ./work)
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
W=${1:-$here/work}
mkdir -p "$W/out"
export GOTOOLCHAIN=auto GOOS=linux GOARCH=arm64

src() {  # REPO TAG DIR DIFF
    [ -d "$W/$3" ] || git clone -q --depth 1 --branch "$2" "$1" "$W/$3"
    git -C "$W/$3" apply --check "$here/$4" 2>/dev/null && git -C "$W/$3" apply "$here/$4" || echo "$3: patch already applied"
}

src https://github.com/containerd/containerd v2.4.2 containerd containerd-v2.4.2.diff
(cd "$W/containerd" && CGO_ENABLED=0 go build -mod=vendor -tags no_btrfs \
    -ldflags "-s -w -X github.com/containerd/containerd/v2/version.Version=v2.4.2+hongmeng" \
    -o "$W/out/containerd" ./cmd/containerd)

src https://github.com/moby/moby docker-v29.9.2 moby moby-docker-v29.9.2.diff
(cd "$W/moby" && CGO_ENABLED=0 go build -mod=vendor -tags 'netgo osusergo static_build exclude_graphdriver_btrfs' \
    -ldflags '-s -w -X github.com/moby/moby/v2/dockerversion.Version=29.9.2+hongmeng' \
    -o "$W/out/dockerd" ./cmd/dockerd)

# runc without the seccomp tag: static, no libseccomp (README, "what is weaker")
src https://github.com/opencontainers/runc v1.5.2 runc runc-v1.5.2.diff
(cd "$W/runc" && CGO_ENABLED=1 CC=aarch64-linux-musl-gcc go build -mod=vendor -trimpath \
    -tags 'urfave_cli_no_docs netgo osusergo' \
    -ldflags '-s -w -extldflags -static -X main.version=1.5.2+hongmeng' \
    -o "$W/out/runc" .)

ls -l "$W/out"
