import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

ShellRoot {
  id: root

  property StandaloneService service: StandaloneService {
    corePath: Quickshell.env("SYNCSHELL_CORE_PATH") || ""
    configPath: Quickshell.env("SYNCSHELL_CONFIG_PATH") || ""
  }

  FloatingWindow {
    visible: true
    width: 640
    height: 480
    title: "Syncshell standalone contract harness"

    Rectangle {
      anchors.fill: parent
      color: "#181825"

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 10

        Label {
          text: root.service.online ? "Syncthing online" : "Syncthing unavailable"
          color: root.service.online ? "#a6e3a1" : "#f38ba8"
          font.pixelSize: 20
        }

        Label {
          text: "Device: " + (root.service.deviceId || "unknown")
          color: "#cdd6f4"
        }

        Label {
          text: "Folders: " + root.service.folders.length
          color: "#cdd6f4"
        }

        RowLayout {
          Button { text: "Refresh"; onClicked: root.service.refresh() }
          Button {
            text: "Rescan first"
            enabled: root.service.folders.length > 0
            onClicked: root.service.rescan(root.service.folders[0].id)
          }
          Button { text: "Restart core"; onClicked: root.service.restart() }
        }

        ScrollView {
          Layout.fillWidth: true
          Layout.fillHeight: true

          TextArea {
            readOnly: true
            color: "#cdd6f4"
            text: JSON.stringify(root.service.snapshot, null, 2)
            wrapMode: TextEdit.Wrap
          }
        }
      }
    }
  }

  IpcHandler {
    target: "syncshell-standalone"

    function status(): string { return JSON.stringify(root.service.snapshot) }
    function refresh(): void { root.service.refresh() }
    function rescan(folderId: string): void { root.service.rescan(folderId) }
    function restart(): void { root.service.restart() }
  }
}
