import QtQuick
import "../../shared"

QtObject {
  id: root

  required property string pluginRoot
  property string configPath: ""
  property string endpoint: ""
  property string credentialFile: ""
  property string expectedDeviceId: ""
  property bool lifecycleAuthorized: false
  property string lifecycleUnit: ""
  property string lifecycleConfig: ""
  property int probeIntervalSeconds: 15
  property int refreshIntervalSeconds: 60
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

  signal actionFinished(string id, bool ok, var data, var error)

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
      refreshIntervalSeconds: refreshIntervalSeconds,
      desiredServiceState: serviceState
    })
  }

  function refresh() { return core.refresh() }

  function rescan(folderId) {
    return core.action("folder.rescan", { folderId: folderId })
  }

  function pause(folderId) {
    return core.action("folder.pause", { folderId: folderId })
  }

  function resume(folderId) {
    return core.action("folder.resume", { folderId: folderId })
  }

  function rescanAll() { return core.action("folder.rescan-all", {}) }

  function forget(folderId) {
    return core.action("folder.forget", { folderId: folderId })
  }

  function addExisting(arguments) {
    return core.action("folder.add-existing", arguments || ({}))
  }

  function suggestFolderId() { return core.action("folder.suggest-id", {}) }

  function lifecycle(action) {
    return core.action("lifecycle." + action, {})
  }

  function setWebUiTheme(theme) {
    return core.action("webui.set-theme", { theme: theme })
  }

  function restart() { return core.restart() }

  function stop() { core.terminate() }

  property CoreProcess core: CoreProcess {
    pluginRoot: root.pluginRoot
    startupArguments: root.startupArguments()
    onResultReceived: function(id, ok, revision, data, error) {
      root.actionFinished(id, ok, data, error)
    }
  }
}
