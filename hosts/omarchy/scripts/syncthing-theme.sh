#!/bin/bash
set -euo pipefail

usage() {
  printf 'Usage: syncthing-theme.sh generate <gui-assets-dir> [colors.toml]\n' >&2
  exit 2
}

[[ ${1:-} == "generate" && ( $# == 2 || $# == 3 ) ]] || usage

assets_root=$2
colors_file=${3:-}
theme_root="$assets_root/syncthing-omarchy"
theme_dir="$theme_root/assets/css"
script_dir="$theme_root/assets/js"
gui_url=${SYNCTHING_GUI_URL:-https://127.0.0.1:8384}
default_index_url="${gui_url%/}/theme-assets/default/index.html"
refresh_source="$(dirname -- "$0")/../webui/omarchy_theme_refresh.js"

declare -A colors=()
if [[ -n $colors_file ]]; then
  color_command=(omarchy-theme-color --file "$colors_file" --all)
else
  color_command=(omarchy-theme-color --all)
fi
while IFS=$'\t' read -r key value; do
  [[ $key =~ ^[A-Za-z0-9_-]+$ ]] || continue
  [[ $value =~ ^#[0-9A-Fa-f]{6}$|^(dark|light)$ ]] || continue
  colors[$key]=$value
done < <("${color_command[@]}")

required=(
  background foreground accent muted selection
  lighter_background darker_background dark_foreground light_foreground
  red yellow green cyan blue magenta orange
)
for key in "${required[@]}"; do
  [[ -n ${colors[$key]:-} ]] || {
    printf 'Omarchy theme is missing the resolved color %s\n' "$key" >&2
    exit 1
  }
done

mkdir -p -- "$theme_dir" "$script_dir"
wrapper_tmp=$(mktemp --tmpdir="$theme_dir" .theme.css.XXXXXX)
palette_tmp=$(mktemp --tmpdir="$theme_dir" .omarchy-theme.css.XXXXXX)
refresh_tmp=$(mktemp --tmpdir="$script_dir" .omarchy-theme-refresh.js.XXXXXX)
index_source_tmp=$(mktemp --tmpdir="$theme_root" .default-index.html.XXXXXX)
index_tmp=$(mktemp --tmpdir="$theme_root" .index.html.XXXXXX)
version_tmp=$(mktemp --tmpdir="$theme_root" .theme-version.txt.XXXXXX)
trap 'rm -f -- "$wrapper_tmp" "$palette_tmp" "$refresh_tmp" \
  "$index_source_tmp" "$index_tmp" "$version_tmp"' EXIT

generation="${EPOCHREALTIME//[.,]/}-$RANDOM"

printf '%s\n' \
  "/* omarchy-generation: $generation */" \
  '@import "/theme-assets/default/assets/css/theme.css";' \
  "@import \"omarchy_syncthing_theme.css?v=$generation\";" \
  >"$wrapper_tmp"

sed \
  -e "s/{{background}}/${colors[background]}/g" \
  -e "s/{{foreground}}/${colors[foreground]}/g" \
  -e "s/{{accent}}/${colors[accent]}/g" \
  -e "s/{{muted}}/${colors[muted]}/g" \
  -e "s/{{selection}}/${colors[selection]}/g" \
  -e "s/{{surface}}/${colors[lighter_background]}/g" \
  -e "s/{{surface_dark}}/${colors[darker_background]}/g" \
  -e "s/{{foreground_dark}}/${colors[dark_foreground]}/g" \
  -e "s/{{foreground_light}}/${colors[light_foreground]}/g" \
  -e "s/{{red}}/${colors[red]}/g" \
  -e "s/{{yellow}}/${colors[yellow]}/g" \
  -e "s/{{green}}/${colors[green]}/g" \
  -e "s/{{cyan}}/${colors[cyan]}/g" \
  -e "s/{{blue}}/${colors[blue]}/g" \
  -e "s/{{magenta}}/${colors[magenta]}/g" \
  -e "s/{{orange}}/${colors[orange]}/g" \
  "$(dirname -- "$0")/../webui/omarchy_syncthing_theme.css" \
  >"$palette_tmp"

grep -q '{{' "$palette_tmp" && {
  printf 'Generated Syncthing theme contains unresolved colors\n' >&2
  exit 1
}

curl \
  --fail \
  --silent \
  --show-error \
  --insecure \
  --noproxy "*" \
  "$default_index_url" >"$index_source_tmp"

[[ $(grep -Fc '</head>' "$index_source_tmp") == 1 ]] || {
  printf 'Syncthing default Web UI has an unexpected document head\n' >&2
  exit 1
}

sed \
  "s#</head>#  <script defer src=\"assets/js/omarchy_theme_refresh.js\" data-theme-version=\"$generation\"></script>\n</head>#" \
  "$index_source_tmp" >"$index_tmp"
cp -- "$refresh_source" "$refresh_tmp"
printf '%s\n' "$generation" >"$version_tmp"

chmod 644 -- "$wrapper_tmp" "$palette_tmp" "$refresh_tmp" \
  "$index_tmp" "$version_tmp"
mv -- "$palette_tmp" "$theme_dir/omarchy_syncthing_theme.css"
mv -- "$wrapper_tmp" "$theme_dir/theme.css"
mv -- "$refresh_tmp" "$script_dir/omarchy_theme_refresh.js"
mv -- "$index_tmp" "$theme_root/index.html"
mv -- "$version_tmp" "$theme_root/theme-version.txt"
rm -f -- "$index_source_tmp"
trap - EXIT

printf '%s\n' "$theme_dir"
