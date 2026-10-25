#!/bin/sh
# Reproduce a static aarch64-musl build of upstream virtiofsd.
# Runs on an arm64 host with Docker (here: colima on Apple Silicon).
# Usage: ./build-virtiofsd.sh [WORKDIR]   (default: directory containing this script's parent)
set -eu

TAG=${TAG:-v1.14.0}
EXPECTED_COMMIT=${EXPECTED_COMMIT:-c2540f8db14caba81c1e37fba23fc7bf2cd7f0dd}
IMAGE=${IMAGE:-alpine:3.22}
DOCKER=${DOCKER:-docker --context colima}
WORK=${1:-$(cd "$(dirname "$0")/.." && pwd)}

mkdir -p "$WORK/src" "$WORK/out"
if [ ! -d "$WORK/src/virtiofsd/.git" ]; then
    git clone --branch "$TAG" --depth 1 https://gitlab.com/virtio-fs/virtiofsd.git "$WORK/src/virtiofsd"
fi
COMMIT=$(git -C "$WORK/src/virtiofsd" rev-parse HEAD)
[ "$COMMIT" = "$EXPECTED_COMMIT" ] || { echo "commit mismatch: $COMMIT" >&2; exit 1; }

# Source and output are moved with `docker cp`, not bind mounts: colima only
# shares $HOME into its VM, and the work dir may live elsewhere (e.g. /private/tmp).
CID=$($DOCKER create --platform linux/arm64 "$IMAGE" sh -euxc '
        apk add --no-cache rust cargo musl-dev pkgconf file \
            libseccomp-dev libseccomp-static libcap-ng-dev libcap-ng-static
        export LIBSECCOMP_LINK_TYPE=static
        export LIBSECCOMP_LIB_PATH=/usr/lib
        # capng crate emits a plain -lcap-ng, which picks the .so if present: hide it
        # so the linker can only resolve libcap-ng.a.
        rm -f /usr/lib/libcap-ng.so /usr/lib/libseccomp.so
        # non-PIE fully static executable (no PT_DYNAMIC, no interpreter).
        # rustc puts -lcap-ng after -lc, so libc symbols used by libcap-ng.a
        # (capget, sscanf, ...) are unresolved; a trailing static -lc fixes the order
        # (-Bstatic is needed because rustc ends its library list with -Bdynamic;
        # -lgcc supplies the soft-float helpers musl libc.a needs under -nodefaultlibs).
        export RUSTFLAGS="-C target-feature=+crt-static -C relocation-model=static -C link-arg=-Wl,-Bstatic -C link-arg=-lc -C link-arg=-lgcc"
        cd /src
        # explicit --target so RUSTFLAGS (crt-static) is not applied to proc-macros/build scripts
        T=$(rustc -vV | sed -n "s/^host: //p")
        cargo build --release --locked --target "$T"
        mkdir -p /out
        cp target/$T/release/virtiofsd /out/virtiofsd
        strip /out/virtiofsd
        file /out/virtiofsd
        { rustc --version; cargo --version; } > /out/rustc-version.txt
    ')
trap '$DOCKER rm -f "$CID" >/dev/null' EXIT
$DOCKER cp "$WORK/src/virtiofsd" "$CID:/src"
$DOCKER start -a "$CID"
$DOCKER cp "$CID:/out/virtiofsd" "$WORK/out/virtiofsd"
$DOCKER cp "$CID:/out/rustc-version.txt" "$WORK/out/.rustc-version"

cd "$WORK/out"
file virtiofsd
shasum -a 256 virtiofsd > virtiofsd.sha256
cat virtiofsd.sha256
