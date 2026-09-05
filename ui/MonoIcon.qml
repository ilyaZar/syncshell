import QtQuick
import QtQuick.Effects

Item {
  id: root

  property url source
  property color tint: "#ffffff"

  Image {
    id: image
    anchors.fill: parent
    source: root.source
    sourceSize.width: width
    sourceSize.height: height
    fillMode: Image.PreserveAspectFit
    smooth: true
    visible: false
    layer.enabled: true
  }

  MultiEffect {
    anchors.fill: image
    source: image
    colorization: 1.0
    colorizationColor: root.tint
  }
}
