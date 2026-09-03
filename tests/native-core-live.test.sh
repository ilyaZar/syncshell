#!/bin/bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d /tmp/syncshell-native-core.XXXXXX)
syncthing_pid=""

cleanup() {
  if [[ -n $syncthing_pid ]] && kill -0 "$syncthing_pid" 2>/dev/null; then
    kill "$syncthing_pid" 2>/dev/null || true
    wait "$syncthing_pid" 2>/dev/null || true
  fi
  find "$test_root" -depth -delete
}
trap cleanup EXIT

for command in curl go jq syncthing xmlstarlet; do
  command -v "$command" >/dev/null 2>&1 || {
    printf 'missing live-test command: %s\n' "$command" >&2
    exit 1
  }
done

port_probe_flag() {
  local action=$1 help
  help=$(syncthing "$action" --help 2>&1 || true)
  if grep -Fq -- '--no-port-probing' <<<"$help"; then
    printf '%s\n' --no-port-probing
  elif grep -Fq -- '--skip-port-probing' <<<"$help"; then
    printf '%s\n' --skip-port-probing
  else
    printf 'Syncthing %s has no no-port-probing flag\n' "$action" >&2
    return 1
  fi
}

log_file_argument() {
  local path=$1 help
  help=$(syncthing serve --help 2>&1 || true)
  if grep -Fq -- '--log-file=' <<<"$help"; then
    printf '%s\n' "--log-file=$path"
  elif grep -Fq -- '--logfile=' <<<"$help"; then
    printf '%s\n' "--logfile=$path"
  else
    printf 'Syncthing serve has no log-file option\n' >&2
    return 1
  fi
}

st_home="$test_root/syncthing"
folder="$test_root/folder"
socket="$test_root/gui.sock"
binary="$test_root/syncshell-core"
mkdir -p -- "$st_home" "$folder"

STHOMEDIR="$st_home" syncthing generate \
  "$(port_probe_flag generate)" >/dev/null
config="$st_home/config.xml"
xmlstarlet ed -L \
  -d '/configuration/folder' \
  -d '/configuration/options/listenAddress' \
  -s '/configuration/options' -t elem -n listenAddress \
    -v 'tcp://127.0.0.1:0' \
  -u '/configuration/gui/address' -v "$socket" \
  -u '/configuration/options/globalAnnounceEnabled' -v false \
  -u '/configuration/options/localAnnounceEnabled' -v false \
  -u '/configuration/options/relaysEnabled' -v false \
  -u '/configuration/options/natEnabled' -v false \
  -u '/configuration/options/urAccepted' -v -1 \
  "$config"

STHOMEDIR="$st_home" syncthing serve "$(port_probe_flag serve)" \
  --no-browser --no-restart --no-upgrade \
  "$(log_file_argument "$test_root/syncthing.log")" \
  >"$test_root/syncthing.stdout" 2>&1 &
syncthing_pid=$!
for _ in $(seq 1 100); do
  curl --silent --fail --noproxy '*' --unix-socket "$socket" \
    http://localhost/rest/noauth/health >/dev/null 2>&1 && break
  sleep 0.1
done
curl --silent --fail --noproxy '*' --unix-socket "$socket" \
  http://localhost/rest/noauth/health >/dev/null

folder_json=$(syncthing cli --home="$st_home" config defaults folder dump-json |
  jq --arg id native-core --arg path "$folder" \
    '.id=$id | .label="Native core" | .path=$path | .paused=false')
syncthing cli --home="$st_home" config folders add-json "$folder_json" >/dev/null

go -C "$root/core" build -trimpath -o "$binary" ./cmd/syncshell-core
"$binary" probe --json --host-id standalone --config "$config" \
  >"$test_root/probe.json"
"$binary" status --json --config "$config" >"$test_root/status.json"
jq -e '
  .revision >= 1 and
  .connection.online == true and
  .identity.deviceId != ""
' "$test_root/probe.json" >/dev/null
jq -e '
  .revision >= 1 and
  .state.connection.online == true and
  .state.connection.endpoint == "unix://" + $socket and
  any(.state.folders[]; .id == "native-core")
' --arg socket "$socket" "$test_root/status.json" >/dev/null

printf '%s\n' \
  '{"v":1,"type":"configure","id":"1","config":{"probeIntervalSeconds":2}}' \
  '{"v":1,"type":"action","id":"2","action":"folder.rescan","args":{"folderId":"native-core"}}' \
  '{"v":1,"type":"shutdown","id":"3"}' |
  "$binary" stream --config "$config" >"$test_root/stream.jsonl" \
    2>"$test_root/core.stderr"

jq -s -e '
  .[0].type == "hello" and
  .[1].type == "snapshot" and
  any(.[]; .type == "result" and .id == "1" and .ok == true) and
  any(.[]; .type == "result" and .id == "2" and .ok == true) and
  any(.[]; .type == "result" and .id == "3" and .ok == true) and
  .[-1].type == "end"
' "$test_root/stream.jsonl" >/dev/null

api_key=$(xmlstarlet sel -t -v '/configuration/gui/apikey' "$config")
if grep -Fq -- "$api_key" "$test_root/probe.json" "$test_root/status.json" \
    "$test_root/stream.jsonl" "$test_root/core.stderr"; then
  printf '%s\n' 'native core output exposed the API key' >&2
  exit 1
fi

printf '%s\n' 'native core live Syncthing test passed'
