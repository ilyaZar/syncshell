import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui

BorderSurface {
  id: root

  property var controller
  property var syncthing
  property bool folderPickerRunning: false
  property color foreground: Color.foreground
  property color dim: Qt.darker(foreground, 1.5)
  property color urgent: Color.urgent
  property color warning: "#ebcb8b"
  property color success: "#a3be8c"
  property string fontFamily: Style.font.family
  property alias pathText: addPathField.text
  property alias labelText: addLabelField.text
  property alias idText: addIdField.text
  property alias selectedDeviceIds: devicePicker.values
  property alias pendingFolderValue: pendingFolderPicker.value

  function reset() {
    addPathField.text = ""
    addLabelField.text = ""
    addIdField.text = ""
    devicePicker.values = []
    pendingFolderPicker.value = ""
    devicePicker.close()
  }

  function closePopups() {
    if (devicePicker.popupOpen) devicePicker.close()
  }

  function focusPath() {
    addPathField.forceActiveFocus()
  }

  width: parent ? parent.width : implicitWidth
  implicitHeight: addColumn.implicitHeight + Style.space(16)
  color: "transparent"
  borderSpec: Border.controlSpec("normal", foreground, Color.accent)
  radius: Style.cornerRadius
  Keys.onPressed: function(event) {
    if (event.key === Qt.Key_Escape) {
      controller.closeAddFolder()
      event.accepted = true
    }
  }

  Column {
    id: addColumn
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: Style.space(8)
    spacing: Style.space(6)

    RowLayout {
      width: parent.width

      PanelSectionHeader {
        Layout.fillWidth: true
        text: "ADD FOLDER"
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      Button {
        text: "CANCEL"
        bordered: true
        foreground: root.urgent
        fontFamily: root.fontFamily
        fontSize: Style.font.caption
        horizontalPadding: Style.space(6)
        verticalPadding: Style.space(4)
        enabled: !root.syncthing || !root.syncthing.folderMutationBusy
        onClicked: root.controller.closeAddFolder()
      }
    }

    Dropdown {
      id: pendingFolderPicker
      visible: options.length > 1
      width: parent.width
      showLabel: false
      value: ""
      options: root.controller.pendingFolderOptions()
      foreground: root.foreground
      fontFamily: root.fontFamily
      onChanged: function(value) { root.controller.applyPendingFolder(value) }
    }

    Text {
      readonly property int encryptedCount:
        root.controller.encryptedPendingOfferCount()
      visible: encryptedCount > 0
      width: parent.width
      text: encryptedCount + " encrypted folder offer"
        + (encryptedCount === 1 ? " requires" : "s require")
        + " the Syncthing Web UI."
      textFormat: Text.PlainText
      color: root.warning
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }

    Text {
      text: "Existing directory"
      textFormat: Text.PlainText
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }

    RowLayout {
      width: parent.width
      spacing: Style.space(6)

      TextField {
        id: addPathField
        Layout.fillWidth: true
        enabled: !root.syncthing || !root.syncthing.folderMutationBusy
        placeholderText: "/path/to/existing/folder"
        foreground: root.foreground
      }

      Button {
        text: "BROWSE"
        tooltipText: "Choose an existing local directory"
        bordered: true
        foreground: root.foreground
        fontFamily: root.fontFamily
        fontSize: Style.font.caption
        enabled: (!root.syncthing || !root.syncthing.folderMutationBusy)
          && !root.folderPickerRunning
        onClicked: root.controller.browseForFolder()
      }
    }

    Text {
      text: "Label"
      textFormat: Text.PlainText
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }

    TextField {
      id: addLabelField
      width: parent.width
      enabled: !root.syncthing || !root.syncthing.folderMutationBusy
      placeholderText: "Derived from the directory name when empty"
      foreground: root.foreground
      onTextEdited: root.controller.addLabelFromOffer = false
    }

    Text {
      text: "Folder ID"
      textFormat: Text.PlainText
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }

    RowLayout {
      width: parent.width
      spacing: Style.space(6)

      TextField {
        id: addIdField
        Layout.fillWidth: true
        enabled: !root.syncthing || !root.syncthing.folderMutationBusy
        placeholderText: root.syncthing
          && root.syncthing.folderPreparationBusy
          ? "Generating..." : "Required folder identity"
        foreground: root.foreground
        onTextEdited: root.controller.addIdEdited = true
        onAccepted: root.controller.submitAddFolder()
      }

      Button {
        text: "NEW ID"
        tooltipText: "Generate a new Syncthing folder ID"
        bordered: true
        foreground: root.foreground
        fontFamily: root.fontFamily
        fontSize: Style.font.caption
        enabled: root.syncthing && !root.syncthing.folderPreparationBusy
          && !root.syncthing.folderMutationBusy
        onClicked: {
          root.controller.addIdEdited = false
          addIdField.text = ""
          pendingFolderPicker.value = ""
          root.syncthing.requestFolderIdSuggestion()
        }
      }
    }

    Text {
      width: parent.width
      text: "Reuse the exact ID to rejoin an existing remote folder. "
        + "A new ID creates a different folder identity."
      textFormat: Text.PlainText
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }

    MultiSelect {
      id: devicePicker
      property double lastClosedAt: 0
      width: parent.width
      label: "Share with devices"
      values: []
      options: root.controller.deviceOptions()
      noSelectionText: "Local only"
      placeholderText: "Find a device..."
      foreground: root.foreground
      fontFamily: root.fontFamily

      onPopupOpenChanged: if (!popupOpen) lastClosedAt = Date.now()

      MouseArea {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: parent.rowHeight
        z: 10
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        onEntered: parent.hasCursor = true
        onExited: parent.hasCursor = false
        onPressed: function(mouse) {
          if (parent.popupOpen) parent.close()
          mouse.accepted = true
        }
        onClicked: function(mouse) {
          if (parent.popupOpen) parent.close()
          else if (Date.now() - parent.lastClosedAt > 150) parent.open()
          mouse.accepted = true
        }
      }

      Button {
        parent: devicePicker.Overlay.overlay || devicePicker
        readonly property real buttonSize: devicePicker.popupRowHeight
          + Style.spacing.controlPaddingX - Style.spacing.md * 2
        readonly property point popupOrigin: parent
          ? devicePicker.mapToItem(
            parent, 0, devicePicker.height + Style.spacing.xxs)
          : Qt.point(0, 0)
        visible: devicePicker.popupOpen
        x: popupOrigin.x + devicePicker.width - width
          - Border.right(devicePicker.popupBorderSpec)
          - Style.spacing.hairline - Style.spacing.md
        y: popupOrigin.y + Border.top(devicePicker.popupBorderSpec)
          + Style.spacing.hairline + Style.spacing.md
        width: buttonSize
        height: buttonSize
        z: 10000
        text: "OK"
        bordered: true
        foreground: root.success
        fontFamily: root.fontFamily
        fontSize: Style.font.caption
        horizontalPadding: 0
        verticalPadding: 0
        onClicked: devicePicker.close()
      }
    }

    Text {
      width: parent.width
      text: devicePicker.values.length === 0
        ? "Local only: this folder will not synchronize with another device."
        : "Selected devices receive a share offer and may need to accept it."
      textFormat: Text.PlainText
      color: devicePicker.values.length === 0 ? root.warning : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }

    Text {
      visible: root.syncthing
        && root.syncthing.folderPreparationError !== ""
      width: parent.width
      text: root.syncthing ? root.syncthing.folderPreparationError : ""
      textFormat: Text.PlainText
      color: root.urgent
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }

    Button {
      width: parent.width
      text: root.syncthing && root.syncthing.folderMutationBusy
        && root.syncthing.folderMutationAction === "add"
        ? "ADDING..." : "ADD FOLDER"
      bordered: true
      foreground: root.foreground
      fontFamily: root.fontFamily
      enabled: root.syncthing && root.syncthing.online
        && !root.syncthing.folderMutationBusy
        && String(addPathField.text || "").trim() !== ""
        && String(addIdField.text || "").trim() !== ""
      onClicked: root.controller.submitAddFolder()
    }
  }
}
