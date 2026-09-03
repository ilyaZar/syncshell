#!/bin/bash

set -euo pipefail

service_name="syncthing.service"
runtime_root="${XDG_RUNTIME_DIR:-/tmp}/omarchy-syncthing-$UID"
operation_file="$runtime_root/operation.pid"
bin_link="$HOME/.local/bin/syncthing"
service_file="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/$service_name"
script_path="$(readlink -f -- "$0")"

fail() {
  printf 'Error: %s\n' "$*" >&2
  return 1
}

step() {
  printf '\n==> %s\n' "$*"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

operation_running() {
  local pid=""
  [[ -f $operation_file ]] || return 1
  pid="$(<"$operation_file")"
  [[ $pid =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null
}

detect_status() {
  local executable="" executable_path=""
  local label="Not installed" state="missing"

  executable="$(command -v syncthing 2>/dev/null || true)"
  if [[ -n $executable ]]; then
    executable_path="$(readlink -f -- "$executable" 2>/dev/null || true)"
    [[ -n $executable_path ]] || executable_path="$executable"
  fi

  if [[ -n $executable_path ]]; then
    state="existing"
    label="Existing installation found: working"
  elif [[ -e $bin_link || -L $bin_link || -e $service_file ||
          -L $service_file ]]; then
    state="incomplete"
    label="Incomplete installation: non-working"
  fi

  jq -n \
    --arg state "$state" \
    --arg label "$label" \
    --arg executable "$executable_path" \
    --argjson operationRunning \
      "$(operation_running && echo true || echo false)" \
    '{
      state: $state,
      label: $label,
      executable: $executable,
      operationRunning: $operationRunning
    }'
}

installation_state() {
  detect_status | jq -r '.state'
}

ensure_initial_install() {
  local state=""
  state="$(installation_state)"
  [[ $state == missing ]] || fail \
    "Syncthing must be absent before installing it (state: $state)"
}

install_package() {
  ensure_initial_install
  require_command omarchy

  step "Installing the official Arch package through Omarchy"
  omarchy pkg add syncthing
  step "Enabling the Syncthing user service"
  systemctl --user daemon-reload
  systemctl --user enable --now "$service_name"
}

run_and_prompt() {
  local action="$1" result=0
  shift

  mkdir -p -- "$runtime_root"
  chmod 700 "$runtime_root"
  if operation_running; then
    fail "Another Syncthing operation is already running"
  fi
  printf '%s\n' "$$" >"$operation_file"
  trap '[[ ! -e $operation_file ]] || unlink -- "$operation_file"' EXIT

  printf 'Syncthing for Omarchy\n'
  printf '%s\n' '----------------------'
  set +e
  (
    set -Eeuo pipefail
    case "$action" in
      install-package) install_package ;;
      *) fail "Unknown operation: $action" ;;
    esac
  )
  result=$?
  set -e

  if (( result == 0 )); then
    printf '\nDone. The Syncthing operation completed successfully.\n'
  else
    printf '\nThe operation failed. Review the error above.\n' >&2
  fi
  printf 'Press Enter to close this terminal. '
  IFS= read -r _
  return "$result"
}

launch_terminal() {
  local action="$1"
  shift
  require_command uwsm-app
  require_command xdg-terminal-exec
  exec uwsm-app -- xdg-terminal-exec --title="Syncthing setup" -- \
    bash "$script_path" run "$action" "$@"
}

main() {
  case "${1:-status}" in
    status) detect_status ;;
    install) launch_terminal install-package ;;
    run)
      shift
      run_and_prompt "$@"
      ;;
    *)
      fail "usage: ${0##*/} {status|install}"
      return 2
      ;;
  esac
}

main "$@"
