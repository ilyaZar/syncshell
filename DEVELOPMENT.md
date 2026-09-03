# Development

## Branches

`dev` is the integration branch for the 0.1.8 native-core work and descends
directly from released 0.1.7. Verified phase checkpoints may be pushed to
`origin/dev`. Promotion to `main`, tags, releases, and marketplace changes are
separate owner-controlled actions.

The following branches are read-only historical source and evidence:

- `dev-syncshell-cross-distro` at `1062b17`
- `dev-syncshell-cross-distro-ui` at `5af5056`

Their QML-first core is not an implementation base for 0.1.8.

## Architecture

The target ownership and protocol are recorded in:

- [Syncshell glossary](CONTEXT.md)
- [ownership map](docs/ownership.md)
- [adapter protocol v1](docs/adapter-protocol-v1.md)
- [Omarchy service contract](docs/omarchy-service-contract-0.1.7.md)
- [Omarchy interaction contract](docs/omarchy-interaction-contract-0.1.7.md)

The released QML engine stays in its original paths until the atomic cutover.
Do not introduce a mixed QML and Go domain runtime.

## Baseline checks

Run the complete released suite from the repository root:

```bash
git diff --check
jq empty manifest.json
omarchy plugin validate .
qmllint Panel.qml Service.qml core/*.qml models/*.js ui/*.qml \
  tests*.qml scripts/folder-picker.qml
bash -n scripts/*.sh tests/*.sh
mise exec aqua:koalaman/shellcheck@0.11.0 -- \
  shellcheck scripts/*.sh tests/*.sh
qml6 --apptype core -f tests/run.qml
bash tests/scripts.test.sh
bash tests/architecture.test.sh
bash tests/folder-rescan.test.sh
bash tests/service-state.test.sh
```

## Isolated runtime tests

Never use the owner's normal Syncthing configuration, database, API key, or
synchronized data. Test instances use temporary configuration, database, GUI,
and folder paths with discovery, relays, NAT traversal, and upgrades disabled.

Interactive release evidence comes from the repo-owned `syncshell-vm-setup`
Omarchy profile on `optiplex-sff`. Verify the source commit and snapshot before
copying code, keep the guest inhibitor active, pull evidence, and fully stop the
guest afterward.

## Native core development

The native core and standalone harness remain deliberately outside the
production Omarchy entry points until the phase-04 cutover. Run their complete
local checks with:

```bash
go -C core test ./...
go -C core test -race ./...
go -C core vet ./...
go -C core test -run='^$' -fuzz=FuzzEventJSON -fuzztime=1s \
  ./internal/syncthing
tests/core-process.test.sh
tests/standalone-service.test.sh
tests/native-core-architecture.test.sh
tests/native-core-live.test.sh
```

The live test creates one temporary Syncthing home and Unix GUI socket. It
disables discovery, relays, NAT traversal, telemetry, and upgrades, then removes
the complete temporary tree.

To inspect the shell-neutral harness manually, build to a temporary path and
provide an isolated Syncthing configuration:

```bash
go -C core build -trimpath -o /tmp/syncshell-core ./cmd/syncshell-core
SYNCSHELL_CORE_PATH=/tmp/syncshell-core \
SYNCSHELL_CONFIG_PATH=/path/to/isolated/config.xml \
  quickshell -p tests-standalone.qml
```

Never point the harness at the owner's normal Syncthing configuration. The
standalone surface is a maintained contract test, not a supported 0.1.8 host.

The interactive VM parity gate runs `tests/native-core-parity-vm.test.sh`
against an explicitly supplied temporary core binary. It creates two isolated
loopback-only Syncthing nodes and records only credential-free results under the
VM artifact directory.
