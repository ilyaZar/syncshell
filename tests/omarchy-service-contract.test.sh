#!/bin/bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
fixture="$root/tests/fixtures/omarchy-service-contract.json"
facade="$root/hosts/omarchy/OmarchyService.qml"

fail() {
  printf 'omarchy service contract test failed: %s\n' "$*" >&2
  exit 1
}

jq -e '.version == "0.1.7"' "$fixture" >/dev/null \
  || fail "fixture version changed"

while IFS= read -r property; do
  rg -q "property [^:]+ ${property}([ :])" "$facade" \
    || fail "missing property $property"
done < <(jq -r '.properties[]' "$fixture")

while IFS= read -r method; do
  rg -q "function ${method}[(]" "$facade" \
    || fail "missing method $method"
done < <(jq -r '.methods[]' "$fixture")

while IFS= read -r member; do
  jq -e --arg member "$member" \
    '.properties + .methods | index($member) != null' "$fixture" >/dev/null \
    || fail "panel uses unrecorded service member $member"
done < <(
  rg -o 'syncthing[.]([A-Za-z][A-Za-z0-9]*)' \
    "$root/hosts/omarchy/OmarchyPanel.qml" "$root/hosts/omarchy/ui" \
    -g '*.qml' \
    | sed 's/.*syncthing[.]//' \
    | sort -u
)

grep -Fxq 'OmarchyPanel {}' "$root/Panel.qml" \
  || fail "root panel is not a thin delegate"
grep -Fxq 'OmarchyService {}' "$root/Service.qml" \
  || fail "root service is not a thin delegate"
rg -Uq 'remains fully usable with the retained[[:space:]]+0[.]1[.]7 service' \
  "$root/docs/omarchy-service-contract-0.1.7.md" \
  || fail "pre-restart service compatibility is not documented"

[[ $(sed -n '/AddFolderForm {/,/^                }/p' \
  "$root/hosts/omarchy/ui/SyncthingPanelPopup.qml" \
  | grep -c 'warning: root.controller.warning') -eq 1 ]] \
  || fail "add-folder warning binding is duplicated"
grep -Fq '&& (!root.syncthing.serviceAvailable || root.syncthing.serviceActive)' \
  "$root/hosts/omarchy/ui/PanelStatus.qml" \
  || fail "external online service is visually dimmed"

printf '%s\n' 'Omarchy service contract test passed'
