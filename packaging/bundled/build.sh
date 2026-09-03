#!/bin/bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
output="$root/bin/x86_64/syncshell-core"

mkdir -p -- "$(dirname -- "$output")"
(
  cd -- "$root/core"
  GOOS=linux GOARCH=amd64 CGO_ENABLED=0 \
    go build -mod=readonly -trimpath -buildvcs=false \
      -ldflags='-buildid=' -o "$output" ./cmd/syncshell-core
)
chmod 755 -- "$output"
(
  cd -- "$root"
  sha256sum bin/x86_64/syncshell-core \
    >packaging/bundled/SHA256SUMS
)
