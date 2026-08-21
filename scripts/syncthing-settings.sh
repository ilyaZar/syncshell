#!/bin/bash
set -euo pipefail

usage() {
  printf 'Usage: syncthing-settings.sh ensure <template> <target> <branded|themed>\n' >&2
  exit 2
}

[[ ${1:-} == "ensure" && $# == 4 ]] || usage

template=$2
target=$3
icon_style=$4

[[ -f $template ]] || {
  printf 'Settings template is missing: %s\n' "$template" >&2
  exit 1
}
[[ $icon_style == "branded" || $icon_style == "themed" ]] || usage

if [[ ! -e $target ]]; then
  target_dir=$(dirname -- "$target")
  if [[ ! -d $target_dir ]]; then
    mkdir -p -- "$target_dir"
    chmod 700 -- "$target_dir"
  fi

  temporary=$(mktemp --tmpdir="$target_dir" .settings.toml.XXXXXX)
  trap 'rm -f -- "$temporary"' EXIT
  sed -E "s/^(icon_style[[:space:]]*=[[:space:]]*)\"branded\"/\1\"$icon_style\"/" \
    "$template" >"$temporary"
  chmod 600 -- "$temporary"
  mv -- "$temporary" "$target"
  trap - EXIT
fi

printf '%s\n' "$target"
