#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
qs --no-color -p "$root/tests-folder-rescan.qml"
