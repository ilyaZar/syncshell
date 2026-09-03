#!/bin/bash
set -euo pipefail

temporary=""

cleanup() {
  [[ -z $temporary ]] || rm -f -- "$temporary"
}

trap cleanup EXIT

usage() {
  printf '%s\n' \
    'Usage: syncthing-settings.sh ensure <template> <target> <branded|themed>' \
    '       syncthing-settings.sh set-service-state <template> <target> <branded|themed> <enabled|disabled>' \
    >&2
  exit 2
}

seed_settings() {
  local template=$1 target=$2 icon_style=$3
  local target_dir

  [[ -f $template ]] || {
    printf 'Settings template is missing: %s\n' "$template" >&2
    return 1
  }
  [[ $icon_style == "branded" || $icon_style == "themed" ]] || usage
  [[ ! -e $target ]] || return 0

  target_dir=$(dirname -- "$target")
  if [[ ! -d $target_dir ]]; then
    mkdir -p -- "$target_dir"
    chmod 700 -- "$target_dir"
  fi

  temporary=$(mktemp --tmpdir="$target_dir" .settings.toml.XXXXXX)
  sed -E "s/^(icon_style[[:space:]]*=[[:space:]]*)\"branded\"/\1\"$icon_style\"/" \
    "$template" >"$temporary"
  chmod 600 -- "$temporary"
  mv -- "$temporary" "$target"
  temporary=""
}

write_service_state() {
  local target=$1 service_state=$2
  local target_dir

  [[ $service_state == "enabled" || $service_state == "disabled" ]] || usage
  target_dir=$(dirname -- "$target")
  temporary=$(mktemp --tmpdir="$target_dir" .settings.toml.XXXXXX)
  awk -v service_state="$service_state" '
    function write_state() {
      print "service_state = \"" service_state "\""
      state_seen = 1
    }
    function service_header(line) {
      return line ~ /^[[:space:]]*\[service\][[:space:]]*(#.*)?$/
    }
    function any_header(line) {
      return line ~ /^[[:space:]]*\[[^]]+\][[:space:]]*(#.*)?$/
    }
    {
      if (any_header($0)) {
        if (in_service && !state_seen) write_state()
        in_service = service_header($0)
        if (in_service) {
          if (service_seen) duplicate_service = 1
          service_seen = 1
        }
        print
        next
      }
      if (in_service &&
          $0 ~ /^[[:space:]]*service_state[[:space:]]*=/) {
        if (state_seen) duplicate_state = 1
        else write_state()
        next
      }
      print
    }
    END {
      if (duplicate_service || duplicate_state) exit 3
      if (!service_seen) {
        if (NR > 0) print ""
        print "[service]"
        write_state()
        print "probe_interval_seconds = 15"
      } else if (in_service && !state_seen) {
        write_state()
      }
    }
  ' "$target" >"$temporary" || {
    printf 'Could not update service settings safely\n' >&2
    return 1
  }
  chmod --reference="$target" "$temporary"
  mv -- "$temporary" "$target"
  temporary=""
}

case "${1:-}" in
  ensure)
    [[ $# == 4 ]] || usage
    seed_settings "$2" "$3" "$4"
    target=$3
    ;;
  set-service-state)
    [[ $# == 5 ]] || usage
    seed_settings "$2" "$3" "$4"
    write_service_state "$3" "$5"
    target=$3
    ;;
  *) usage ;;
esac

printf '%s\n' "$target"
