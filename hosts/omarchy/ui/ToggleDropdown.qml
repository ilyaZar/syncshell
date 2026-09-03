import QtQuick
import qs.Ui as Ui

Ui.Dropdown {
  id: root

  property double lastClosedAt: 0

  onPopupOpenChanged: if (!popupOpen) lastClosedAt = Date.now()

  MouseArea {
    anchors.fill: parent
    z: 10
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor

    onEntered: root.hasCursor = true
    onExited: root.hasCursor = false
    onPressed: function(mouse) {
      if (root.popupOpen) root.close()
      mouse.accepted = true
    }
    onClicked: function(mouse) {
      if (root.popupOpen) root.close()
      else if (Date.now() - root.lastClosedAt > 150) root.open()
      mouse.accepted = true
    }
  }
}
