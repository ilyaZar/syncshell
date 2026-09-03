#!/bin/bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

fail() {
  printf 'native core architecture test failed: %s\n' "$*" >&2
  exit 1
}

packages=(protocol session syncthing systemduser)
for package in "${packages[@]}"; do
  [[ -d $root/core/internal/$package ]] \
    || fail "missing native-core package $package"
done

mapfile -t actual_packages < <(
  find "$root/core/internal" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' \
    | sort
)
[[ ${actual_packages[*]} == "protocol session syncthing systemduser" ]] \
  || fail "unexpected native-core package layout"

grep -Fxq 'OmarchyPanel {}' "$root/Panel.qml" \
  || fail "root panel does not delegate to Omarchy"
grep -Fxq 'OmarchyService {}' "$root/Service.qml" \
  || fail "root service does not delegate to Omarchy"
[[ $(rg -l 'CoreProcess[[:space:]]*\{' "$root/hosts/omarchy" -g '*.qml' \
  | wc -l) -eq 1 ]] || fail "Omarchy does not own exactly one CoreProcess"

removed=(
  core/ActivityTracker.qml
  core/ApiClient.qml
  core/FolderController.qml
  core/InstallationController.qml
  models/FolderModel.js
  models/ServiceStateModel.js
  models/SyncthingApi.js
  scripts/syncthing-api.sh
)
for path in "${removed[@]}"; do
  [[ ! -e $root/$path ]] || fail "superseded owner remains at $path"
done

if rg -n 'qs[.]Commons|qs[.]Ui|omarchy' \
    "$root/shared" "$root/hosts/standalone" >/dev/null; then
  fail "standalone process boundary imports Omarchy"
fi
if rg -n 'settings[.]toml|icon_style|web_ui_theme|ilyazar[.]syncthing' \
    -g '*.go' "$root/core" >/dev/null; then
  fail "native core owns Omarchy settings"
fi
if rg -n -i 'api[-_]?key|x-api-key|rest/|config[.]xml|systemctl|events[?]' \
    "$root/shared" "$root/hosts/standalone" >/dev/null; then
  fail "generic QML boundary contains domain or credential logic"
fi

mapfile -t host_sources < <(
  find "$root/hosts/omarchy" -type f \
    \( -name '*.qml' -o -name '*.js' -o -name '*.sh' \) \
    ! -name syncthing-install.sh -print
)
if rg -n -i \
    'api[-_]?key|x-api-key|rest/|config[.]xml|systemctl|RemoteDownloadProgress' \
    "${host_sources[@]}" >/dev/null; then
  fail "Omarchy host contains deleted domain or lifecycle logic"
fi

grep -Fq 'pluginRoot + "/bin/x86_64/syncshell-core"' \
  "$root/shared/CoreProcess.qml" || fail "exact bundled path is missing"
if rg -n 'GOARCH|go build|command -v syncshell|syncshell-core.*(curl|wget)' \
    "$root/shared" "$root/hosts/omarchy" >/dev/null; then
  fail "production host contains build, download, or PATH fallback logic"
fi
if rg -n -- '--api-key|APIKey string `json|apiKey.*json' "$root/core" \
    >/dev/null; then
  fail "native core exposes an API-key argument or JSON field"
fi
if rg -n -g '!**/*_test.go' \
    'net[.]Listen|ListenUnix|unixgram|socket activation' "$root/core" \
    >/dev/null; then
  fail "native core contains a daemon control socket path"
fi

printf '%s\n' 'native core architecture test passed'
