import QtQuick
import QtQuick.Effects

Item {
  id: root

  property url source
  property color tint: "#ffffff"

  // The mono assets are pure white artwork. MultiEffect's colorization only
  // swaps hue and saturation and keeps the source lightness, so a white glyph
  // stays white whatever the tint is -- unreadable against a light bar. Mask a
  // solid tint rectangle with the artwork's alpha instead: that recolors in
  // both directions and still antialiases the edges.
  Image {
    id: image
    anchors.fill: parent
    source: root.source
    sourceSize.width: Math.round(width * Screen.devicePixelRatio)
    sourceSize.height: Math.round(height * Screen.devicePixelRatio)
    fillMode: Image.PreserveAspectFit
    smooth: true
    visible: false
    layer.enabled: true
  }

  Rectangle {
    id: tintSource
    anchors.fill: image
    color: root.tint
    visible: false
    layer.enabled: true
  }

  // min 0.5 with spread 1.0 makes the mask curve span the full alpha range,
  // so partially covered edge pixels stay partially covered.
  MultiEffect {
    anchors.fill: image
    source: tintSource
    maskEnabled: true
    maskSource: image
    maskThresholdMin: 0.5
    maskSpreadAtMin: 1.0
  }
}
