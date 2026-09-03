#!/bin/bash
set -euo pipefail

[[ ${1:-} == stream ]]
[[ -n ${SYNCSHELL_RECOVERY_MARKER:-} ]]
[[ -f $SYNCSHELL_RECOVERY_MARKER ]] || exit 23

printf '%s\n' \
  '{"v":1,"type":"hello","build":{"version":"test","protocol":1},"capabilities":[]}' \
  '{"v":1,"type":"snapshot","revision":1,"state":{"connection":{"phase":"ready","online":true},"installation":{"available":false},"lifecycle":{"classification":"external","available":true,"active":false,"targetMatch":true,"canControl":false,"canStart":false},"counts":{},"folders":[]}}'

while IFS= read -r line; do
  id=$(jq -er '.id' <<<"$line")
  type=$(jq -er '.type' <<<"$line")
  printf '{"v":1,"type":"result","id":"%s","ok":true,"revision":1}\n' "$id"
  if [[ $type == shutdown ]]; then
    printf '%s\n' '{"v":1,"type":"end","reason":"shutdown"}'
    exit 0
  fi
done

printf '%s\n' '{"v":1,"type":"end","reason":"stdin"}'
