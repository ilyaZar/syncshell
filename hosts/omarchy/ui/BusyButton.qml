import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  property string text: ""
  property string busyText: text
  property string iconText: ""
  property string tooltipText: ""
  property bool busy: false
  property bool canActivate: true
  property bool bordered: false
  property bool focusable: false
  property color foreground: Color.foreground
  property color busyForeground: foreground
  property color disabledForeground: Qt.darker(foreground, 1.6)
  property string fontFamily: Style.font.family
  property real fontSize: Style.font.body
  property real iconSize: Style.font.icon
  property real horizontalPadding: Style.spacing.controlPaddingX
  property real verticalPadding: Style.spacing.controlPaddingY

  readonly property bool interactive: enabled && canActivate && !busy
  readonly property bool inputTargetEnabled:
    interactiveButton.visible && interactiveButton.enabled
  readonly property color inertForeground:
    busy ? busyForeground : disabledForeground
  readonly property string inertText: busy ? busyText : text
  readonly property real busyIconRotation: inertIcon.rotation
  readonly property real inertContentWidth:
    inertIcon.implicitWidth + inertLabel.implicitWidth
      + (iconText !== "" && inertText !== ""
          ? Style.spacing.controlGap : 0)

  signal clicked

  function activate() {
    if (!interactive) return false
    clicked()
    return true
  }

  implicitWidth: Math.max(
    interactiveButton.implicitWidth,
    inertContentWidth + horizontalPadding * 2
      + inertButton.borderLeft + inertButton.borderRight)
  implicitHeight: interactiveButton.implicitHeight

  Button {
    id: interactiveButton
    anchors.fill: parent
    visible: root.interactive
    text: root.text
    iconText: root.iconText
    tooltipText: root.tooltipText
    bordered: root.bordered
    focusable: root.focusable
    foreground: root.foreground
    fontFamily: root.fontFamily
    fontSize: root.fontSize
    iconSize: root.iconSize
    horizontalPadding: root.horizontalPadding
    verticalPadding: root.verticalPadding
    onClicked: root.activate()
  }

  BorderSurface {
    id: inertButton
    anchors.fill: parent
    visible: !root.interactive
    color: "transparent"
    radius: Style.cornerRadius
    borderSpec: root.bordered
      ? Border.controlSpec("normal", root.inertForeground, Color.accent)
      : Border.none()

    HoverHandler {
      cursorShape: Qt.ArrowCursor
    }

    Row {
      anchors.centerIn: parent
      spacing: Style.spacing.controlGap

      Text {
        id: inertIcon
        textFormat: Text.PlainText
        visible: root.iconText !== ""
        text: root.iconText
        color: root.inertForeground
        font.family: root.fontFamily
        font.pixelSize: root.iconSize
        transformOrigin: Item.Center
        anchors.verticalCenter: parent.verticalCenter

        RotationAnimation on rotation {
          from: 0
          to: 360
          duration: 900
          loops: Animation.Infinite
          running: root.busy
        }
      }

      Text {
        id: inertLabel
        textFormat: Text.PlainText
        visible: root.inertText !== ""
        text: root.inertText
        color: root.inertForeground
        font.family: root.fontFamily
        font.pixelSize: root.fontSize
        anchors.verticalCenter: parent.verticalCenter
      }
    }
  }
}
