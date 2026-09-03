#!/bin/bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d /tmp/syncshell-standalone-service.XXXXXX)
trap 'find "$test_root" -depth -delete' EXIT
mkdir -p -- "$test_root/bin/x86_64"
cp -- "$root/tests/core-process-mock.sh" \
  "$test_root/bin/x86_64/syncshell-core"
chmod 755 -- "$test_root/bin/x86_64/syncshell-core"

SYNCSHELL_TEST_PLUGIN_ROOT="$test_root" \
  timeout 15s quickshell --no-color -p "$root/tests-standalone-service.qml"
if pgrep -f "$test_root/bin/x86_64/syncshell-core" >/dev/null; then
  printf '%s\n' 'standalone service fixture was orphaned' >&2
  exit 1
fi
printf '%s\n' 'standalone service tests passed'
