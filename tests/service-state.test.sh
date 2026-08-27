#!/bin/bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d /tmp/syncshell-service-state.XXXXXX)
trap 'find "$test_root" -depth -delete' EXIT
fake_bin="$test_root/bin"
state_file="$test_root/unit-file-state"
mkdir -p -- "$fake_bin" "$test_root/home" "$test_root/runtime"
printf 'disabled\n' >"$state_file"

printf '%s\n' '#!/bin/bash' 'exit 0' >"$fake_bin/syncthing"
# Fake variables expand only when the generated command runs.
# shellcheck disable=SC2016
printf '%s\n' \
  '#!/bin/bash' \
  'set -euo pipefail' \
  'action=""' \
  'property=""' \
  'for argument in "$@"; do' \
  '  case "$argument" in' \
  '    show|enable|disable) action=$argument ;;' \
  '    --property=*) property=${argument#--property=} ;;' \
  '  esac' \
  'done' \
  'case "$action:$property" in' \
  '  show:LoadState) printf '\''loaded\n'\'' ;;' \
  '  show:ActiveState) printf '\''inactive\n'\'' ;;' \
  '  show:UnitFileState) cat -- "$SYNCSHELL_SYSTEMCTL_STATE" ;;' \
  '  enable:)' \
  '    if [[ ${SYNCSHELL_EXPECT_SYSTEMCTL_FAILURE:-0} == 1 ]]; then' \
  '      printf '\''permission denied\n'\'' >&2' \
  '      exit 5' \
  '    fi' \
  '    printf '\''enabled\n'\'' >"$SYNCSHELL_SYSTEMCTL_STATE"' \
  '    ;;' \
  '  disable:) printf '\''disabled\n'\'' >"$SYNCSHELL_SYSTEMCTL_STATE" ;;' \
  '  *) exit 1 ;;' \
  'esac' \
  >"$fake_bin/systemctl"
chmod 700 -- "$fake_bin/syncthing" "$fake_bin/systemctl"

run_case() {
  local expect_failure=$1
  printf 'disabled\n' >"$state_file"
  HOME="$test_root/home" \
    PATH="$fake_bin:$PATH" \
    SYNCSHELL_EXPECT_SYSTEMCTL_FAILURE="$expect_failure" \
    SYNCSHELL_INSTALL_HELPER="$root/scripts/syncthing-install.sh" \
    SYNCSHELL_SYSTEMCTL_STATE="$state_file" \
    qs --no-color -p "$root/tests-service-state.qml"
}

run_case 0
run_case 1
printf 'all service state controller tests passed\n'
