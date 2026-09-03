import QtQuick
import Quickshell
import "hosts/omarchy"

ShellRoot {
  id: root

  property bool exhausted: false
  readonly property string marker:
    Quickshell.env("SYNCSHELL_RECOVERY_MARKER") || ""

  function fail(message) {
    console.error(message)
    service.core.terminate()
    Qt.exit(1)
  }

  OmarchyService {
    id: service
  }

  Timer {
    interval: 25
    repeat: true
    running: true
    onTriggered: {
      if (root.exhausted && service.core.protocolReady) {
        stop()
        service.packageController.state = "missing"
        presentationTimer.restart()
        return
      }
      if (root.exhausted || service.core.running
          || service.core.restartTimer.running
          || service.core.restartAttempts < service.core.maxRestartAttempts) {
        return
      }
      root.exhausted = true
      Quickshell.execDetached(["/usr/bin/touch", root.marker])
      statusTimer.restart()
    }
  }

  Timer {
    id: presentationTimer
    interval: 25
    repeat: false
    onTriggered: {
      if (!service.online || service.installationState !== "existing"
          || service.canInstall || service.serviceAvailable
          || service.canControlService || service.summaryText !== "Up to date") {
        root.fail("external instance presentation is incorrect")
        return
      }
      service.core.terminate()
      console.log("install recovery test passed")
      Qt.exit(0)
    }
  }

  Timer {
    id: statusTimer
    interval: 100
    repeat: false
    onTriggered: service.packageController.updateStatus()
  }

  Timer {
    interval: 10000
    running: true
    repeat: false
    onTriggered: root.fail("install recovery test timed out")
  }
}
