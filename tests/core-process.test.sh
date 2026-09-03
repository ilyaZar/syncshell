#!/bin/bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d /tmp/syncshell-core-process.XXXXXX)
trap 'find "$test_root" -depth -delete' EXIT
mkdir -p -- "$test_root/bin/x86_64"
cp -- "$root/tests/core-process-mock.sh" \
  "$test_root/bin/x86_64/syncshell-core"
chmod 755 -- "$test_root/bin/x86_64/syncshell-core"

SYNCSHELL_TEST_PLUGIN_ROOT="$test_root" \
  timeout 15s quickshell --no-color -p "$root/tests-core-process.qml"
if pgrep -f "$test_root/bin/x86_64/syncshell-core" >/dev/null; then
  printf '%s\n' 'core process fixture was orphaned' >&2
  exit 1
fi
printf '%s\n' 'core process tests passed'
