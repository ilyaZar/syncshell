#!/bin/bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

packages=(protocol session syncthing systemduser)
for package in "${packages[@]}"; do
  [[ -d $root/core/internal/$package ]] || {
    printf 'missing native-core package: %s\n' "$package" >&2
    exit 1
  }
done

mapfile -t actual_packages < <(
  find "$root/core/internal" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' |
    sort
)
[[ ${actual_packages[*]} == "protocol session syncthing systemduser" ]] || {
  printf 'unexpected native-core package layout: %s\n' "${actual_packages[*]}" >&2
  exit 1
}

if rg -n 'qs[.]Commons|qs[.]Ui|omarchy' \
    "$root/shared" "$root/hosts/standalone" >/dev/null; then
  printf '%s\n' 'standalone process boundary imports Omarchy' >&2
  exit 1
fi

if rg -n 'settings[.]toml|icon_style|web_ui_theme|ilyazar[.]syncthing' \
    -g '*.go' "$root/core" >/dev/null; then
  printf '%s\n' 'native core owns Omarchy settings' >&2
  exit 1
fi

if rg -n -i 'api[-_]?key|x-api-key|rest/|config[.]xml|systemctl' \
    "$root/shared" "$root/hosts/standalone" >/dev/null; then
  printf '%s\n' 'QML process boundary contains domain or credential logic' >&2
  exit 1
fi

if rg -n 'CoreProcess|syncshell-core' "$root/Panel.qml" "$root/Service.qml" \
    >/dev/null; then
  printf '%s\n' 'phase 02 changed the production Omarchy runtime' >&2
  exit 1
fi

if rg -n -- '--api-key|APIKey string `json|apiKey.*json' "$root/core" \
    >/dev/null; then
  printf '%s\n' 'native core exposes an API-key argument or JSON field' >&2
  exit 1
fi

if rg -n -g '!**/*_test.go' \
    'net[.]Listen|ListenUnix|unixgram|socket activation' "$root/core" \
    >/dev/null; then
  printf '%s\n' 'native core contains a daemon control socket path' >&2
  exit 1
fi

printf '%s\n' 'native core architecture test passed'
