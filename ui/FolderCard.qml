import QtQuick
import qs.Commons
import qs.Ui

BorderSurface {
  id: root

  property var folder: ({})
  property bool selected: false
  property bool mutationBusy: false
  property string stateLabel: "UNKNOWN"
  property color stateColor: foreground
  property string meta: ""
  property bool activityActive: false
  property string activityDots: ""
  property string activityDetail: ""
  property string activityAction: ""
  property color foreground: Color.foreground
  property color dim: Qt.darker(foreground, 1.5)
  property color urgent: Color.urgent
  property color success: "#a3be8c"
  property color syncColor: "#26B6DB"
  property string fontFamily: Style.font.family

  readonly property bool problem: folder && folder.problem
  readonly property bool syncing: folder && folder.syncing
  readonly property bool canOpen: folder && String(folder.path || "") !== ""
  readonly property color cardBorderColor: problem
    ? urgent : (syncing ? foreground : dim)

  signal openRequested
  signal forgetRequested
  signal copyIdRequested(string folderId)

  implicitHeight: nameBadge.implicitHeight + details.implicitHeight
    + Style.space(14)
  color: rowMouse.containsMouse
    ? Style.hoverFillFor(cardBorderColor, Color.accent) : "transparent"
  borderSpec: Border.controlSpec(
    selected ? "focus" : "normal", cardBorderColor, Color.accent)
  radius: Style.cornerRadius

  MouseArea {
    id: rowMouse
    anchors.fill: parent
    enabled: root.canOpen
    hoverEnabled: true
    cursorShape: root.canOpen ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: root.openRequested()
  }

  BorderSurface {
    id: nameBadge
    z: 1
    anchors.left: parent.left
    anchors.top: parent.top
    width: Math.min(nameText.implicitWidth + copyIdButton.width
      + Style.space(16),
      parent.width - stateBadge.width - Style.space(8))
    implicitHeight: nameText.implicitHeight + Style.space(6)
    height: implicitHeight
    color: "transparent"
    borderSpec: Border.withWidth(Border.controlSpec(
      "normal", root.cardBorderColor, Color.accent), "0 1 1 0")
    radius: 0

    Text {
      id: nameText
      anchors.fill: parent
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: copyIdButton.width + Style.space(4)
      text: String(root.folder.label || "Unnamed folder")
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      font.bold: true
      verticalAlignment: Text.AlignVCenter
      elide: Text.ElideRight
    }

    PanelActionButton {
      id: copyIdButton
      anchors.right: parent.right
      anchors.rightMargin: Style.space(2)
      anchors.verticalCenter: parent.verticalCenter
      size: Style.space(18)
      iconText: "󰆏"
      tooltipText: "Copy folder ID"
      foreground: root.foreground
      fontFamily: root.fontFamily
      fontSize: Style.font.caption
      onClicked: root.copyIdRequested(String(root.folder.id || ""))
    }
  }

  BorderSurface {
    id: stateBadge
    z: 1
    anchors.right: parent.right
    anchors.top: parent.top
    implicitWidth: stateText.implicitWidth + Style.space(10)
    width: implicitWidth
    height: nameBadge.height
    color: "transparent"
    borderSpec: Border.withWidth(Border.controlSpec(
      "normal", root.stateColor, Color.accent), "0 0 1 1")
    radius: 0

    Text {
      id: stateText
      anchors.centerIn: parent
      text: root.stateLabel
      color: root.stateColor
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }
  }

  Column {
    id: details
    z: 1
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: nameBadge.bottom
    anchors.leftMargin: Style.space(8)
    anchors.rightMargin: root.folder.paused
      ? forgetButton.width + Style.space(14) : Style.space(8)
    anchors.topMargin: Style.space(6)
    spacing: Style.space(1)

    ActivityText {
      width: parent.width
      active: root.activityActive
      dots: root.activityDots
      detail: root.activityDetail
      action: root.activityAction
      foreground: root.foreground
      syncColor: root.syncColor
      removalColor: root.urgent
      uploadColor: root.success
      fontFamily: root.fontFamily
    }

    Text {
      width: parent.width
      text: root.meta
      color: root.problem ? root.urgent : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }

    Text {
      visible: root.canOpen
      width: parent.width
      text: String(root.folder.path || "")
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideLeft
    }
  }

  Button {
    id: forgetButton
    z: 1
    visible: root.folder && root.folder.paused
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.margins: Style.space(6)
    width: implicitWidth
    height: implicitHeight
    text: "FORGET"
    tooltipText: "Remove only this unlinked Syncthing configuration"
    bordered: true
    foreground: root.urgent
    fontFamily: root.fontFamily
    fontSize: Style.font.caption
    horizontalPadding: Style.space(5)
    verticalPadding: Style.space(2)
    enabled: !root.mutationBusy
    onClicked: root.forgetRequested()
  }
}
