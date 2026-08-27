import QtQuick
import Quickshell
import Quickshell.Io
import "../models/ServiceStateModel.js" as ServiceStateModel

QtObject {
  id: root

  property string helperPath: ""
  property bool folderMutationBusy: false
  property string state: "checking"
  property string label: "Checking"
  property string executablePath: ""
  property bool serviceAvailable: false
  property bool serviceRunning: false
  property string serviceActiveState: "inactive"
  property string unitFileState: "not-found"
  property int probeIntervalSeconds: 15
  property bool operationRunning: false
  property bool refreshing: false
  property bool packageActionRunning: false
  property string packageStatus: ""
  property string packageError: ""
  property string controlError: ""
  property int _desiredServiceState: -1
  property string _desiredUnitFileState: ""
  property string _controlKind: ""
  property bool _operationSeen: false
  property bool _statusRefreshPending: false
  property string _statusOutput: ""
  property string _statusErrorOutput: ""
  property string _controlErrorOutput: ""

  readonly property bool serviceActive: _desiredServiceState === -1
    ? serviceRunning : _desiredServiceState === 1
  readonly property bool serviceActionRunning: controlProcess.running
  readonly property bool unitFileActionRunning:
    _controlKind === "unit-file" || _desiredUnitFileState !== ""
  readonly property bool canUseRuntime: state === "existing"
    && executablePath !== ""
  readonly property bool canControlService: canUseRuntime && serviceAvailable
  readonly property bool lifecycleBusy: refreshing || packageActionRunning
    || serviceActionRunning || folderMutationBusy
  readonly property bool canInstall: state === "missing" && !lifecycleBusy

  signal runtimeUnavailable(string phase)
  signal runtimeAvailable
  signal serviceStarting
  signal serviceStopping
  signal serviceStarted

  function updateStatus() {
    if (statusProcess.running) {
      _statusRefreshPending = true
      return
    }
    refreshing = true
    packageError = ""
    _statusOutput = ""
    _statusErrorOutput = ""
    statusProcess.running = true
  }

  function applyStatus(text) {
    var data
    try {
      data = JSON.parse(String(text || ""))
    } catch (error) {
      packageError = "Could not read Syncthing installation status"
      return false
    }
    var nextState = String(data.state || "")
    if (["existing", "incomplete", "missing"].indexOf(nextState) < 0) {
      packageError = "Syncthing installation status is invalid"
      return false
    }
    state = nextState
    label = String(data.label || "Unavailable")
    executablePath = String(data.executable || "")
    serviceAvailable = data.serviceAvailable === true
    serviceRunning = data.serviceRunning === true
    serviceActiveState = String(data.serviceActiveState || "")
    unitFileState = String(data.unitFileState || "")
    operationRunning = data.operationRunning === true
    if (!_statusRefreshPending) {
      reconcileDesiredServiceState()
      reconcileDesiredUnitFileState()
    }
    reconcilePackageOperation()
    if (!canUseRuntime) runtimeUnavailable(state)
    else if (serviceAvailable && !serviceActive) runtimeUnavailable("stopped")
    else runtimeAvailable()
    return true
  }

  function reconcileDesiredServiceState() {
    if (_desiredServiceState === -1) return
    var expectedRunning = _desiredServiceState === 1
    if (serviceRunning === expectedRunning) {
      _desiredServiceState = -1
    } else if (!controlProcess.running) {
      _desiredServiceState = -1
      controlError = expectedRunning
        ? "Syncthing did not start" : "Syncthing did not stop"
    }
  }

  function reconcileDesiredUnitFileState() {
    if (_desiredUnitFileState === "") return
    if (unitFileState === _desiredUnitFileState) {
      _desiredUnitFileState = ""
    } else if (!controlProcess.running) {
      var desired = _desiredUnitFileState
      _desiredUnitFileState = ""
      controlError = desired === "enabled"
        ? "Syncthing service was not enabled"
        : "Syncthing service was not disabled"
    }
  }

  function reconcilePackageOperation() {
    if (packageActionRunning && operationRunning) _operationSeen = true
    if (!packageActionRunning || !_operationSeen || operationRunning) return
    packageActionRunning = false
    packageStatus = "Installation terminal closed"
    _operationSeen = false
    operationPollTimer.stop()
    packageMessageTimer.restart()
  }

  function install() {
    if (!canInstall) return
    packageActionRunning = true
    packageError = ""
    packageStatus = "Complete installation in the Omarchy terminal"
    operationPollTimer.ticks = 0
    _operationSeen = false
    operationPollTimer.start()
    Quickshell.execDetached(["bash", helperPath, "install"])
  }

  function toggleService() {
    if (!canControlService || controlProcess.running || folderMutationBusy) return
    var start = !serviceActive
    _desiredServiceState = start ? 1 : 0
    _controlKind = "runtime"
    controlError = ""
    _controlErrorOutput = ""
    controlProcess.command = [
      "systemctl", "--user", start ? "start" : "stop", "syncthing.service"
    ]
    if (start) serviceStarting()
    else serviceStopping()
    controlProcess.running = true
  }

  function setUnitFileState(state) {
    var command = ServiceStateModel.persistenceCommand(String(state || ""))
    if (!canControlService || controlProcess.running || folderMutationBusy
        || command.length === 0) return false
    _desiredUnitFileState = String(state)
    _controlKind = "unit-file"
    controlError = ""
    _controlErrorOutput = ""
    controlProcess.command = command
    controlProcess.running = true
    return true
  }

  property Timer statusTimer: Timer {
    interval: Math.max(1, root.probeIntervalSeconds) * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.updateStatus()
  }

  property Timer operationPollTimer: Timer {
    property int ticks: 0
    interval: 1500
    repeat: true
    onTriggered: {
      ticks++
      root.updateStatus()
      if (ticks >= 10 && !root._operationSeen) {
        stop()
        root.packageActionRunning = false
        root.packageStatus = ""
        root.packageError = "The installation terminal did not start"
      }
    }
  }

  property Timer packageMessageTimer: Timer {
    interval: 3000
    repeat: false
    onTriggered: root.packageStatus = ""
  }

  property Process statusProcess: Process {
    id: statusProcess
    command: ["bash", root.helperPath, "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root._statusOutput = text
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root._statusErrorOutput = text
    }
    onExited: function(exitCode) {
      var rerun = root._statusRefreshPending
      root.refreshing = false
      if (exitCode === 0) {
        root.applyStatus(root._statusOutput)
      } else {
        root.packageError = String(root._statusErrorOutput
          || "Could not check Syncthing installation").trim()
      }
      root._statusRefreshPending = false
      if (rerun) Qt.callLater(root.updateStatus)
    }
  }

  property Process controlProcess: Process {
    id: controlProcess
    command: []
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root._controlErrorOutput = text
    }
    onExited: function(exitCode) {
      var kind = root._controlKind
      if (exitCode !== 0) {
        root.controlError = String(root._controlErrorOutput
          || "Could not change Syncthing service state").trim()
        root._desiredServiceState = -1
        root._desiredUnitFileState = ""
      } else if (kind === "runtime" && root._desiredServiceState === 1) {
        root.serviceStarted()
      }
      root._controlKind = ""
      root.updateStatus()
    }
  }
}
