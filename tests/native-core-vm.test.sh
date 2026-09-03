#!/bin/bash
set -euo pipefail

: "${SYNCSHELL_CORE_PATH:?missing core path}"

test_root=$(mktemp -d /tmp/syncshell-native-core-vm.XXXXXX)
artifact_root=${SYNCSHELL_VM_ARTIFACT_ROOT:-$HOME/syncshell-vm/artifacts}
result="$artifact_root/phase02-native-core.json"
http_home="$test_root/http"
https_home="$test_root/https"
http_folder="$test_root/http-folder"
http_url=http://127.0.0.1:28340
https_url=https://127.0.0.1:28341
pids=()
initial_service_active=$(systemctl --user is-active syncthing.service || true)
initial_unit_file_state=$(systemctl --user is-enabled syncthing.service || true)
settings=$HOME/.config/omarchy/ilyazar.syncthing/settings.toml

settings_hash() {
  if [[ -f $settings ]]; then
    sha256sum "$settings" | awk '{print $1}'
  else
    printf '%s\n' missing
  fi
}

settings_mode() {
  if [[ -f $settings ]]; then
    stat -c '%a' "$settings"
  else
    printf '%s\n' missing
  fi
}

settings_hash_before=$(settings_hash)
settings_mode_before=$(settings_mode)

cleanup() {
  local pid
  for pid in "${pids[@]:-}"; do
    if [[ -n $pid ]] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
    fi
  done
  if [[ $initial_service_active == active ]]; then
    systemctl --user start syncthing.service >/dev/null 2>&1 || true
  else
    systemctl --user stop syncthing.service >/dev/null 2>&1 || true
  fi
  find "$test_root" -depth -delete
}
trap cleanup EXIT

for command in curl jq syncthing systemctl xmlstarlet; do
  command -v "$command" >/dev/null 2>&1 || {
    printf 'missing VM test command: %s\n' "$command" >&2
    exit 1
  }
done
[[ -x $SYNCSHELL_CORE_PATH ]]
mkdir -p -- "$artifact_root" "$http_home" "$https_home" "$http_folder"

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

prepare_instance() {
  local home=$1 address=$2 tls=$3
  STHOMEDIR="$home" syncthing generate "$(port_probe_flag generate)" \
    >/dev/null
  xmlstarlet ed -L \
    -d '/configuration/folder' \
    -d '/configuration/options/listenAddress' \
    -s '/configuration/options' -t elem -n listenAddress \
      -v 'tcp://127.0.0.1:0' \
    -u '/configuration/gui/@tls' -v "$tls" \
    -u '/configuration/gui/address' -v "$address" \
    -u '/configuration/options/globalAnnounceEnabled' -v false \
    -u '/configuration/options/localAnnounceEnabled' -v false \
    -u '/configuration/options/relaysEnabled' -v false \
    -u '/configuration/options/natEnabled' -v false \
    -u '/configuration/options/urAccepted' -v -1 \
    "$home/config.xml"
}

start_instance() {
  local home=$1 log=$2
  STHOMEDIR="$home" syncthing serve "$(port_probe_flag serve)" \
    --no-browser --no-restart --no-upgrade "$(log_file_argument "$log")" \
    >"$log.stdout" 2>&1 &
  pids+=("$!")
}

wait_health() {
  local url=$1 insecure=${2:-false} curl_args=()
  [[ $insecure == false ]] || curl_args+=(--insecure)
  for _ in $(seq 1 120); do
    curl "${curl_args[@]}" --silent --fail --noproxy '*' \
      "$url/rest/noauth/health" >/dev/null 2>&1 && return 0
    sleep 0.1
  done
  return 1
}

prepare_instance "$http_home" 127.0.0.1:28340 false
start_instance "$http_home" "$test_root/http.log"
wait_health "$http_url"

folder_json=$(syncthing cli --home="$http_home" config defaults folder dump-json |
  jq --arg id phase02 --arg path "$http_folder" \
    '.id=$id | .label="Phase 02" | .path=$path | .paused=false')
syncthing cli --home="$http_home" config folders add-json "$folder_json" \
  >/dev/null
http_key=$(xmlstarlet sel -t -v '/configuration/gui/apikey' \
  "$http_home/config.xml")
printf '%s\n' "$http_key" >"$test_root/http.credential"
chmod 600 "$test_root/http.credential"

"$SYNCSHELL_CORE_PATH" status --json --host-id standalone \
  --config "$http_home/config.xml" >"$test_root/explicit.json"
jq -e '.state.connection.online and
  .state.lifecycle.canControl == false and
  any(.state.folders[]; .id == "phase02")' \
  "$test_root/explicit.json" >/dev/null

STHOMEDIR="$http_home" "$SYNCSHELL_CORE_PATH" probe --json \
  --host-id standalone >"$test_root/discovered.json"
jq -e '.connection.online and .connection.endpoint == "http://127.0.0.1:28340"' \
  "$test_root/discovered.json" >/dev/null

unit_active_before=$(systemctl --user is-active syncthing.service || true)
systemctl --user stop syncthing.service
unit_active_before=$(systemctl --user is-active syncthing.service || true)
unit_file_before=$(systemctl --user is-enabled syncthing.service || true)
{
  printf '%s\n' \
    '{"v":1,"type":"action","id":"1","action":"folder.rescan","args":{"folderId":"phase02"}}'
  sleep 3
  printf '%s\n' '{"v":1,"type":"shutdown","id":"2"}'
} | "$SYNCSHELL_CORE_PATH" stream --host-id standalone \
  --config "$http_home/config.xml" --probe-interval-seconds 1 \
  --lifecycle-kind systemd-user --lifecycle-authorized \
  --lifecycle-unit syncthing.service >"$test_root/issue45.jsonl"
jq -s -e '
  any(.[]; .type == "snapshot" and .state.connection.online == true and
    .state.lifecycle.classification == "external" and
    .state.lifecycle.canControl == false) and
  any(.[]; .type == "result" and .id == "1" and .ok == true) and
  .[-1].type == "end"
' "$test_root/issue45.jsonl" >/dev/null
[[ $(systemctl --user is-active syncthing.service || true) == "$unit_active_before" ]]
[[ $(systemctl --user is-enabled syncthing.service || true) == "$unit_file_before" ]]

printf '%s\n' wrong-test-credential >"$test_root/wrong.credential"
chmod 600 "$test_root/wrong.credential"
set +e
"$SYNCSHELL_CORE_PATH" status --json --host-id standalone \
  --endpoint "$http_url" --credential-file "$test_root/wrong.credential" \
  >"$test_root/wrong.json" 2>"$test_root/wrong.stderr"
wrong_status=$?
set -e
[[ $wrong_status -ne 0 ]]
jq -e '.state.connection.error.code == "unauthorized"' \
  "$test_root/wrong.json" >/dev/null

printf '%s\n' '<configuration><gui>' >"$test_root/malformed.xml"
set +e
"$SYNCSHELL_CORE_PATH" status --json --host-id standalone \
  --config "$test_root/malformed.xml" >"$test_root/malformed.json" \
  2>"$test_root/malformed.stderr"
malformed_status=$?
set -e
[[ $malformed_status -ne 0 ]]

env PATH=/nonexistent "$SYNCSHELL_CORE_PATH" status --json \
  --host-id standalone --endpoint "$http_url" \
  --credential-file "$test_root/http.credential" \
  >"$test_root/no-binary.json"
jq -e '.state.connection.online == true' "$test_root/no-binary.json" \
  >/dev/null

prepare_instance "$https_home" 127.0.0.1:28341 true
start_instance "$https_home" "$test_root/https.log"
wait_health "$https_url" true
"$SYNCSHELL_CORE_PATH" status --json --host-id standalone \
  --config "$https_home/config.xml" >"$test_root/https.json"
jq -e '.state.connection.online and
  .state.connection.endpoint == "https://127.0.0.1:28341"' \
  "$test_root/https.json" >/dev/null

systemctl --user start syncthing.service
for _ in $(seq 1 120); do
  [[ $(systemctl --user is-active syncthing.service || true) == active ]] && break
  sleep 0.1
done
for _ in $(seq 1 120); do
  syncthing cli show system >/dev/null 2>&1 && break
  sleep 0.1
done
syncthing cli show system >/dev/null
syncthing cli config options global-ann-enabled set false >/dev/null
syncthing cli config options local-ann-enabled set false >/dev/null
syncthing cli config options relays-enabled set false >/dev/null
syncthing cli config options natenabled set false >/dev/null
"$SYNCSHELL_CORE_PATH" status --json --host-id standalone \
  --lifecycle-kind systemd-user --lifecycle-authorized \
  --lifecycle-unit syncthing.service >"$test_root/managed.json"
jq -e '.state.connection.online and
  .state.lifecycle.classification == "managed" and
  .state.lifecycle.canControl == true' "$test_root/managed.json" >/dev/null
systemctl --user stop syncthing.service

for output in "$test_root"/*.json "$test_root"/*.jsonl \
    "$test_root"/*.stderr; do
  if [[ -f $output ]] && grep -Fq -- "$http_key" "$output"; then
    printf 'native core VM output exposed a credential: %s\n' "$output" >&2
    exit 1
  fi
done

settings_hash_after=$(settings_hash)
settings_mode_after=$(settings_mode)
[[ $settings_hash_after == "$settings_hash_before" ]]
[[ $settings_mode_after == "$settings_mode_before" ]]
[[ $(systemctl --user is-enabled syncthing.service || true) == "$initial_unit_file_state" ]]

binary_sha=$(sha256sum "$SYNCSHELL_CORE_PATH" | awk '{print $1}')
source_commit=$(<"$HOME/syncshell-vm/source-ref")
jq -n \
  --arg sourceCommit "$source_commit" \
  --arg binarySha256 "$binary_sha" \
  --arg syncthingVersion "$(syncthing --version | head -1)" \
  --arg settingsHash "$settings_hash_after" \
  --arg settingsMode "$settings_mode_after" \
  --arg unitActiveBefore "$unit_active_before" \
  --arg unitFileBefore "$unit_file_before" \
  '{phase:"02", status:"passed", sourceCommit:$sourceCommit,
    binarySha256:$binarySha256, syncthingVersion:$syncthingVersion,
    settings:{sha256:$settingsHash, mode:$settingsMode},
    issue45:{probeIntervals:2, online:true, rescan:true,
      classification:"external", canControl:false,
      unitActiveState:$unitActiveBefore, unitFileState:$unitFileBefore},
    managed:{online:true, classification:"managed", canControl:true},
    transports:{http:true, httpsPinned:true},
    discovery:{automatic:true, explicitConfig:true, missingBinary:true},
    failures:{wrongCredential:true, malformedConfig:true},
    credentialsExposed:false}' >"$result"

printf 'native core VM test passed: %s\n' "$result"
