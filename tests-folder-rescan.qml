import QtQuick
import Quickshell
import "core"

ShellRoot {
  id: root

  property var requests: []

  FolderController {
    id: folderController
    apiReady: true
    online: true
    requestApi: function(name, options) {
      var next = root.requests.slice()
      next.push({ name: name, options: options })
      root.requests = next
      return { abort: function() {} }
    }
  }

  function compare(actual, expected, name) {
    if (JSON.stringify(actual) !== JSON.stringify(expected)) {
      throw new Error(name + ": expected " + JSON.stringify(expected)
        + ", got " + JSON.stringify(actual))
    }
  }

  function runTests() {
    folderController.folders = [{
      id: "active", label: "Active", paused: false
    }, {
      id: "paused", label: "Paused", paused: true
    }]
    compare(folderController.rescan("paused"), false,
      "paused folder rescan rejected")
    compare(folderController.mutationError,
      "Link the folder before rescanning it", "paused folder rescan error")

    compare(folderController.rescan("active"), true,
      "active folder rescan accepted")
    compare(requests[0], {
      name: "scanFolder",
      options: { method: "POST", query: { folder: "active" } }
    }, "folder rescan request")
    folderController.cancel("")

    compare(folderController.rescanAll(), true, "all folder rescan accepted")
    compare(requests[1], {
      name: "scanFolder", options: { method: "POST" }
    }, "all folder rescan request")
    folderController.cancel("")

    folderController.folders = []
    compare(folderController.rescanAll(), false, "empty folder rescan rejected")
    compare(folderController.mutationError, "No directories are configured",
      "empty folder rescan error")
  }

  Timer {
    interval: 1
    running: true
    onTriggered: {
      try {
        root.runTests()
        console.log("folder rescan tests passed")
        Qt.exit(0)
      } catch (error) {
        console.error(error)
        Qt.exit(1)
      }
    }
  }
}
