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
  property color urgent: Color.urgent
  property color warning: "#ebcb8b"
  property color success: "#a3be8c"
  property string fontFamily: Style.font.family

  width: parent ? parent.width : implicitWidth
  spacing: Style.space(12)

  Item {
    id: header
    width: parent.width
    implicitHeight: hero.implicitHeight
    readonly property bool serviceAvailable: root.syncthing
      ? root.syncthing.canControlService : false
    readonly property bool serviceActive: root.syncthing
      ? root.syncthing.serviceActive : false
    readonly property bool serviceBusy: root.syncthing
      ? root.syncthing.serviceActionRunning
        || root.syncthing.folderMutationBusy : false

    PanelHero {
      id: hero
      width: parent.width
      title: "Syncthing"
      meta: root.controller.localDeviceName
      metaOpacity: 0
      foreground: root.foreground
      fontFamily: root.fontFamily
      iconOpacity: root.syncthing && root.syncthing.serviceActive
        && root.syncthing.online ? 1.0 : 0.5
      iconComponent: Component {
        Image {
          width: hero.iconSize
          height: width
          source: root.controller.syncthingIconSource
          sourceSize.width: 64
          sourceSize.height: 64
          fillMode: Image.PreserveAspectFit
          smooth: true
        }
      }
      trailingControl: Component {
        ToggleSwitch {
          id: powerSwitch
          visible: header.serviceAvailable
          checked: header.serviceActive
          busy: header.serviceBusy
          trackHeight: Style.space(16)
          cursorPad: Style.space(4)
          foreground: hero.foreground
          onToggled: root.controller.toggleSyncing()

          PanelToolTip {
            visible: powerSwitch.containsMouse
            text: root.controller.toggleHint
            fontFamily: hero.fontFamily
          }
        }
      }
    }

    Item {
      id: deviceMetaRow
      anchors.left: hero.left
      anchors.leftMargin: hero.iconSize + Style.space(14)
      anchors.right: hero.right
      anchors.rightMargin: hero.trailingInset
      anchors.bottom: hero.bottom
      height: Math.max(deviceNameText.implicitHeight,
        copyHostIdButton.height)

      Text {
        id: deviceNameText
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, Math.max(0,
          deviceMetaRow.width - (copyHostIdButton.visible
            ? copyHostIdButton.width + Style.space(4) : 0)))
        text: root.controller.localDeviceName.toUpperCase()
        color: Qt.darker(root.foreground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: 1.2
        elide: Text.ElideRight
      }

      Button {
        id: copyHostIdButton
        anchors.left: deviceNameText.right
        anchors.leftMargin: Style.space(4)
        anchors.verticalCenter: parent.verticalCenter
        visible: root.syncthing && root.syncthing.displayDeviceId !== ""
        height: Math.round(deviceNameText.implicitHeight)
        text: "host ID"
        iconText: "󰆏"
        tooltipText: "Copy host ID"
        bordered: true
        foreground: root.foreground
        fontFamily: root.fontFamily
        fontSize: Math.max(Style.space(8), Style.font.caption - 1)
        iconSize: Math.max(Style.space(7), Style.font.caption - 3)
        horizontalPadding: Style.space(4)
        verticalPadding: 0
        onClicked: root.controller.copyLocalDeviceId()
      }
    }
  }

  Text {
    visible: root.controller.visibleWarning !== ""
    width: parent.width
    text: root.controller.visibleWarning
    color: root.warning
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    wrapMode: Text.WordWrap
  }

  Text {
    visible: root.controller.visibleError !== ""
    width: parent.width
    text: root.controller.visibleError
    color: root.urgent
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    wrapMode: Text.WordWrap
  }

  Text {
    visible: root.controller.displayedNotice !== ""
    width: parent.width
    text: root.controller.displayedNotice
    opacity: root.controller.noticeShown ? 1 : 0
    color: root.success
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    wrapMode: Text.WordWrap

    Behavior on opacity {
      NumberAnimation {
        duration: root.controller.noticeShown ? 0 : 350
        easing.type: Easing.OutCubic
      }
    }
  }

  Column {
    width: parent.width
    spacing: Style.spacing.labelGap

    InfoPair {
      label: "Folders"
      value: root.syncthing ? String(root.syncthing.folderCount) : "—"
      foreground: root.foreground
      fontFamily: root.fontFamily
    }
    InfoPair {
      label: "Devices"
      value: root.syncthing
        ? root.syncthing.connectedDeviceCount + " of "
          + root.syncthing.deviceCount + " connected"
        : "—"
      foreground: root.foreground
      fontFamily: root.fontFamily
    }
    InfoPair {
      label: "Tracked"
      value: root.controller.formatCount(root.controller.trackedFiles)
        + " files · " + root.controller.formatBytes(root.controller.trackedBytes)
      foreground: root.foreground
      fontFamily: root.fontFamily
    }
  }
}
