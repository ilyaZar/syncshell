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

The production entry points delegate to the Omarchy host, which starts one
bundled native core. Do not introduce a mixed QML and Go domain runtime.

## Baseline checks

Run the complete released suite from the repository root:

```bash
git diff --check
jq empty manifest.json
omarchy plugin validate .
/usr/lib/qt6/bin/qmllint -I /usr/share/omarchy/shell Panel.qml Service.qml \
  shared/*.qml hosts/omarchy/*.qml hosts/omarchy/controllers/*.qml \
  hosts/omarchy/ui/*.qml tests*.qml
bash -n hosts/omarchy/scripts/*.sh packaging/bundled/*.sh tests/*.sh
mise exec aqua:koalaman/shellcheck@0.11.0 -- \
  shellcheck hosts/omarchy/scripts/*.sh packaging/bundled/*.sh tests/*.sh
qml6 --apptype core -f tests/run.qml
bash tests/scripts.test.sh
bash tests/architecture.test.sh
bash tests/native-core-architecture.test.sh
bash tests/omarchy-service-contract.test.sh
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

Build and verify the exact production artifact before running the native
checks:

```bash
packaging/bundled/build.sh
git add bin/x86_64/syncshell-core
packaging/bundled/verify.sh
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

To inspect the shell-neutral harness manually, reproduce the bundled core and
provide an isolated Syncthing configuration:

```bash
packaging/bundled/build.sh
SYNCSHELL_PLUGIN_ROOT="$PWD" \
SYNCSHELL_CONFIG_PATH=/path/to/isolated/config.xml \
  quickshell -p tests-standalone.qml
```

Never point the harness at the owner's normal Syncthing configuration. The
standalone surface is a maintained contract test, not a supported 0.1.8 host.

The interactive VM parity gate runs `tests/native-core-parity-vm.test.sh`
against the explicitly supplied bundled core path. It creates two isolated
loopback-only Syncthing nodes and records only credential-free results under
the VM artifact directory.

`packaging/bundled/SHA256SUMS` is the sole tracked checksum list for the
bundled artifact.

An update from 0.1.7 requires the user's ordinary shell restart before the
plugin is used again. Do not retain the removed QML helpers to bridge that
restart boundary.
