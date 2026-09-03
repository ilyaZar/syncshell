#!/bin/bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
green=$'\033[0;32m'
red=$'\033[0;31m'
reset=$'\033[0m'

fail() {
  printf '%s[error]%s %s\n' "$red" "$reset" "$*" >&2
  exit 1
}

manifest_count=$(
  find "$root" \
    -path "$root/.git" -prune -o \
    -path "$root/TODO" -prune -o \
    -type f -name manifest.json -print \
    | wc -l
)
[[ $manifest_count -eq 1 ]] || fail "expected one root manifest"

for entry_point in manifest.json Panel.qml Service.qml; do
  [[ -f $root/$entry_point && ! -L $root/$entry_point ]] \
    || fail "$entry_point must be a regular root entry point"
done

if find "$root" \
    -path "$root/.git" -prune -o \
    -path "$root/TODO" -prune -o \
    -type l -print -quit | grep -q .; then
  fail "plugin tree contains a symbolic link"
fi
[[ ! -f $root/.gitmodules ]] || fail "plugin tree contains submodules"

future_hosts=(
  caelestia
  dankmaterialshell
  illogical-impulse
  waybar
)
for host in "${future_hosts[@]}"; do
  host_dir="$root/hosts/$host"
  [[ -d $host_dir ]] || fail "future host directory is missing: $host"
  mapfile -t entries < <(
    find "$host_dir" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort
  )
  [[ ${#entries[@]} -eq 1 && ${entries[0]} == README.md ]] \
    || fail "future host must contain only README.md: $host"
  grep -Fq 'unimplemented and unsupported in Syncshell 0.1.8' \
    "$host_dir/README.md" \
    || fail "future host README makes an unsupported status claim: $host"
done

if git -C "$root" ls-files \
    | grep -Eq '(^|/)(TODO|sources|\.research)(/|$)'; then
  fail "implementation prompts or transcripts are tracked"
fi

if rg -n '/home/iz|/home-hdd-cold|chatgpt-share' \
    "$root/CONTEXT.md" "$root/DEVELOPMENT.md" "$root/docs" \
    "$root/hosts" >/dev/null; then
  fail "tracked architecture material contains developer-local evidence"
fi

grep -Fq "\`dev\` is the integration branch" "$root/DEVELOPMENT.md" \
  || fail "development branch policy is missing"
grep -Fq 'Omarchy remains the sole owner' \
  "$root/docs/adr/0003-omarchy-settings-boundary.md" \
  || fail "Omarchy settings ownership is missing"
grep -Fq 'Unit presence or activity is not authority' \
  "$root/docs/ownership.md" \
  || fail "lifecycle authority rule is missing"
grep -Fq 'There is no mixed runtime, fallback, alias, or feature flag' \
  "$root/docs/ownership.md" \
  || fail "one-way cutover rule is missing"

printf '%s[ok]%s architecture contract passed\n' "$green" "$reset"
