#!/bin/bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d /tmp/syncshell-rescan-core-loss.XXXXXX)
test_home="$test_root/home"
trap 'find "$test_root" -depth -delete' EXIT

git -C "$root" archive HEAD | tar -x -C "$test_root"
ln -s -- /usr/share/omarchy/shell/Commons "$test_root/Commons"
ln -s -- /usr/share/omarchy/shell/Ui "$test_root/Ui"
mkdir -p -- "$test_home/.config" "$test_home/.local/state/syncthing"
config="$test_home/.local/state/syncthing/config.xml"
printf '%s\n' \
  '<configuration>' \
  '  <gui tls="false">' \
  '    <address>127.0.0.1:1</address>' \
  '    <apikey>test-placeholder</apikey>' \
  '  </gui>' \
  '</configuration>' >"$config"
chmod 600 -- "$config"

HOME="$test_home" \
XDG_CONFIG_HOME="$test_home/.config" \
XDG_STATE_HOME="$test_home/.local/state" \
  timeout 15s quickshell --no-color -p "$test_root/tests-rescan-core-loss.qml"

if pgrep -f "$test_root/bin/x86_64/syncshell-core" >/dev/null; then
  printf '%s\n' 'rescan core-loss test orphaned a native core' >&2
  exit 1
fi
