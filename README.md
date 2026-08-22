# Syncthing for Omarchy

See Syncthing health and file activity from the Omarchy bar. The plugin can
manage local folders, open Syncthing's Web UI, control the user service, and
install the official Arch package.

![Syncthing status and installation controls](preview.png)

## Quick start

- select the switch/toggle in the top right to start or stop the user service
- select a folder card to open its directory
- select **+** to configure an existing local directory
- select **Refresh** to request an immediate health update
- select **Open Web UI** for device setup and advanced folder options
- select the gear or press `s` for appearance settings and clean removal

## Install

```bash
omarchy plugin add https://github.com/ilyaZar/omarchy-syncthing.git --enable
```

Open the widget and expand **More**. If Syncthing is missing, select **Install
Syncthing**. The plugin runs `omarchy pkg add syncthing`, then enables and
starts `syncthing.service`.

## Keybindings

As shown in the footer at the bottom of the main plugin menu

| Key   | Action                    |
| ----- | ------------------------- |
| `r`   | refresh status            |
| `w`   | open the Web UI           |
| `p`   | start or stop the service |
| `s`   | open plugin settings      |
| `q`   | close the panel           |
| `esc` | close the panel           |

## Settings

The settings menu opens `~/.config/omarchy/ilyazar.syncthing/settings.toml` in
the default editor. The file is created only when it is first opened, and
changes apply when saved. New files use configuration version `1`, with
appearance options grouped under the `[style]` section. Existing files are never
overwritten.

- `style.icon_style = "branded"` uses the classic Syncthing bar icon. Use
  `themed` for an icon colored by the active Omarchy theme.
- `style.web_ui_theme = "omarchy"` applies the complete Omarchy palette to
  Syncthing's Web UI. Use `default` for Syncthing's own styling.

Changing the Omarchy theme regenerates the Web UI palette immediately. An open
Web UI applies the new colors without a page reload. The generated Omarchy theme
is separate from Syncthing's default theme assets, so selecting `default` keeps
Syncthing's styling and any user customization intact.

## Demo

> [!WARNING] The Hyprland window to the left of the plugin is not part of the
> plugin. It live-tracks changes in the `test-source` directory for the
> demonstration.

The two release demos show the current interface at a readable zoom while a
floating terminal makes every filesystem change explicit:

- [file activity](assets/published/01-syncthing-file-activity.mp4)
- [unlink, link, and forget](assets/published/02-syncthing-folder-lifecycle.mp4)

### File activity

The plugin reports only state exposed by Syncthing:

- Blue identifies synchronization or an indexed addition.
- Red identifies an indexed entry with `deleted=true`.
- Green identifies remote download progress, which is an upload from this
  device.

Syncthing does not expose a reliable source-to-destination relationship for a
rename or move, so the plugin does not guess one from nearby additions and
deletions.

## Manage folders

**UNLINK** pauses the selected folder and **LINK** resumes it. Both actions use
Syncthing's reversible `paused` setting; they do not create filesystem links or
change device sharing.

**FORGET** is available for an unlinked folder. It removes that folder from the
local Syncthing configuration without deleting its directory or data. Its Folder
ID, settings, and device list are no longer retained by the plugin.

Adding a folder requires an existing directory and a unique Folder ID. The path
is canonicalized, and paths that duplicate, contain, or sit inside another
configured folder are rejected. A new folder is local-only unless remote devices
are explicitly selected.

Pending unencrypted folder offers can prefill the Folder ID, label, and offering
device. Encrypted offers and sharing with untrusted devices must be configured
in the Web UI.

A shared folder must use the same Folder ID on every device. Labels and paths
may differ. Create the folder on one device, share it, and accept the offer on
the other devices rather than creating unrelated folder identities.

See Syncthing's
[Getting Started guide](https://docs.syncthing.net/intro/getting-started.html)
and [folder guide](https://docs.syncthing.net/intro/gui.html) for device pairing
and sharing.

Folder management and Web UI theming use Syncthing's granular configuration and
system-path APIs and require Syncthing 1.21.0 or later.

## Roadmap and prior releases

## Remove

Open the plugin settings and select **Cleanly remove Syncthing plugin**. The
confirmation can preserve or delete the plugin settings. Both choices restore
Syncthing's default Web UI when the Omarchy theme is active, remove the
generated Omarchy theme, and then use Omarchy's native plugin removal.

Clean plugin removal never uninstalls Syncthing or removes its configuration,
folders, devices, or synchronized data. Uninstall Syncthing separately only when
that is intended:

```bash
systemctl --user disable --now syncthing.service
omarchy pkg drop syncthing
```

These commands do not remove Syncthing configuration or synchronized files.

## Security and license

The plugin talks only to Syncthing's local API. It keeps the API key in memory
and does not persist or log it. Like other Omarchy shell plugins, it runs
unsandboxed, and the API key permits Syncthing configuration changes.

Plugin code is MIT licensed. Adapted Syncthing status icons are MPL-2.0; their
source and attribution are documented in `assets/README.md`.
