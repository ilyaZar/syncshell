import QtQuick
import qs.Commons

Item {
    id: root

    property int selectedIndex: 0
    property string fontFamily: Style.font.family
    signal highlightRequested(int index)
    signal activated(int index)

    readonly property var rows: [
        {
            title: "Open settings file",
            description: "Edit icon and Web UI preferences",
            separatorBefore: false,
            dangerous: false
        },
        {
            title: "Cleanly remove Syncthing plugin",
            description: "Optionally delete plugin settings",
            separatorBefore: false,
            dangerous: true
        },
        {
            title: "Back [q / Esc]",
            description: "Return to Syncthing",
            separatorBefore: true,
            dangerous: false
        }
    ]

    implicitHeight: menuColumn.implicitHeight

    Column {
        id: menuColumn
        width: parent.width
        spacing: Style.space(3)

        Text {
            width: parent.width
            bottomPadding: Style.spacing.sm
            text: "SETTINGS"
            color: Color.menu.text
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 0.8
        }

        Repeater {
            model: root.rows

            delegate: Rectangle {
                id: menuRow
                required property int index
                required property var modelData

                width: menuColumn.width
                height: Style.space(60)
                radius: Style.cornerRadius
                color: root.selectedIndex === index ? Color.menu.selectedBackground : "transparent"

                Rectangle {
                    visible: menuRow.modelData.separatorBefore
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    height: Math.max(1, Style.space(1))
                    color: Util.alpha(Color.menu.text, 0.18)
                }

                Column {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: Style.spacing.md
                    anchors.rightMargin: Style.spacing.md
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(2)

                    Text {
                        width: parent.width
                        text: menuRow.modelData.title
                        textFormat: Text.PlainText
                        color: root.selectedIndex === menuRow.index ? Color.menu.selectedText : (menuRow.modelData.dangerous ? Color.urgent : Color.menu.text)
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.title
                        font.bold: true
                        elide: Text.ElideRight
                    }

                    Text {
                        width: parent.width
                        text: menuRow.modelData.description
                        textFormat: Text.PlainText
                        color: root.selectedIndex === menuRow.index ? Color.menu.selectedText : Color.menu.text
                        opacity: 0.65
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                        elide: Text.ElideRight
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: root.highlightRequested(menuRow.index)
                    onClicked: root.activated(menuRow.index)
                }
            }
        }
    }
}
