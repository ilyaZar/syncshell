#!/bin/bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
relative=bin/x86_64/syncshell-core
binary="$root/$relative"

fail() {
  printf 'bundled core verification failed: %s\n' "$*" >&2
  exit 1
}

[[ -f $binary && ! -L $binary && -x $binary ]] \
  || fail "binary is not a regular executable"
[[ $(git -C "$root" ls-files -s -- "$relative" | awk '{print $1}') == 100755 ]] \
  || fail "Git mode is not 100755"
(
  cd -- "$root"
  sha256sum --check packaging/bundled/syncshell-core.sha256
)

metadata=$(file -- "$binary")
[[ $metadata == *"ELF 64-bit LSB executable, x86-64"* ]] \
  || fail "binary architecture is not Linux x86_64"
[[ $metadata == *"statically linked"* ]] || fail "binary is dynamically linked"

linkage=$(ldd -- "$binary" 2>&1 || true)
[[ $linkage == *"not a dynamic executable"* \
    || $linkage == *"statically linked"* ]] \
  || fail "ldd reported dynamic linkage"
go version -m "$binary" | grep -Fq 'path' \
  || fail "Go build metadata is missing"

if strings -- "$binary" \
    | rg -n '/home/iz|/home-hdd-cold|BEGIN (RSA |OPENSSH )?PRIVATE KEY' \
      >/dev/null; then
  fail "binary contains a secret marker or developer path"
fi

printf '%s\n' "$metadata"
printf '%s\n' "$linkage"
go version -m "$binary"
