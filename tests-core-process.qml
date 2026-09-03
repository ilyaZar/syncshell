import QtQuick
import Quickshell
import "shared"

ShellRoot {
  id: root

  property int readyCount: 0
  property int completedRequests: 0
  property bool restartRequested: false
  property int handledGeneration: 0
  property bool versionFailurePassed: false
  property bool lineBoundPassed: false
  property bool pendingRequestSent: false
  property bool pendingFailurePassed: false
  readonly property string testPluginRoot:
    Quickshell.env("SYNCSHELL_TEST_PLUGIN_ROOT") || ""

  function localPath(url) {
    var value = String(url || "")
    if (value.indexOf("file://") === 0) value = value.slice(7)
    return decodeURIComponent(value)
  }

  function fail(message) {
    console.error(message)
    core.terminate()
    pendingProbe.terminate()
    Qt.exit(1)
  }

  function requestCompleted(ok, revision, data, error) {
    if (!ok || error) {
      fail("mock request failed: " + JSON.stringify(error))
      return
    }
    completedRequests++
    if (completedRequests === 3) {
      restartRequested = true
      if (!core.restart()) fail("core restart was rejected")
    }
  }

  function handleSnapshot() {
    if (!core.protocolReady || core.revision < 1
        || handledGeneration === core.generation) return
    handledGeneration = core.generation
    readyCount++
    if (core.snapshot.connection.online !== true
        || core.snapshot.identity.deviceId !== "TEST-ID"
        || core.snapshot.folders.length !== 1) {
      fail("snapshot projection failed")
      return
    }
    if (readyCount === 1) {
      core.configure({ probeIntervalSeconds: 2 }, requestCompleted)
      core.refresh(requestCompleted)
      core.action("folder.rescan", { folderId: "folder" }, requestCompleted)
    } else if (readyCount === 2 && restartRequested) {
      core.terminate()
      completionTimer.restart()
    }
  }

  function handlePendingSnapshot() {
    if (!pendingProbe.protocolReady || pendingProbe.revision < 1
        || pendingRequestSent) return
    pendingRequestSent = true
    var id = pendingProbe.refresh(function(ok, revision, data, error) {
      if (ok || !error || error.code !== "core_unavailable") {
        root.fail("pending request did not receive core-unavailable failure")
        return
      }
      root.pendingFailurePassed = true
      pendingProbe.terminate()
    })
    if (!id) fail("pending request was rejected")
  }

  CoreProcess {
    id: core
    pluginRoot: root.testPluginRoot

    onRevisionChanged: root.handleSnapshot()

    onProtocolFailed: function(message) { root.fail(message) }
  }

  CoreProcess {
    id: pendingProbe
    pluginRoot: root.testPluginRoot
    startupArguments: ["--test-exit-on-request"]
    onRevisionChanged: root.handlePendingSnapshot()
    onProtocolFailed: function(message) { root.fail(message) }
  }

  CoreProcess {
    id: versionProbe
    pluginRoot: root.testPluginRoot
    desiredRunning: false
    onProtocolFailed: function(message) {
      root.versionFailurePassed = message.indexOf("protocol major") >= 0
    }
  }

  CoreProcess {
    id: lineBoundProbe
    pluginRoot: root.testPluginRoot
    desiredRunning: false
    onProtocolFailed: function(message) {
      root.lineBoundPassed = message.indexOf("line bound") >= 0
    }
  }

  Timer {
    id: completionTimer
    interval: 100
    repeat: false
    onTriggered: {
      if (core.running || pendingProbe.running || !root.pendingFailurePassed) {
        restart()
        return
      }
      if (root.completedRequests !== 3 || root.readyCount !== 2
          || !root.versionFailurePassed || !root.lineBoundPassed
          || !root.pendingFailurePassed) {
        root.fail("core process lifecycle did not complete")
        return
      }
      console.log("core process tests passed")
      Qt.exit(0)
    }
  }

  Timer {
    interval: 1
    running: true
    repeat: false
    onTriggered: {
      versionProbe.handleLine('{"v":2,"type":"hello"}')
      lineBoundProbe.handleLine("x".repeat(lineBoundProbe.maxLineLength + 1))
    }
  }

  Timer {
    interval: 10000
    running: true
    repeat: false
    onTriggered: root.fail("core process test timed out")
  }
}
