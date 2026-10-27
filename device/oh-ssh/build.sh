#!/bin/sh
# Build ohsshd and ohtoken (static linux/arm64, Go 1.22 or later) into ./out, and
# fetch frpc (upstream frp 0.61.2, the version on the test machines).
#   GOPROXY=https://goproxy.cn,direct sh build.sh   # where proxy.golang.org is slow
set -e
cd "$(dirname "$0")"
mkdir -p out
for p in ohsshd ohtoken; do
    (cd src/$p && CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -trimpath -ldflags='-s -w' -o ../../out/$p .)
done
v=0.61.2
curl -fsSL "https://github.com/fatedier/frp/releases/download/v$v/frp_${v}_linux_arm64.tar.gz" |
    tar xzf - -C out --strip-components=1 "frp_${v}_linux_arm64/frpc"
ls -l out
