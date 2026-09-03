import QtQuick
import Quickshell
import "hosts/standalone"

ShellRoot {
  id: root

  property int results: 0
  property bool started: false

  function localPath(url) {
    var value = String(url || "")
    if (value.indexOf("file://") === 0) value = value.slice(7)
    return decodeURIComponent(value)
  }

  function fail(message) {
    console.error(message)
    service.stop()
    Qt.exit(1)
  }

  function startActions() {
    if (started || !service.protocolReady || service.revision < 1) return
    started = true
    service.configure(2, "disabled")
    service.refresh()
    service.pause("folder")
    service.resume("folder")
    service.rescan("folder")
    service.rescanAll()
    service.forget("folder")
    service.addExisting({ folderId: "new", path: "/tmp/new" })
    service.suggestFolderId()
    service.lifecycle("start")
    service.lifecycle("stop")
    service.lifecycle("enable")
    service.lifecycle("disable")
    service.setWebUiTheme("default")
  }

  StandaloneService {
    id: service
    pluginRoot: Quickshell.env("SYNCSHELL_TEST_PLUGIN_ROOT") || ""

    onRevisionChanged: root.startActions()
    onProtocolReadyChanged: root.startActions()
    onActionFinished: function(id, ok, data, error) {
      if (!ok || error) {
        root.fail("standalone action failed: " + id)
        return
      }
      root.results++
      if (root.results === 14) {
        service.stop()
        completionTimer.restart()
      }
    }
  }

  Timer {
    id: completionTimer
    interval: 100
    repeat: false
    onTriggered: {
      if (service.processRunning) {
        restart()
        return
      }
      console.log("standalone service tests passed")
      Qt.exit(0)
    }
  }

  Timer {
    interval: 10000
    running: true
    repeat: false
    onTriggered: root.fail("standalone service test timed out")
  }
}
