# Syncshell adapter protocol v1

Protocol v1 is the only native-core wire contract in Syncshell 0.1.8. One rich
host owns one child, one session, one event cursor, and one serialized mutation
queue.

## Transport

- UTF-8 JSON Lines travel over the child's standard input and output.
- Each line is one JSON object and is at most 1,048,576 bytes including its
  newline.
- Standard output contains protocol lines only.
- Standard error contains bounded, sanitized diagnostics only.
- The API key never appears in arguments, JSONL, errors, logs, fixtures,
  settings, or screenshots.
- The host terminates the child when its service is destroyed. Closing standard
  input requests a graceful end.
- Protocol major `1` is required. There is no negotiation, patch format, second
  output format, daemon, socket, or client brokerage.

## Core messages

The first accepted output is `hello`:

```json
{"v":1,"type":"hello","build":{"version":"0.1.8"},"capabilities":[]}
```

State is always a complete snapshot. Revisions increase only when public state
changes, and a host replaces state only with a higher revision:

```json
{"v":1,"type":"snapshot","revision":1,"state":{}}
```

The `state` value serializes the session's public snapshot directly. It contains
host-neutral connection, identity, device, folder, pending-offer, activity,
mutation, Web UI, lifecycle, executable, and capability facts. It never
contains Omarchy labels, layout, settings paths, icon style, Web UI theme
preference, package-manager state, or other presentation policy.

The complete state object contains these sections:

- `hostId`: the bounded adapter identity supplied at startup
- `connection`: endpoint, health, authorization, online, and freshness
- `identity`: authenticated device ID and Syncthing version
- `devices`: bounded configured devices and connection state
- `folders`: bounded configuration, status, sharing, and current errors
- `pendingFolders`: bounded current offers and encryption flags
- `activity`: bounded active files and the session-owned rotating current file
- `webUi`: openable URL, selected theme, and GUI-assets path
- `installation`: host-neutral executable presence and path
- `mutation`: the one serialized action's busy, error, and result state
- `counts`: normalized folder, device, connection, problem, and syncing totals
- `lifecycle`: exact binding, observation, classification, and capabilities
- `capabilities`: the action names implemented by this core

Every collection and remote string is bounded so the complete snapshot remains
within the transport line limit. A fresh snapshot replaces the prior state; no
section is a patch or independently revisioned cache.

Every accepted request has a non-empty caller-generated string `id` and exactly
one result:

```json
{"v":1,"type":"refresh","id":"7"}
{"v":1,"type":"configure","id":"8","config":{}}
{"v":1,"type":"action","id":"9","action":"folder.rescan","args":{}}
{"v":1,"type":"result","id":"9","ok":true,"revision":2,"data":{}}
```

A failed result has a stable machine code and sanitized text:

```json
{"v":1,"type":"result","id":"9","ok":false,"error":{"code":"folder_missing","message":"folder is no longer configured"}}
```

The one `configure` request may update `probeIntervalSeconds` and
`desiredServiceState`. Both are validated and applied in memory. It cannot
carry credentials, settings paths, style values, or arbitrary host objects.

The domain action names are:

- `folder.pause`
- `folder.resume`
- `folder.rescan`
- `folder.rescan-all`
- `folder.forget`
- `folder.add-existing`
- `folder.suggest-id`
- `lifecycle.start`
- `lifecycle.stop`
- `lifecycle.enable`
- `lifecycle.disable`
- `webui.set-theme`

Unsupported names fail; they do not fall back or alias another action.

Action arguments are exact:

- `folder.pause`, `folder.resume`, `folder.rescan`, and `folder.forget` take
  `folderId`.
- `folder.rescan-all`, `folder.suggest-id`, and lifecycle actions take an empty
  object.
- `folder.add-existing` takes `folderId`, `path`, optional `label`, bounded
  `deviceIds`, and optional `pendingDeviceId`.
- `webui.set-theme` takes `theme`.

Successful folder-ID suggestion and add results return the resulting
`folderId` in `data`. Irrelevant fields are rejected rather than ignored.

## Termination and protocol failure

A host may send a correlated `shutdown` request. The core stops accepting new
actions, cancels its long poll, completes or cancels the active mutation, emits
the result, then emits `end` and exits:

```json
{"v":1,"type":"shutdown","id":"10"}
{"v":1,"type":"result","id":"10","ok":true}
{"v":1,"type":"end","reason":"shutdown"}
```

An unrecoverable framing or version error emits one `fatal` line when output is
still safe, then exits nonzero:

```json
{"v":1,"type":"fatal","code":"protocol_version","message":"protocol major 1 required"}
```

Malformed, duplicate, oversized, or post-shutdown requests never invoke an
action. A crash is process state owned by the host adapter; it is not
represented as Syncthing offline.
