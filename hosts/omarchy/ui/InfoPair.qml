import QtQuick
import QtQuick.Layouts
import qs.Commons

RowLayout {
  id: root

  property string label: ""
  property string value: ""
  property color foreground: "white"
  property string fontFamily: Style.font.family
  property int elideMode: Text.ElideRight
  property int valueTextFormat: Text.PlainText

  width: parent ? parent.width : implicitWidth
  spacing: Style.space(8)

  Text {
    text: root.label
    textFormat: Text.PlainText
    color: root.foreground
    opacity: 0.6
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  Text {
    Layout.fillWidth: true
    text: root.value
    textFormat: root.valueTextFormat
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    elide: root.elideMode
    horizontalAlignment: Text.AlignRight
  }
}
