#!/bin/bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

timeout 15s quickshell --no-color -p "$root/tests-standalone-service.qml"
if pgrep -f "$root/tests/core-process-mock.sh" >/dev/null; then
  printf '%s\n' 'standalone service fixture was orphaned' >&2
  exit 1
fi
printf '%s\n' 'standalone service tests passed'
