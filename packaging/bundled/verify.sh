#!/bin/bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
relative=bin/x86_64/syncshell-core
binary="$root/$relative"
test_root=$(mktemp -d /tmp/syncshell-bundled-verify.XXXXXX)
trap 'find "$test_root" -depth -delete' EXIT

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
  sha256sum --check packaging/bundled/SHA256SUMS
)

metadata=$(file -- "$binary")
[[ $metadata == *"ELF 64-bit LSB executable, x86-64"* ]] \
  || fail "binary architecture is not Linux x86_64"
[[ $metadata == *"statically linked"* ]] || fail "binary is dynamically linked"

linkage=$(ldd -- "$binary" 2>&1 || true)
[[ $linkage == *"not a dynamic executable"* \
    || $linkage == *"statically linked"* ]] \
  || fail "ldd reported dynamic linkage"
build_metadata=$(go version -m "$binary")
grep -Fq $'path\tgithub.com/omarchy-QOL/syncshell/core/cmd/syncshell-core' \
  <<<"$build_metadata" || fail "Go module path is unexpected"
grep -Fq $'build\tGOARCH=amd64' <<<"$build_metadata" \
  || fail "Go architecture metadata is unexpected"
grep -Fq $'build\tGOOS=linux' <<<"$build_metadata" \
  || fail "Go operating-system metadata is unexpected"

if strings -- "$binary" \
    | rg -n '/home/iz|/home-hdd-cold|BEGIN (RSA |OPENSSH )?PRIVATE KEY' \
      >/dev/null; then
  fail "binary contains a secret marker or developer path"
fi

config="$test_root/config.xml"
printf '%s\n' \
  '<configuration>' \
  '  <gui tls="false">' \
  '    <address>127.0.0.1:1</address>' \
  '    <apikey>verification-placeholder</apikey>' \
  '  </gui>' \
  '</configuration>' >"$config"
chmod 600 -- "$config"
frames=$("$binary" stream --host-id bundled-verify --config "$config" \
  </dev/null 2>/dev/null || true)
hello=$(sed -n '1p' <<<"$frames")
jq -e '.v == 1 and .type == "hello" and .build.version == "0.1.8"
  and .build.protocol == 1' <<<"$hello" >/dev/null \
  || fail "runtime version or protocol is unexpected"

printf '%s\n' "$metadata"
printf '%s\n' "$linkage"
printf '%s\n' "$build_metadata"
