#!/bin/bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d /tmp/syncshell-install-recovery.XXXXXX)
test_home="$test_root/home"
marker="$test_root/installation-ready"
trap 'find "$test_root" -depth -delete' EXIT

git -C "$root" ls-files -co --exclude-standard -z \
  | tar --null -C "$root" -T - -cf - \
  | tar -C "$test_root" -xf -
ln -s -- /usr/share/omarchy/shell/Commons "$test_root/Commons"
ln -s -- /usr/share/omarchy/shell/Ui "$test_root/Ui"
mkdir -p -- "$test_home/.config" "$test_home/.local/state"
cp -- "$root/tests/install-recovery-core-mock.sh" \
  "$test_root/bin/x86_64/syncshell-core"
chmod 755 -- "$test_root/bin/x86_64/syncshell-core"

HOME="$test_home" \
XDG_CONFIG_HOME="$test_home/.config" \
XDG_STATE_HOME="$test_home/.local/state" \
SYNCSHELL_RECOVERY_MARKER="$marker" \
  timeout 15s quickshell --no-color -p "$test_root/tests-install-recovery.qml"

if pgrep -f "$test_root/bin/x86_64/syncshell-core" >/dev/null; then
  printf '%s\n' 'install recovery test orphaned a native core' >&2
  exit 1
fi
