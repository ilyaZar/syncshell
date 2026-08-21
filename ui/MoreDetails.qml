import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
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
  property string fontFamily: Style.font.family
  readonly property bool folderPopupOpen: folderSelector.popupOpen
  readonly property bool pendingPopupOpen: pendingOfferSelector.popupOpen

  function closePopups() {
    if (folderSelector.popupOpen) folderSelector.close()
    if (pendingOfferSelector.popupOpen) pendingOfferSelector.close()
  }

  width: parent ? parent.width : implicitWidth
  spacing: Style.space(8)

  PanelSectionHeader {
    text: "FOLDERS"
    foreground: root.foreground
    fontFamily: root.fontFamily
  }

  RowLayout {
    width: parent.width
    spacing: Style.space(6)

    ToggleDropdown {
      id: folderSelector
      visible: root.controller.folderRows.length > 0
      Layout.fillWidth: true
      Layout.preferredHeight: Style.space(28)
      showLabel: false
      rowHeight: Style.space(28)
      value: root.controller.selectedFolderId
      options: root.controller.folderOptions()
      foreground: root.foreground
      fontFamily: root.fontFamily
      onChanged: function(value) { root.controller.selectedFolderId = value }
    }

    Button {
      text: "+"
      Layout.preferredHeight: Style.space(28)
      tooltipText: root.controller.addOpen
        ? "Close add folder form" : "Add folder"
      bordered: true
      foreground: root.foreground
      fontFamily: root.fontFamily
      fontSize: Style.font.body
      horizontalPadding: Style.space(7)
      verticalPadding: Style.space(3)
      enabled: root.syncthing && root.syncthing.online
        && !root.syncthing.folderMutationBusy
      onClicked: root.controller.addOpen
        ? root.controller.closeAddFolder() : root.controller.openAddFolder()
    }

    Button {
      readonly property var targetFolder: root.controller.selectedFolder()
      readonly property bool targetBusy: root.syncthing
        && root.syncthing.folderMutationBusy
        && root.syncthing.folderMutationId === root.controller.selectedFolderId
      visible: root.controller.folderRows.length > 0
      Layout.preferredHeight: Style.space(28)
      text: targetBusy ? "WAIT"
        : (targetFolder && targetFolder.paused ? "LINK" : "UNLINK")
      tooltipText: targetFolder
        ? (targetFolder.paused
          ? "Resume synchronization for " + targetFolder.label
          : "Pause synchronization for " + targetFolder.label)
          + "\n" + targetFolder.path
        : "Select a folder"
      bordered: true
      foreground: root.foreground
      fontFamily: root.fontFamily
      fontSize: Style.font.caption
      horizontalPadding: Style.space(6)
      verticalPadding: Style.space(4)
      enabled: targetFolder && root.syncthing && root.syncthing.online
        && !root.syncthing.folderMutationBusy
      onClicked: root.syncthing.setFolderLinked(
        targetFolder.id, targetFolder.paused)
    }
  }

  RowLayout {
    visible: root.controller.pendingOfferRows.length > 0
    width: parent.width
    spacing: Style.space(6)

    ToggleDropdown {
      id: pendingOfferSelector
      Layout.fillWidth: true
      Layout.preferredHeight: Style.space(28)
      showLabel: false
      rowHeight: Style.space(28)
      value: root.controller.selectedPendingOffer
      options: root.controller.pendingOfferRows
      foreground: root.foreground
      fontFamily: root.fontFamily
      onChanged: function(value) {
        root.controller.selectedPendingOffer = value
      }
    }

    Button {
      text: "ACCEPT"
      Layout.preferredHeight: Style.space(28)
      tooltipText: "Prepare this offered folder for local acceptance"
      bordered: true
      foreground: root.success
      fontFamily: root.fontFamily
      fontSize: Style.font.caption
      horizontalPadding: Style.space(6)
      verticalPadding: Style.space(4)
      enabled: root.syncthing && root.syncthing.online
        && !root.syncthing.folderMutationBusy
        && root.controller.selectedPendingOffer !== ""
      onClicked: root.controller.acceptPendingFolderOffer(
        root.controller.selectedPendingOffer)
    }
  }

  PanelSeparator {
    foreground: root.foreground
  }

  Row {
    width: parent.width
    spacing: Style.space(6)

    PanelSectionHeader {
      width: parent.width - installationHelp.width - parent.spacing
      anchors.verticalCenter: parent.verticalCenter
      text: "INSTALLATION"
      foreground: root.foreground
      fontFamily: root.fontFamily
    }

    Button {
      id: installationHelp
      implicitWidth: implicitHeight
      text: "?"
      tooltipText: "Installs the official package through Omarchy "
        + "when Syncthing is absent. Removal is manual."
      foreground: root.foreground
      fontFamily: root.fontFamily
      fontSize: Style.font.caption
      horizontalPadding: 0
      bordered: true
      focusable: true
    }
  }

  InfoPair {
    label: "Installation"
    value: {
      if (!root.syncthing) return "Unavailable"
      if (root.syncthing.installationState === "existing") {
        return "Existing installation found: <font color=\""
          + root.success + "\">working</font>"
      }
      if (root.syncthing.installationState === "incomplete") {
        return "Incomplete installation: <font color=\""
          + root.urgent + "\">non-working</font>"
      }
      return root.syncthing.installationLabel
    }
    valueTextFormat: Text.StyledText
    foreground: root.foreground
    fontFamily: root.fontFamily
  }

  InfoPair {
    visible: root.syncthing && root.syncthing.executablePath !== ""
    label: "Executable"
    value: root.syncthing ? root.syncthing.executablePath : ""
    elideMode: Text.ElideLeft
    foreground: root.foreground
    fontFamily: root.fontFamily
  }

  Text {
    visible: text !== ""
    width: parent.width
    text: {
      if (!root.syncthing) return "Installation status unavailable."
      if (root.syncthing.installationState === "existing") return ""
      if (root.syncthing.installationState === "incomplete") {
        return "Repair or remove the incomplete installation manually."
      }
      if (root.syncthing.installationState === "missing") {
        return "Installs through Omarchy. Removal is manual."
      }
      return "Checking installation."
    }
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    elide: Text.ElideRight
    wrapMode: Text.NoWrap
  }

  Text {
    visible: root.syncthing && root.syncthing.packageStatus !== ""
    width: parent.width
    text: root.syncthing ? root.syncthing.packageStatus : ""
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    elide: Text.ElideRight
    wrapMode: Text.NoWrap
  }

  Button {
    visible: root.syncthing && root.syncthing.canInstall
    text: "Install Syncthing"
    bordered: true
    foreground: root.foreground
    fontFamily: root.fontFamily
    enabled: root.syncthing && root.syncthing.canInstall
    onClicked: root.controller.installationAction()
  }
}
