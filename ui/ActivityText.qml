import QtQuick
import qs.Commons

Row {
  id: root

  property bool active: false
  property string dots: ""
  property string detail: ""
  property string action: ""
  property color foreground: "white"
  property color syncColor: "#26B6DB"
  property color removalColor: "#bf616a"
  property color uploadColor: "#a3be8c"
  property string fontFamily: Style.font.family
  property int fontSize: Style.font.caption

  height: activityLabel.implicitHeight
  spacing: 0

  function actionColor() {
    if (action === "removing") return removalColor
    if (action === "upload") return uploadColor
    return syncColor
  }

  Text {
    id: activityLabel
    text: root.active ? "File syncing" : " "
    textFormat: Text.PlainText
    color: root.syncColor
    font.family: root.fontFamily
    font.pixelSize: root.fontSize
  }

  Item {
    id: dotsSlot
    width: dotsProbe.implicitWidth
    height: dotsProbe.implicitHeight

    Text {
      text: root.active ? root.dots : ""
      textFormat: Text.PlainText
      color: root.syncColor
      font.family: root.fontFamily
      font.pixelSize: root.fontSize
    }

    Text {
      id: dotsProbe
      visible: false
      text: "..."
      textFormat: Text.PlainText
      font.family: root.fontFamily
      font.pixelSize: root.fontSize
    }
  }

  Text {
    width: Math.max(0, root.width - activityLabel.implicitWidth
      - dotsSlot.width)
    text: root.active ? " " + root.detail : ""
    textFormat: Text.PlainText
    color: root.actionColor()
    font.family: root.fontFamily
    font.pixelSize: root.fontSize
    elide: Text.ElideRight
  }
}
