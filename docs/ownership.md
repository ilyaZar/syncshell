# Syncshell ownership

This is the final ownership map for the 0.1.8 architecture. The phase 04
cutover moved the retained host implementation after native parity was proven.

| Path                         | Sole responsibility                         |
| ---------------------------- | ------------------------------------------- |
| `core/`                      | Go native core                              |
| `core/internal/syncthing/`   | discovery, secrets, transport, wire data     |
| `core/internal/session/`     | normalized state, events, retries, actions  |
| `core/internal/systemduser/` | one trusted user lifecycle binding          |
| `core/internal/protocol/`    | bounded JSONL for session public types      |
| `shared/CoreProcess.qml`     | child process and serialization boundary    |
| `hosts/omarchy/`             | Omarchy facade, settings, UI, and platform  |
| `hosts/standalone/`          | maintained contract harness                 |
| `packaging/bundled/`         | reproducible x86_64 artifact tooling        |

The root `Panel.qml`, `Service.qml`, and `manifest.json` remain regular-file
Omarchy entry points. They are boundaries, not additional owners.

## State and policy

- API health is authoritative for the selected instance.
- One session owns discovery, connection, hydration, events, retry, public
  state, and serialized mutations.
- Lifecycle controls require a host-authorized exact unit and a verified match
  to the selected target. Unit presence or activity is not authority.
- `hosts/omarchy/` alone owns
  `$XDG_CONFIG_HOME/omarchy/ilyazar.syncthing/settings.toml` and its four
  fields.
- The core receives only host-neutral operational values. It never receives
  the Omarchy settings path, icon style, or Web UI theme preference.
- `shared/CoreProcess.qml` knows framing and process state, not Syncthing or
  systemd semantics.
- Protocol code serializes session public types directly. No repository,
  service, mapper, DTO, or view-model chain may merely rename values.

## Transition

Retained Omarchy presentation and settings files live in `hosts/omarchy/`.
Replaced REST, credential, event, state, folder, and lifecycle QML code was
deleted from its original paths.
There is no mixed runtime, fallback, alias, or feature flag.

The released QML implementation remains available in the `v0.1.7` Git history,
not in the 0.1.8 runtime. Users restart the shell after updating from 0.1.7 so
the kept service is replaced atomically by the native-backed service.

The future host directories are README-only in 0.1.8 and make no support claim.
