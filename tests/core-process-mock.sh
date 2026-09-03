#!/bin/bash
set -euo pipefail

[[ ${1:-} == stream ]]

printf '%s\n' \
  '{"v":1,"type":"hello","build":{"version":"test","protocol":1},"capabilities":[]}' \
  '{"v":1,"type":"snapshot","revision":1,"state":{"connection":{"online":true},"identity":{"deviceId":"TEST-ID"},"folders":[{"id":"folder"}]}}'

while IFS= read -r line; do
  id=$(jq -er '.id' <<<"$line")
  type=$(jq -er '.type' <<<"$line")
  case $type in
    configure|refresh|action)
      printf '{"v":1,"type":"result","id":"%s","ok":true,"revision":1}\n' "$id"
      ;;
    shutdown)
      printf '{"v":1,"type":"result","id":"%s","ok":true,"revision":1}\n' "$id"
      printf '%s\n' '{"v":1,"type":"end","reason":"shutdown"}'
      exit 0
      ;;
    *) exit 1 ;;
  esac
done

printf '%s\n' '{"v":1,"type":"end","reason":"stdin"}'
