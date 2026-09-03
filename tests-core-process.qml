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
  readonly property string mockPath: localPath(
    Qt.resolvedUrl("tests/core-process-mock.sh"))

  function localPath(url) {
    var value = String(url || "")
    if (value.indexOf("file://") === 0) value = value.slice(7)
    return decodeURIComponent(value)
  }

  function fail(message) {
    console.error(message)
    core.terminate()
    Qt.exit(1)
  }

  function requestCompleted(ok, revision, error) {
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

  CoreProcess {
    id: core
    corePath: root.mockPath

    onRevisionChanged: root.handleSnapshot()

    onProtocolFailed: function(message) { root.fail(message) }
  }

  CoreProcess {
    id: versionProbe
    corePath: root.mockPath
    desiredRunning: false
    onProtocolFailed: function(message) {
      root.versionFailurePassed = message.indexOf("protocol major") >= 0
    }
  }

  CoreProcess {
    id: lineBoundProbe
    corePath: root.mockPath
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
      if (core.running) {
        restart()
        return
      }
      if (root.completedRequests !== 3 || root.readyCount !== 2
          || !root.versionFailurePassed || !root.lineBoundPassed) {
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
