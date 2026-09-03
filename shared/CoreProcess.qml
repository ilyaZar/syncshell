import QtQuick
import Quickshell.Io

QtObject {
  id: root

  required property string corePath
  property var startupArguments: []
  property bool desiredRunning: true
  property bool protocolReady: false
  property bool incompatible: false
  property bool unavailable: false
  property string lastError: ""
  property string lastDiagnostic: ""
  property var snapshot: ({})
  property int revision: 0
  property int generation: 0
  property int restartAttempts: 0
  readonly property bool running: coreProcess.running
  readonly property int maxLineLength: 1048575
  readonly property int maxRestartAttempts: 3

  property int _nextId: 0
  property var _pending: ({})
  property bool _expectedStop: false
  property bool _restartRequested: false

  signal resultReceived(string id, bool ok, int revision, var data, var error)
  signal protocolFailed(string message)

  function start() {
    if (!corePath || incompatible) return false
    _expectedStop = false
    desiredRunning = true
    return true
  }

  function terminate() {
    _restartRequested = false
    _expectedStop = true
    desiredRunning = false
    if (coreProcess.running) coreProcess.signal(15)
  }

  function restart() {
    if (!corePath) return false
    _restartRequested = true
    _expectedStop = true
    if (coreProcess.running) {
      send("shutdown", {})
      shutdownTimer.restart()
    } else {
      restartTimer.restart()
    }
    return true
  }

  function configure(config, callback) {
    return send("configure", { config: config || ({}) }, callback)
  }

  function refresh(callback) {
    return send("refresh", {}, callback)
  }

  function action(name, args, callback) {
    return send("action", { action: String(name || ""), args: args || ({}) },
      callback)
  }

  function send(type, values, callback) {
    if (!coreProcess.running || !protocolReady && type !== "shutdown") return ""
    var id = String(++_nextId)
    var message = { v: 1, type: type, id: id }
    var keys = Object.keys(values || ({}))
    for (var index = 0; index < keys.length; index++) {
      message[keys[index]] = values[keys[index]]
    }
    var encoded = JSON.stringify(message)
    if (utf8Length(encoded) + 1 > maxLineLength) {
      failProtocol("request exceeds protocol line bound")
      return ""
    }
    var next = Object.assign({}, _pending)
    next[id] = callback || null
    _pending = next
    coreProcess.write(encoded + "\n")
    return id
  }

  function handleLine(rawLine) {
    var line = String(rawLine || "")
    if (utf8Length(line) > maxLineLength) {
      failProtocol("core output exceeds protocol line bound")
      return
    }
    var message
    try {
      message = JSON.parse(line)
    } catch (error) {
      failProtocol("core output is not valid JSON")
      return
    }
    if (!message || message.v !== 1 || typeof message.type !== "string") {
      failProtocol("core protocol major is incompatible")
      return
    }
    if (!protocolReady) {
      acceptHello(message)
      return
    }
    if (message.type === "snapshot") {
      acceptSnapshot(message)
      return
    }
    if (message.type === "result") {
      acceptResult(message)
      return
    }
    if (message.type === "end") {
      _expectedStop = true
      desiredRunning = false
      return
    }
    if (message.type === "fatal") {
      failProtocol(String(message.message || "core reported a protocol error"))
      return
    }
    failProtocol("core message type is unsupported")
  }

  function acceptHello(message) {
    if (message.type !== "hello" || !message.build
        || message.build.protocol !== 1) {
      failProtocol("core did not provide a compatible hello")
      return
    }
    protocolReady = true
    restartAttempts = 0
    incompatible = false
    unavailable = false
    lastError = ""
  }

  function acceptSnapshot(message) {
    if (!Number.isInteger(message.revision) || message.revision <= revision
        || !message.state || typeof message.state !== "object") {
      failProtocol("core snapshot revision is invalid")
      return
    }
    snapshot = message.state
    revision = message.revision
  }

  function acceptResult(message) {
    var id = String(message.id || "")
    if (!_pending.hasOwnProperty(id)) {
      failProtocol("core result is duplicate or unknown")
      return
    }
    var callback = _pending[id]
    var next = Object.assign({}, _pending)
    delete next[id]
    _pending = next
    if (callback) callback(message.ok === true, message.revision || 0,
      message.data || null, message.error || null)
    resultReceived(id, message.ok === true, message.revision || 0,
      message.data || null, message.error || null)
  }

  function utf8Length(value) {
    try {
      return unescape(encodeURIComponent(String(value || ""))).length
    } catch (error) {
      return maxLineLength + 1
    }
  }

  function failProtocol(message) {
    lastError = message
    incompatible = true
    protocolReady = false
    _expectedStop = true
    _restartRequested = false
    desiredRunning = false
    _pending = ({})
    if (coreProcess.running) coreProcess.signal(15)
    protocolFailed(message)
  }

  function handleExit(exitCode) {
    shutdownTimer.stop()
    protocolReady = false
    _pending = ({})
    if (_restartRequested) {
      _restartRequested = false
      restartTimer.restart()
      return
    }
    if (_expectedStop || !desiredRunning) return
    unavailable = true
    lastError = "core exited unexpectedly with status " + exitCode
    if (restartAttempts < maxRestartAttempts) {
      restartAttempts++
      restartTimer.interval = Math.min(4000, 250 * Math.pow(2,
        restartAttempts - 1))
      restartTimer.restart()
    }
  }

  Component.onDestruction: {
    _expectedStop = true
    desiredRunning = false
    if (coreProcess.running) coreProcess.signal(15)
  }

  property Process coreProcess: Process {
    command: [root.corePath, "stream"].concat(root.startupArguments || [])
    running: root.desiredRunning && root.corePath !== "" && !root.incompatible
    stdinEnabled: true

    stdout: SplitParser {
      splitMarker: "\n"
      onRead: function(line) { root.handleLine(line) }
    }

    stderr: SplitParser {
      splitMarker: "\n"
      onRead: function(line) {
        var value = String(line || "").trim()
        root.lastDiagnostic = value.length > 4096 ? value.slice(0, 4096) : value
      }
    }

    onStarted: {
      root.generation++
      root.protocolReady = false
      root.unavailable = false
      root.lastError = ""
      root.revision = 0
      root.snapshot = ({})
      root._pending = ({})
      root._expectedStop = false
    }

    onExited: function(exitCode) { root.handleExit(exitCode) }
  }

  property Timer restartTimer: Timer {
    interval: 100
    repeat: false
    onTriggered: {
      root._expectedStop = false
      root.desiredRunning = false
      Qt.callLater(function() { root.desiredRunning = true })
    }
  }

  property Timer shutdownTimer: Timer {
    interval: 1000
    repeat: false
    onTriggered: if (coreProcess.running) coreProcess.signal(15)
  }
}
