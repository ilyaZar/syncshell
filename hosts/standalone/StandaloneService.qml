import QtQuick
import "../../shared"

QtObject {
  id: root

  required property string corePath
  property string configPath: ""
  property string endpoint: ""
  property string credentialFile: ""
  property string expectedDeviceId: ""
  property bool lifecycleAuthorized: false
  property string lifecycleUnit: ""
  property string lifecycleConfig: ""
  property int probeIntervalSeconds: 15
  property string desiredServiceState: "enabled"

  readonly property bool processRunning: core.running
  readonly property bool protocolReady: core.protocolReady
  readonly property string processError: core.lastError
  readonly property int revision: core.revision
  readonly property var snapshot: core.snapshot
  readonly property bool online: snapshot.connection
    ? snapshot.connection.online === true : false
  readonly property string deviceId: snapshot.identity
    ? String(snapshot.identity.deviceId || "") : ""
  readonly property var folders: snapshot.folders || []

  signal actionFinished(string id, bool ok, var error)

  function startupArguments() {
    var args = ["--host-id", "standalone",
      "--probe-interval-seconds", String(probeIntervalSeconds),
      "--desired-service-state", desiredServiceState]
    if (configPath) args.push("--config", configPath)
    if (endpoint) args.push("--endpoint", endpoint)
    if (credentialFile) args.push("--credential-file", credentialFile)
    if (expectedDeviceId) args.push("--expected-device-id", expectedDeviceId)
    if (lifecycleAuthorized) {
      args.push("--lifecycle-kind", "systemd-user", "--lifecycle-authorized",
        "--lifecycle-unit", lifecycleUnit)
      if (lifecycleConfig) args.push("--lifecycle-config", lifecycleConfig)
    }
    return args
  }

  function configure(probeSeconds, serviceState) {
    return core.configure({
      probeIntervalSeconds: probeSeconds,
      desiredServiceState: serviceState
    })
  }

  function refresh() { return core.refresh() }

  function rescan(folderId) {
    return core.action("folder.rescan", { folderId: folderId })
  }

  function restart() { return core.restart() }

  function stop() { core.terminate() }

  property CoreProcess core: CoreProcess {
    corePath: root.corePath
    startupArguments: root.startupArguments()
    onResultReceived: function(id, ok, revision, error) {
      root.actionFinished(id, ok, error)
    }
  }
}
