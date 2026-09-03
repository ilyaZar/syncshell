#!/bin/bash
set -euo pipefail

: "${SYNCSHELL_CORE_PATH:?missing core path}"

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d /tmp/syncshell-native-parity.XXXXXX)
artifact_root=${SYNCSHELL_VM_ARTIFACT_ROOT:-$HOME/syncshell-vm/artifacts}
result="$artifact_root/phase03-native-core.json"
home_a="$test_root/a"
home_b="$test_root/b"
folder_a="$test_root/folder-a"
folder_b="$test_root/folder-b"
stream="$test_root/stream.jsonl"
fifo="$test_root/requests.fifo"
pid_a=""
pid_b=""
core_pid=""
settings=$HOME/.config/omarchy/ilyazar.syncthing/settings.toml
unit_active_before=$(systemctl --user is-active syncthing.service || true)
unit_file_before=$(systemctl --user is-enabled syncthing.service || true)

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
  exec 9>&- 2>/dev/null || true
  for pid in "$core_pid" "$pid_a" "$pid_b"; do
    if [[ -n $pid ]] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
    fi
  done
  find "$test_root" -depth -delete
}
trap cleanup EXIT
trap 'printf "native core parity VM test failed at line %s\n" "$LINENO" >&2' ERR

for command in curl jq sha256sum syncthing systemctl xmlstarlet; do
  command -v "$command" >/dev/null 2>&1 || {
    printf 'missing parity-test command: %s\n' "$command" >&2
    exit 1
  }
done
[[ -x $SYNCSHELL_CORE_PATH ]]
mkdir -p -- "$artifact_root" "$home_a" "$home_b" "$folder_a" "$folder_b"

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
  local home=$1 gui_port=$2 listen_port=$3
  STHOMEDIR="$home" syncthing generate "$(port_probe_flag generate)" \
    >/dev/null
  xmlstarlet ed -L \
    -d '/configuration/folder' \
    -d '/configuration/options/listenAddress' \
    -s '/configuration/options' -t elem -n listenAddress \
      -v "tcp://127.0.0.1:$listen_port" \
    -u '/configuration/gui/address' -v "127.0.0.1:$gui_port" \
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
  instance_pid=$!
}

wait_health() {
  local port=$1
  for _ in $(seq 1 120); do
    curl --silent --fail --noproxy '*' \
      "http://127.0.0.1:$port/rest/noauth/health" >/dev/null 2>&1 && return 0
    sleep 0.1
  done
  return 1
}

wait_result() {
  local id=$1 ok=$2 seconds=${3:-20}
  for _ in $(seq 1 $((seconds * 10))); do
    if jq -s -e --arg id "$id" --argjson ok "$ok" \
        'any(.[]; .type == "result" and .id == $id and .ok == $ok)' \
        "$stream" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.1
  done
  return 1
}

wait_snapshot() {
  local expression=$1 seconds=${2:-20}
  for _ in $(seq 1 $((seconds * 10))); do
    if jq -s -e "any(.[]; .type == \"snapshot\" and ($expression))" \
        "$stream" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.1
  done
  return 1
}

send_json() {
  printf '%s\n' "$1" >&9
}

wait_file_hash() {
  local path=$1 expected=$2 seconds=${3:-30} actual
  for _ in $(seq 1 "$seconds"); do
    if [[ -f $path ]]; then
      actual=$(sha256sum "$path" | awk '{print $1}')
      [[ $actual == "$expected" ]] && return 0
    fi
    sleep 1
  done
  return 1
}

prepare_instance "$home_a" 28540 23540
prepare_instance "$home_b" 28541 23541
start_instance "$home_a" "$test_root/a.log"
pid_a=$instance_pid
start_instance "$home_b" "$test_root/b.log"
pid_b=$instance_pid
wait_health 28540
wait_health 28541

id_a=$(syncthing cli --home="$home_a" show system | jq -er .myID)
id_b=$(syncthing cli --home="$home_b" show system | jq -er .myID)
device_b=$(syncthing cli --home="$home_a" config defaults device dump-json |
  jq --arg id "$id_b" '.deviceID=$id | .name="parity-b" |
    .addresses=["tcp://127.0.0.1:23541"]')
device_a=$(syncthing cli --home="$home_b" config defaults device dump-json |
  jq --arg id "$id_a" '.deviceID=$id | .name="parity-a" |
    .addresses=["tcp://127.0.0.1:23540"]')
syncthing cli --home="$home_a" config devices add-json "$device_b" >/dev/null
syncthing cli --home="$home_b" config devices add-json "$device_a" >/dev/null

folder=$(syncthing cli --home="$home_b" config defaults folder dump-json |
  jq --arg path "$folder_b" --arg local "$id_b" --arg remote "$id_a" '
    .id="parity" | .label="Native parity" | .path=$path |
    .paused=false | .fsWatcherEnabled=true | .fsWatcherDelayS=1 |
    .rescanIntervalS=1 |
    .devices=[{deviceID:$local},{deviceID:$remote}]')
syncthing cli --home="$home_b" config folders add-json "$folder" >/dev/null
for _ in $(seq 1 200); do
  pending=$(syncthing cli --home="$home_a" show pending folders 2>/dev/null || true)
  jq -e 'has("parity")' <<<"${pending:-{}}" >/dev/null 2>&1 && break
  sleep 0.1
done
jq -e 'has("parity")' <<<"$pending" >/dev/null

mkfifo "$fifo"
"$SYNCSHELL_CORE_PATH" stream --host-id standalone \
  --config "$home_a/config.xml" --probe-interval-seconds 2 \
  <"$fifo" >"$stream" 2>"$test_root/core.stderr" &
core_pid=$!
exec 9>"$fifo"
wait_snapshot '.state.connection.online == true and
  (.state.pendingFolders | has("parity"))'

send_json '{"v":1,"type":"configure","id":"1","config":{"probeIntervalSeconds":1,"desiredServiceState":"disabled"}}'
wait_result 1 true
add_request=$(jq -cn --arg path "$folder_a" --arg peer "$id_b" '
  {v:1,type:"action",id:"2",action:"folder.add-existing",
    args:{folderId:"parity",path:$path,label:"Native parity",
      deviceIds:[$peer],pendingDeviceId:$peer}}')
send_json "$add_request"
wait_result 2 true

printf '%s\n' 'from b to a' >"$folder_b/from-b.txt"
hash_b=$(sha256sum "$folder_b/from-b.txt" | awk '{print $1}')
wait_file_hash "$folder_a/from-b.txt" "$hash_b" 30

printf '%s\n' 'from a to b' >"$folder_a/from-a.txt"
hash_a=$(sha256sum "$folder_a/from-a.txt" | awk '{print $1}')
send_json '{"v":1,"type":"action","id":"3","action":"folder.rescan","args":{"folderId":"parity"}}'
wait_result 3 true
wait_file_hash "$folder_b/from-a.txt" "$hash_a" 30

send_json '{"v":1,"type":"action","id":"4","action":"folder.pause","args":{"folderId":"parity"}}'
wait_result 4 true
printf '%s\n' 'blocked while paused' >"$folder_b/blocked.txt"
sleep 3
test ! -e "$folder_a/blocked.txt"
send_json '{"v":1,"type":"action","id":"5","action":"folder.resume","args":{"folderId":"parity"}}'
wait_result 5 true
blocked_hash=$(sha256sum "$folder_b/blocked.txt" | awk '{print $1}')
wait_file_hash "$folder_a/blocked.txt" "$blocked_hash" 30

mv "$folder_b/from-b.txt" "$folder_b/renamed.txt"
unlink "$folder_b/blocked.txt"
renamed_hash=$(sha256sum "$folder_b/renamed.txt" | awk '{print $1}')
wait_file_hash "$folder_a/renamed.txt" "$renamed_hash" 30
for _ in $(seq 1 30); do
  [[ ! -e $folder_a/from-b.txt && ! -e $folder_a/blocked.txt ]] && break
  sleep 1
done
test ! -e "$folder_a/from-b.txt"
test ! -e "$folder_a/blocked.txt"

kill "$pid_a"
wait "$pid_a" 2>/dev/null || true
pid_a=""
wait_snapshot '.state.connection.fresh == false or
  .state.connection.online == false' 15
recovery_revision=$(jq -s '[.[] | select(.type == "snapshot" and
  (.state.connection.fresh == false or .state.connection.online == false)) |
  .revision] | max' "$stream")
start_instance "$home_a" "$test_root/a-restarted.log"
pid_a=$instance_pid
wait_health 28540
wait_snapshot ".revision > $recovery_revision and
  .state.connection.online == true and
  .state.connection.fresh == true" 20

send_json '{"v":1,"type":"action","id":"6","action":"folder.rescan-all","args":{}}'
wait_result 6 true
send_json '{"v":1,"type":"action","id":"7","action":"folder.suggest-id","args":{}}'
wait_result 7 true
send_json '{"v":1,"type":"action","id":"8","action":"webui.set-theme","args":{"theme":"default"}}'
wait_result 8 true

send_json '{"v":1,"type":"action","id":"9","action":"folder.pause","args":{"folderId":"parity"}}'
wait_result 9 true
retained_hash=$(sha256sum "$folder_a/renamed.txt" | awk '{print $1}')
send_json '{"v":1,"type":"action","id":"10","action":"folder.forget","args":{"folderId":"parity"}}'
wait_result 10 true
wait_file_hash "$folder_a/renamed.txt" "$retained_hash" 5
for _ in $(seq 1 100); do
  if ! syncthing cli --home="$home_a" config folders list | grep -qx parity; then
    break
  fi
  sleep 0.1
done
if syncthing cli --home="$home_a" config folders list | grep -qx parity; then
  exit 1
fi

send_json '{"v":1,"type":"shutdown","id":"11"}'
wait_result 11 true
exec 9>&-
wait "$core_pid"
core_pid=""

jq -s -e 'any(.[]; .type == "snapshot" and
  ((.state.activity.files // []) | length > 0))' "$stream" >/dev/null

xmlstarlet sel -t -v '/configuration/gui/apikey' "$home_a/config.xml" \
  >"$test_root/credentials.pattern"
printf '\n' >>"$test_root/credentials.pattern"
xmlstarlet sel -t -v '/configuration/gui/apikey' "$home_b/config.xml" \
  >>"$test_root/credentials.pattern"
chmod 600 "$test_root/credentials.pattern"
if grep -Fqf "$test_root/credentials.pattern" "$stream" \
    "$test_root/core.stderr"; then
  printf '%s\n' 'parity output exposed an API credential' >&2
  exit 1
fi

settings_hash_after=$(settings_hash)
settings_mode_after=$(settings_mode)
[[ $settings_hash_after == "$settings_hash_before" ]]
[[ $settings_mode_after == "$settings_mode_before" ]]
[[ $(systemctl --user is-active syncthing.service || true) == "$unit_active_before" ]]
[[ $(systemctl --user is-enabled syncthing.service || true) == "$unit_file_before" ]]

binary_sha=$(sha256sum "$SYNCSHELL_CORE_PATH" | awk '{print $1}')
if [[ -f $HOME/syncshell-vm/source-ref ]]; then
  source_commit=$(<"$HOME/syncshell-vm/source-ref")
else
  source_commit=$(git -C "$root" rev-parse HEAD)
fi
jq -n \
  --arg sourceCommit "$source_commit" \
  --arg binarySha256 "$binary_sha" \
  --arg syncthingVersion "$(syncthing --version | head -1)" \
  --arg settingsHash "$settings_hash_after" \
  --arg settingsMode "$settings_mode_after" \
  --arg retainedHash "$retained_hash" \
  '{phase:"03",status:"passed",sourceCommit:$sourceCommit,
    binarySha256:$binarySha256,syncthingVersion:$syncthingVersion,
    settings:{sha256:$settingsHash,mode:$settingsMode},
    topology:{isolatedNodes:2,transport:"guest loopback",
      discovery:false,relays:false,nat:false,upgrades:false},
    behaviors:{pendingOffer:true,addExisting:true,bidirectionalHashes:true,
      activity:true,
      pauseBlockedDelivery:true,resumeDelivered:true,rename:true,delete:true,
      networkInterruption:true,restartRecovery:true,configure:true,
      rescan:true,rescanAll:true,suggestId:true,theme:true,
      forgetRetainedData:true},
    retainedDataSha256:$retainedHash,credentialsExposed:false}' >"$result"

printf 'native core parity VM test passed: %s\n' "$result"
