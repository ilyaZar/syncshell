import QtQuick
import qs.Commons
import qs.Ui

Column {
  id: root

  property var controller
  property var syncthing
  property color foreground: Color.foreground
  property color dim: Qt.darker(foreground, 1.5)
  property color urgent: Color.urgent
  property color success: "#a3be8c"
  property color syncColor: "#26B6DB"
  property string fontFamily: Style.font.family

  width: parent ? parent.width : implicitWidth
  spacing: Style.space(8)

  Text {
    visible: root.controller.folderRows.length === 0
    width: parent.width
    text: root.syncthing && root.syncthing.online
      ? "No folders configured." : "Folder status is unavailable."
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
    horizontalAlignment: Text.AlignHCenter
  }

  Column {
    width: parent.width
    spacing: Style.space(6)

    Repeater {
      model: root.controller.visibleFolderRows

      FolderCard {
        required property var modelData
        width: parent.width
        folder: modelData
        selected: String(modelData.id || "")
          === root.controller.displayedFolderId
        mutationBusy: root.syncthing
          ? root.syncthing.folderMutationBusy : false
        stateLabel: root.controller.folderState(modelData)
        stateColor: root.controller.folderStateColor(modelData)
        meta: root.controller.folderMeta(modelData)
        activityActive: root.controller.folderHasActivity(modelData)
        activityDots: root.controller.visibleSyncDots
        activityDetail: root.controller.visibleSyncDetail
        activityAction: root.controller.visibleSyncAction
        foreground: root.foreground
        dim: root.dim
        urgent: root.urgent
        success: root.success
        syncColor: root.syncColor
        fontFamily: root.fontFamily
        onOpenRequested: root.controller.openFolder(modelData)
        onForgetRequested: root.controller.requestForget(modelData)
      }
    }
  }
}
