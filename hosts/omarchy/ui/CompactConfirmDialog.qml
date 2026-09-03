import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  property bool opened: false
  property string message: ""
  property string cancelText: "Cancel"
  property string confirmText: "Confirm"
  property int selectedIndex: 1
  property color background: Color.background
  property color foreground: Color.foreground
  property color scrim: Util.alpha(Color.background, 0.7)
  property color selectedBackground: Util.alpha(Color.foreground, 0.08)
  property color selectedText: Color.accent
  property string fontFamily: Style.font.family

  signal canceled()
  signal confirmed()

  visible: opened

  Rectangle {
    anchors.fill: parent
    color: root.scrim

    MouseArea {
      anchors.fill: parent
      onClicked: root.canceled()
    }

    BorderSurface {
      id: card
      width: Math.min(parent.width - Style.space(12), Style.space(390))
      height: card.contentTopInset + card.contentBottomInset
        + messageText.implicitHeight + Style.space(12) + Style.space(28)
      anchors.centerIn: parent
      color: root.background
      borderSpec: Border.flat(root.selectedText, Style.normalBorderWidth)
      padding: Style.space(12)
      radius: Style.cornerRadius

      MouseArea {
        anchors.fill: parent
        onClicked: {}
      }

      Item {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset

        Text {
          id: messageText
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          text: root.message
          textFormat: Text.PlainText
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          wrapMode: Text.WordWrap
        }

        Row {
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          spacing: Style.space(6)

          Repeater {
            model: [root.cancelText, root.confirmText]

            BorderSurface {
              required property int index
              required property string modelData

              readonly property bool selected: root.selectedIndex === index
              readonly property bool destructive: index === 1

              width: Style.space(76)
              height: Style.space(28)
              color: selected
                ? (destructive
                  ? Util.alpha(Color.urgent, 0.22)
                  : root.selectedBackground)
                : "transparent"
              borderSpec: Border.flat(destructive
                ? (selected
                  ? Color.urgent : Util.alpha(Color.urgent, 0.56))
                : (selected
                  ? root.selectedText : Util.alpha(root.foreground, 0.38)),
                Style.normalBorderWidth)
              radius: 0

              Text {
                anchors.centerIn: parent
                text: modelData
                textFormat: Text.PlainText
                color: destructive
                  ? (selected ? Color.urgent : root.foreground)
                  : (selected ? root.selectedText : root.foreground)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: root.selectedIndex = index
                onClicked: {
                  if (index === 0) root.canceled()
                  else root.confirmed()
                }
              }
            }
          }
        }
      }
    }
  }
}
