# Assets

## Marketplace preview

`../preview.png` is intentionally the only published asset outside this
directory. The Omarchy plugin marketplace discovers a preview only when it uses
a supported `preview.*` name in the repository root. `manifest.json` has no
preview path field.

## Published demos

`published/` contains the four release videos linked from the root README. Each
MP4 has a matching PNG thumbnail:

- `01_syncthing_file_activity`
- `02_syncthing_folder_lifecycle`
- `03_syncthing_theme_aware_webUI`
- `04_syncthing_icon_change_and_other_settings`

The ignored capture harness, upstream reference, and byte-identical release
backups live in `../tests/interactive/syncthing-demo/`. The ignored project
skill at `../.agents/skills/syncthing-demo-video/` documents the reproduction
workflow.

## Syncthing status icons

The four SVG files in this directory are formatting adaptations of Syncthing's
official 16-by-16 status icons. Their appearance and view boxes are preserved:

- `status-default.svg`
- `status-notify.svg`
- `status-pause.svg`
- `status-sync.svg`

They were retrieved from the Syncthing repository at commit
`058bcd7334839663cf569501d3ac539034d45cb5`:

<https://github.com/syncthing/syncthing/tree/058bcd7334839663cf569501d3ac539034d45cb5/assets/statusicons>

`mono/` holds monochrome redraws of the same four icons, tinted to the theme at
runtime by `MonoIcon.qml`. They must stay pure white on transparent: the tint
multiplies the source's value channel, so anything darker comes out darker
still.

Copyright belongs to the Syncthing contributors. These adapted files remain
licensed under the Mozilla Public License 2.0:

<https://github.com/syncthing/syncthing/blob/main/LICENSE>
