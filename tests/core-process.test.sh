#!/bin/bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

timeout 15s quickshell --no-color -p "$root/tests-core-process.qml"
if pgrep -f "$root/tests/core-process-mock.sh" >/dev/null; then
  printf '%s\n' 'core process fixture was orphaned' >&2
  exit 1
fi
printf '%s\n' 'core process tests passed'
