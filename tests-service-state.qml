import QtQuick
import Quickshell
import "core"

ShellRoot {
  id: root

  property bool actionStarted: false
  property int ticks: 0
  readonly property bool expectFailure:
    Quickshell.env("SYNCSHELL_EXPECT_SYSTEMCTL_FAILURE") === "1"

  function fail(message) {
    console.error(message)
    Qt.exit(1)
  }

  function complete() {
    console.log("service state controller test passed")
    Qt.exit(0)
  }

  property InstallationController controller: InstallationController {
    helperPath: Quickshell.env("SYNCSHELL_INSTALL_HELPER")
    probeIntervalSeconds: 3600
  }

  property Timer pollTimer: Timer {
    interval: 20
    repeat: true
    running: true
    onTriggered: {
      root.ticks++
      if (root.ticks > 500) root.fail("service state controller test timed out")
      if (!root.actionStarted) {
        if (root.controller.refreshing
            || root.controller.state === "checking") return
        if (root.controller.unitFileState !== "disabled") {
          root.fail("initial disabled unit-file state was not observed")
        }
        if (!root.controller.setUnitFileState("enabled")) {
          root.fail("enable action was rejected")
        }
        root.actionStarted = true
        return
      }
      if (root.controller.refreshing
          || root.controller.unitFileActionRunning) return
      if (root.expectFailure) {
        if (root.controller.controlError.indexOf("permission denied") < 0) {
          root.fail("systemctl failure was not surfaced")
        }
        if (root.controller.unitFileState !== "disabled") {
          root.fail("failed enable changed the observed unit-file state")
        }
        root.complete()
      } else if (root.controller.unitFileState === "enabled") {
        if (root.controller.controlError !== "") {
          root.fail("successful enable retained a control error")
        }
        root.complete()
      }
    }
  }

  Component.onCompleted: {
    controller.statusTimer.stop()
    controller.updateStatus()
  }
}
