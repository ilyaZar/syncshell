import QtQuick
import QtQuick.Dialogs

Window {
  id: root

  width: 875
  height: 600
  visible: true
  opacity: 0
  flags: Qt.Dialog

  Component.onCompleted: folderDialog.open()

  FolderDialog {
    id: folderDialog
    title: "Choose a Syncthing folder"
    acceptLabel: "Choose"
    onAccepted: {
      console.log("SYNCTHING_FOLDER=" + String(selectedFolder))
      Qt.quit()
    }
    onRejected: Qt.quit()
  }
}
