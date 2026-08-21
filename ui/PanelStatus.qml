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
        + (root.syncthing && root.syncthing.localDeviceId ? "  󰆏" : "")
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

    MouseArea {
      id: copyDeviceId
      anchors.left: hero.left
      anchors.leftMargin: hero.iconSize + Style.space(14)
      anchors.right: hero.right
      anchors.rightMargin: hero.trailingInset
      anchors.bottom: hero.bottom
      height: Style.space(18)
      enabled: root.syncthing && root.syncthing.localDeviceId !== ""
      hoverEnabled: enabled
      cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: root.controller.copyLocalDeviceId()

      PanelToolTip {
        visible: copyDeviceId.containsMouse
        text: "Copy Syncthing device ID"
        fontFamily: root.fontFamily
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
