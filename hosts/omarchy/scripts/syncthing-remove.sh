#!/bin/bash
set -euo pipefail

readonly plugin_id="io.github.ilyazar.syncthing"
readonly data_id="ilyazar.syncthing"

fail() {
  printf 'syncthing-remove: %s\n' "$*" >&2
  exit 1
}

init_paths() {
  local user_home=${HOME:-}
  [[ -n $user_home && $user_home == /* ]] || fail "HOME must be absolute"

  local config_base=${XDG_CONFIG_HOME:-$user_home/.config}
  local state_base=${XDG_STATE_HOME:-$user_home/.local/state}
  local runtime_base=${XDG_RUNTIME_DIR:-$state_base/runtime}

  config_root=$(realpath -m -- "$config_base/omarchy/$data_id")
  state_root=$(realpath -m -- "$state_base/omarchy/$data_id")
  runtime_root=$(realpath -m -- "$runtime_base/omarchy-$data_id")
  plugins_root=$(realpath -m -- "$config_base/omarchy/plugins")
  installed_path="$plugins_root/$plugin_id"

  [[ $config_root == /* && $state_root == /* && $runtime_root == /*
    && $plugins_root == /*
    && $(basename -- "$config_root") == "$data_id"
    && $(basename -- "$state_root") == "$data_id"
    && $(basename -- "$runtime_root") == "omarchy-$data_id"
    && $(basename -- "$installed_path") == "$plugin_id" ]] \
    || fail "refusing unsafe plugin paths"
}

validate_installation() {
  local source_root=$1
  local source_real manifest_id

  [[ -e $installed_path || -L $installed_path ]] \
    || fail "the Syncthing plugin is not installed"
  [[ -f $installed_path/manifest.json ]] \
    || fail "the installed manifest is missing"
  manifest_id=$(jq -r '.id // ""' "$installed_path/manifest.json")
  [[ $manifest_id == "$plugin_id" ]] \
    || fail "the installed plugin identity changed"

  source_real=$(realpath -e -- "$source_root")
  [[ $source_real == "$(realpath -e -- "$installed_path")" ]] \
    || fail "the installed plugin path changed"
}

validate_theme_path() {
  local gui_assets=$1
  [[ $gui_assets == /* ]] || fail "the GUI assets path must be absolute"
  gui_assets=$(realpath -m -- "$gui_assets")
  theme_path="$gui_assets/syncthing-omarchy"
  [[ $(dirname -- "$theme_path") == "$gui_assets"
    && $(basename -- "$theme_path") == "syncthing-omarchy" ]] \
    || fail "refusing unsafe theme path"
}

delete_tree() {
  local path=$1
  [[ ! -L $path ]] || fail "refusing to remove a linked path"
  [[ ! -e $path ]] || find "$path" -depth -delete
}

notify_result() {
  local title=$1
  local message=$2
  command -v omarchy-notification-send >/dev/null 2>&1 \
    && omarchy-notification-send "$title" "$message" >/dev/null 2>&1 \
    || true
}

worker() {
  local source_root=$1
  local gui_assets=$2
  local cleanup_mode=$3
  local exit_code worker_dir

  init_paths
  worker_dir=$(dirname -- "$(realpath -m -- "$0")")
  if [[ $(dirname -- "$worker_dir") == "$runtime_root"
      && $(basename -- "$worker_dir") == remove.* ]]; then
    worker_cleanup_path=$worker_dir
    trap 'find "$worker_cleanup_path" -depth -delete 2>/dev/null || true' EXIT
  fi
  validate_installation "$source_root"
  validate_theme_path "$gui_assets"
  [[ $cleanup_mode == preserve || $cleanup_mode == purge ]] \
    || fail "invalid cleanup mode"

  if timeout --signal=TERM --kill-after=5s 300s \
      omarchy plugin remove "$plugin_id" --yes >/dev/null 2>&1; then
    :
  else
    exit_code=$?
    if [[ -e $installed_path || -L $installed_path ]]; then
      notify_result "Syncthing plugin removal failed" \
        "Native removal failed with exit code $exit_code"
      exit "$exit_code"
    fi
  fi

  delete_tree "$theme_path"
  if [[ $cleanup_mode == purge ]]; then
    delete_tree "$config_root"
    delete_tree "$state_root"
  fi
  notify_result "Syncthing plugin" \
    "Plugin removed; Syncthing folders and data were left untouched"
}

start() {
  local source_root=$1
  local gui_assets=$2
  local cleanup_mode=$3
  local worker_dir worker_path

  init_paths
  validate_installation "$source_root"
  validate_theme_path "$gui_assets"
  [[ $cleanup_mode == preserve || $cleanup_mode == purge ]] \
    || fail "invalid cleanup mode"

  umask 077
  mkdir -p -- "$runtime_root"
  [[ ! -L $runtime_root ]] || fail "the runtime path is linked"
  worker_dir=$(mktemp -d "$runtime_root/remove.XXXXXX")
  worker_path="$worker_dir/syncthing-remove"
  install -m 0700 -- "$0" "$worker_path"

  setsid bash "$worker_path" _worker "$source_root" "$gui_assets" \
    "$cleanup_mode" </dev/null >/dev/null 2>&1 &
  printf '%s\n' "$!"
}

case ${1:-} in
  start)
    [[ $# == 4 ]] || fail "usage: syncthing-remove.sh start ROOT GUI_ASSETS MODE"
    start "$2" "$3" "$4"
    ;;
  _worker)
    [[ $# == 4 ]] || exit 2
    worker "$2" "$3" "$4"
    ;;
  *)
    fail "usage: syncthing-remove.sh start ROOT GUI_ASSETS MODE"
    ;;
esac
