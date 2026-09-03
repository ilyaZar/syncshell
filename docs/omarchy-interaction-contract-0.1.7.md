# Omarchy interaction contract 0.1.7

This manifest freezes the released visual and interactive behavior for the
phase 01 baseline and phase 04 comparison. It does not prescribe a new design.

## Bar surface

- The widget occupies one normal Omarchy bar slot and opens the existing
  anchored panel.
- A left click toggles the panel. A right click requests a refresh.
- The plugin defines no wheel action.
- The icon uses `default`, `sync`, `pause`, or `notify` artwork. The themed mode
  tints the matching monochrome artwork with the bar foreground.
- Online icons are fully opaque; other states use 0.55 opacity.
- Problems activate the bar button. Busy state includes refresh, folder sync,
  scan, and current file activity.
- The tooltip is `Syncthing: <summary>`, except active synchronization uses
  `Syncthing: Sync in progress...` and a missing service object uses
  `Syncthing unavailable`.

## Panel geometry and focus

- Preferred content width is 380 Omarchy spacing units and maximum content
  height is 560.
- The panel opens focused, refreshes state, selects an available folder, and
  scrolls to the top.
- Closing resets More, settings, add, and confirmation views unless a folder
  picker temporarily owns the transition.
- Five or more folders use one selected card. Left and right move that
  selection; fewer folders remain simultaneously visible.
- Escape follows the innermost open dialog or view before closing the panel.

## Header and status

- The hero title is `Syncthing` with the local device name and branded status
  icon.
- `host ID` copies the current or remembered device ID and shows
  `Host ID copied`.
- The lifecycle toggle is shown only when `canControlService` is true. Its hint
  is `Start syncing` or `Stop syncing`.
- Status rows show folder count, connected devices as `<n> of <n> connected`,
  and tracked files and bytes.
- Warning, error, and success notice rows retain their colors, order, wrapping,
  and message timing.

## Folder surface

- Each folder card opens its directory, copies its folder ID, shows the folder
  status and path, and offers `RESCAN` when active or `FORGET` when paused.
- Status badges are `SYNCED`, `SYNCING`, `LINKED`, `UNLINKED`, `ERROR`, or
  `UNKNOWN` with the released colors and precedence.
- Current file activity displays `File syncing`, aligned animated dots, and a
  file detail. Upload and removal use their released green and red wording.
- `More` and `Less` toggle the extended controls.
- The selected-folder controls offer `+`, `LINK`, `UNLINK`, or `WAIT`.
- Pending unencrypted offers appear with `ACCEPT`. Encrypted offers direct the
  user to the Syncthing Web UI.
- `Rescan all directories` and the `r` key rescan every folder when allowed.

## Add and forget flows

- Add contains pending-offer selection, existing-directory path and `BROWSE`,
  label, folder ID and `NEW ID`, device multi-select and `OK`, and the final
  `ADD FOLDER` action.
- Path and ID are required before submission. Empty labels derive from the
  directory name. No selected remote device means local only.
- The folder picker closes the panel, floats a native folder dialog, restores
  the panel, and keeps the add form. Failure permits manual entry.
- Forget is visible only for a paused folder and asks for confirmation with the
  exact folder ID and local-data preservation warning.

## Installation, settings, theme, and removal

- Installation states are checking, existing, incomplete, and missing.
  `Install Syncthing` opens the host-owned Omarchy terminal workflow only when
  installation is safe.
- The settings menu rows are `Open settings file`,
  `Cleanly remove Syncthing plugin`, and `Back [q / Esc]`.
- The settings file remains
  `~/.config/omarchy/ilyazar.syncthing/settings.toml` with mode `0600` when
  created by the plugin.
- The four fields remain `style.icon_style` (`branded`),
  `style.web_ui_theme` (`omarchy`), `service.service_state` (`enabled`), and
  `service.probe_interval_seconds` (`15`). Values in parentheses are defaults.
- Existing settings files are not overwritten. Service-state writes preserve
  unrelated content and the existing mode.
- Omarchy owns palette generation and cleanup. Syncthing owns the selected Web
  UI theme. `default` and `syncthing-omarchy` remain the concrete choices.
- Removal offers preserve settings, delete settings, or abort. Both removal
  paths restore the default Web UI when needed, remove generated theme assets,
  and use native plugin removal without touching Syncthing configuration or
  synchronized data.

## Keyboard contract

- Main view: `r` rescans all, `w` opens the Web UI, `p` toggles an authorized
  service, `s` opens settings, and `q` or Escape closes.
- Settings: `j`, `k`, Up, Down, and Tab move; Enter selects; `q` or Escape
  returns.
- Left, Right, and Tab switch folder or dialog choices where the released view
  permits it. Enter confirms the active choice.
- Mouse hover selects menu and confirmation rows before click activation.

## Baseline evidence

The qualifying screenshot and remote interaction result must be captured from
an isolated Omarchy guest on `optiplex-sff`. Evidence records the source
commit, guest identity, service and settings state, process count, and isolated
data hashes without credentials. A local capture is supplemental only.
