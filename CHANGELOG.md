# Changelog

Notable changes to Syncthing for Omarchy are documented here.

## Unreleased

- replace the QML Syncthing engine with one parent-bound native Go core while
  preserving the complete Omarchy panel and settings workflow
- fix issue 45 by treating healthy external Syncthing instances as online
  without exposing controls for an unrelated inactive user service
- bundle one reproducible static Linux x86_64 executable with a public JSONL
  protocol and keep credentials, REST, events, lifecycle, and mutations in Go
- make accepted single and global rescans visible immediately with rotating,
  inert controls and explicit optimistic folder state
- preserve ordinary 0.1.7 fast-forward updates with a usable panel until the
  standard shell restart activates the native core

## 0.1.7 - 2026-08-31

- reconcile configured and systemd user-service startup states without changing
  the independent runtime start and stop controls (thanks @renews for reporting)
- add a configurable interval for detecting external systemd state changes
- add per-folder and all-folder rescans, a clearer host ID copy control, and
  remembered local host identity while Syncthing is stopped

## 0.1.6 - 2026-08-22

- Make live and indexed file activity accurate for additions, deletions,
  concurrent changes, and active folders.
- Refine folder management with pending offers, copyable Syncthing IDs, and
  explicit link, unlink, and forget actions.
- Add versioned icon preferences, live Omarchy Web UI theming, and clean plugin
  removal that can preserve settings.
- Refresh the preview and add four focused demo videos.

## 0.1.5 - 2026-08-20

- Add an optional theme-colored bar icon while keeping the Syncthing artwork as
  the default (@davidszp, @ilyaZar).

## 0.1.4 - 2026-08-16

- Support Syncthing installations with TLS enabled for the local API.
- Clarify installation state and simplify plugin instructions.

## 0.1.3 - 2026-08-15

- Add a demo video and improve the documentation.

## 0.1.2 - 2026-08-15

- Add folder management to the bar panel.

## 0.1.1 - 2026-08-14

- Keep Syncthing package management explicit and monitor existing installs.
- Show live file activity and refresh status after synchronization.

## 0.1.0 - 2026-08-12

- Initial release.
