#!/bin/bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d /tmp/syncthing-plugin-tests.XXXXXX)
trap 'find "$test_root" -depth -delete' EXIT

fail() {
  printf 'scripts.test.sh: %s\n' "$*" >&2
  exit 1
}

test_settings() {
  local target="$test_root/settings/config/settings.toml"
  bash "$root/scripts/syncthing-settings.sh" ensure \
    "$root/config/settings.toml" "$target" themed >/dev/null
  grep -q '^version = 1$' "$target" \
    || fail "settings version was not seeded"
  grep -q '^\[style\]$' "$target" \
    || fail "style section was not seeded"
  grep -Eq '^icon_style[[:space:]]*=[[:space:]]*"themed"' "$target" \
    || fail "legacy icon choice was not seeded"
  grep -Eq '^service_state[[:space:]]*=[[:space:]]*"enabled"' "$target" \
    || fail "service state was not seeded"

  bash "$root/scripts/syncthing-settings.sh" set-service-state \
    "$root/config/settings.toml" "$target" themed disabled >/dev/null
  grep -Eq '^service_state[[:space:]]*=[[:space:]]*"disabled"' "$target" \
    || fail "service state was not updated"
  [[ $(grep -c '^service_state[[:space:]]*=' "$target") == 1 ]] \
    || fail "service state update created a duplicate"
  grep -Eq '^icon_style[[:space:]]*=[[:space:]]*"themed"' "$target" \
    || fail "service state update changed icon style"

  local legacy="$test_root/settings/config/legacy.toml"
  printf '%s\n' \
    'icon_style = "branded"' \
    'web_ui_theme = "default"' \
    >"$legacy"
  bash "$root/scripts/syncthing-settings.sh" set-service-state \
    "$root/config/settings.toml" "$legacy" branded disabled >/dev/null
  grep -Fxq '[service]' "$legacy" \
    || fail "legacy settings did not receive a service section"
  grep -Eq '^service_state[[:space:]]*=[[:space:]]*"disabled"' "$legacy" \
    || fail "legacy settings did not receive the service state"
  grep -Fxq 'web_ui_theme = "default"' "$legacy" \
    || fail "legacy settings were not preserved"

  local invalid="$test_root/settings/config/invalid.toml"
  local invalid_before
  printf '%s\n' \
    'icon_style = "branded"' \
    'web_ui_theme = "default"' \
    '[service]' \
    'service_state = "enabled"' \
    'service_state = "disabled"' \
    >"$invalid"
  invalid_before=$(<"$invalid")
  if bash "$root/scripts/syncthing-settings.sh" set-service-state \
      "$root/config/settings.toml" "$invalid" branded enabled \
      >/dev/null 2>&1; then
    fail "invalid service settings update succeeded"
  fi
  [[ $(<"$invalid") == "$invalid_before" ]] \
    || fail "failed service settings update changed the file"

  printf '%s\n' '# user-owned' >"$target"
  bash "$root/scripts/syncthing-settings.sh" ensure \
    "$root/config/settings.toml" "$target" branded >/dev/null
  [[ $(<"$target") == "# user-owned" ]] \
    || fail "existing settings were overwritten"
}

test_installation_status() {
  local sandbox="$test_root/installation-status"
  local fake_bin="$sandbox/bin"
  local output
  mkdir -p -- "$fake_bin" "$sandbox/home" "$sandbox/runtime"
  printf '%s\n' '#!/bin/bash' 'exit 0' >"$fake_bin/syncthing"
  printf '%s\n' \
    '#!/bin/bash' \
    'set -euo pipefail' \
    'case " $* " in' \
    '  *" --property=LoadState "*) printf '\''loaded\n'\'' ;;' \
    '  *" --property=ActiveState "*) printf '\''inactive\n'\'' ;;' \
    '  *" --property=UnitFileState "*) printf '\''disabled\n'\'' ;;' \
    '  *) exit 1 ;;' \
    'esac' \
    >"$fake_bin/systemctl"
  chmod 700 -- "$fake_bin/syncthing" "$fake_bin/systemctl"

  output=$(HOME="$sandbox/home" \
    XDG_RUNTIME_DIR="$sandbox/runtime" \
    PATH="$fake_bin:$PATH" \
    bash "$root/scripts/syncthing-install.sh" status)
  jq -e '
    .state == "existing"
    and .serviceAvailable == true
    and .serviceRunning == false
    and .serviceActiveState == "inactive"
    and .unitFileState == "disabled"
  ' <<<"$output" >/dev/null \
    || fail "installation status omitted systemd service state"
}

test_themes() {
  local theme colors version
  local themes_root="$HOME/.local/share/omarchy/themes"
  local default_gui="$test_root/default-gui"
  local default_index="$default_gui/theme-assets/default/index.html"
  mkdir -p -- "$(dirname -- "$default_index")"
  printf '%s\n' \
    '<!doctype html>' \
    '<html><head><title>Syncthing</title></head><body></body></html>' \
    >"$default_index"
  if [[ -d $themes_root ]]; then
    while IFS= read -r colors; do
      theme=$(basename -- "$(dirname -- "$colors")")
      SYNCTHING_GUI_URL="file://$default_gui" \
        bash "$root/scripts/syncthing-theme.sh" generate \
          "$test_root/themes/$theme" "$colors" >/dev/null
      grep -Fxq '@import "/theme-assets/default/assets/css/theme.css";' \
        "$test_root/themes/$theme/syncthing-omarchy/assets/css/theme.css" \
        || fail "$theme did not inherit the Syncthing default theme"
      ! grep -R -q '{{' "$test_root/themes/$theme" \
        || fail "$theme left unresolved palette values"
    done < <(find "$themes_root" -mindepth 2 -maxdepth 2 \
      -type f -name colors.toml -print | sort)
  fi

  local user_theme="$test_root/user-theme/colors.toml"
  local user_palette="$test_root/themes/user/syncthing-omarchy/assets/css/omarchy_syncthing_theme.css"
  mkdir -p -- "$(dirname -- "$user_theme")"
  printf '%s\n' \
    'background = "#120f18"' \
    'foreground = "#e8dff2"' \
    'accent = "#ff7ab2"' \
    'color1 = "#ff5370"' \
    'color2 = "#c3e88d"' \
    'color3 = "#ffcb6b"' \
    'color4 = "#82aaff"' \
    'color5 = "#c792ea"' \
    'color6 = "#89ddff"' \
    >"$user_theme"
  SYNCTHING_GUI_URL="file://$default_gui" \
    bash "$root/scripts/syncthing-theme.sh" generate \
      "$test_root/themes/user" "$user_theme" >/dev/null
  grep -Fxq '@import "/theme-assets/default/assets/css/theme.css";' \
    "$test_root/themes/user/syncthing-omarchy/assets/css/theme.css" \
    || fail "user theme did not inherit the Syncthing default theme"
  ! grep -R -q '{{' "$test_root/themes/user" \
    || fail "user theme left unresolved palette values"
  for color in '#120f18' '#e8dff2' '#ff7ab2' '#ff5370' '#c3e88d' \
      '#ffcb6b' '#82aaff' '#c792ea' '#89ddff'; do
    grep -Fq "$color" "$user_palette" \
      || fail "user theme omitted palette color $color"
  done

  local user_root="$test_root/themes/user/syncthing-omarchy"
  version=$(<"$user_root/theme-version.txt")
  [[ $version =~ ^[A-Za-z0-9._-]+$ ]] \
    || fail "generated theme version is invalid"
  grep -Fq "omarchy_syncthing_theme.css?v=$version" \
    "$user_root/assets/css/theme.css" \
    || fail "theme wrapper did not pin the generated palette"
  grep -Fq "data-theme-version=\"$version\"" "$user_root/index.html" \
    || fail "Web UI did not receive the generated theme version"
  grep -Fq 'src="assets/js/omarchy_theme_refresh.js"' \
    "$user_root/index.html" \
    || fail "Web UI did not load the theme refresh helper"
  cmp -s -- "$root/webui/omarchy_theme_refresh.js" \
    "$user_root/assets/js/omarchy_theme_refresh.js" \
    || fail "generated theme refresh helper differs from its source"
  [[ -z $(find "$user_root" -maxdepth 1 -type f \
    -name '.default-index.html.*' -print -quit) ]] \
    || fail "generated theme retained its default index source"
}

install_fake_plugin() {
  local source=$1
  local target=$2
  local install_kind=$3

  mkdir -p -- "$(dirname -- "$target")"
  if [[ $install_kind == link ]]; then
    mkdir -p -- "$source"
    cp -- "$root/manifest.json" "$source/manifest.json"
    ln -s -- "$source" "$target"
  else
    mkdir -p -- "$target"
    cp -- "$root/manifest.json" "$target/manifest.json"
  fi
}

test_removal_mode() {
  local mode=$1
  local install_kind=$2
  local sandbox="$test_root/removal-$mode-$install_kind"
  local source="$sandbox/source"
  local installed="$sandbox/config/omarchy/plugins/io.github.ilyazar.syncthing"
  local plugin_config="$sandbox/config/omarchy/ilyazar.syncthing"
  local gui_assets="$sandbox/gui"
  local fake_bin="$sandbox/bin"

  [[ $install_kind == link ]] || source=$installed
  install_fake_plugin "$source" "$installed" "$install_kind"
  mkdir -p -- "$plugin_config" \
    "$gui_assets/syncthing-omarchy/assets/css" "$fake_bin"
  printf '%s\n' 'icon_style = "themed"' >"$plugin_config/settings.toml"
  printf '%s\n' 'generated' \
    >"$gui_assets/syncthing-omarchy/assets/css/theme.css"
  # Fake variables expand only when the generated command runs.
  # shellcheck disable=SC2016
  printf '%s\n' '#!/bin/bash' \
    'set -euo pipefail' \
    '[[ $1 == plugin && $2 == remove ]]' \
    'if [[ -L $FAKE_PLUGIN_TARGET ]]; then' \
    '  unlink -- "$FAKE_PLUGIN_TARGET"' \
    'else' \
    '  find "$FAKE_PLUGIN_TARGET" -depth -delete' \
    'fi' \
    >"$fake_bin/omarchy"
  printf '%s\n' '#!/bin/bash' 'exit 0' \
    >"$fake_bin/omarchy-notification-send"
  chmod 700 -- "$fake_bin/omarchy" "$fake_bin/omarchy-notification-send"

  HOME="$sandbox/home" \
    XDG_CONFIG_HOME="$sandbox/config" \
    XDG_STATE_HOME="$sandbox/state" \
    XDG_RUNTIME_DIR="$sandbox/runtime" \
    FAKE_PLUGIN_TARGET="$installed" \
    PATH="$fake_bin:$PATH" \
    bash "$root/scripts/syncthing-remove.sh" _worker \
      "$source" "$gui_assets" "$mode"

  if [[ $install_kind == link ]]; then
    [[ -d $source ]] \
      || fail "$mode removal deleted the linked source checkout"
  else
    [[ ! -e $source ]] \
      || fail "$mode removal left the installed checkout"
  fi
  [[ ! -e $installed && ! -L $installed ]] \
    || fail "$mode removal left the installed link"
  [[ ! -e $gui_assets/syncthing-omarchy ]] \
    || fail "$mode removal left generated theme assets"
  if [[ $mode == preserve ]]; then
    [[ -f $plugin_config/settings.toml ]] \
      || fail "preserve removal deleted plugin settings"
  else
    [[ ! -e $plugin_config ]] \
      || fail "purge removal left plugin settings"
  fi
}

test_settings
test_installation_status
test_themes
test_removal_mode preserve link
test_removal_mode purge link
test_removal_mode preserve directory
test_removal_mode purge directory
printf 'all script tests passed\n'
