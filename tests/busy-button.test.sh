#!/bin/bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d /tmp/syncshell-busy-button.XXXXXX)
trap 'find "$test_root" -depth -delete' EXIT

mkdir -p -- "$test_root/ui"
ln -s -- /usr/share/omarchy/shell/Commons "$test_root/Commons"
ln -s -- /usr/share/omarchy/shell/Ui "$test_root/Ui"
cp -- "$root/hosts/omarchy/ui/BusyButton.qml" \
  "$test_root/ui/BusyButton.qml"
cp -- "$root/tests-busy-button.qml" "$test_root/tests-busy-button.qml"

timeout 10s quickshell --no-color -p "$test_root/tests-busy-button.qml"
