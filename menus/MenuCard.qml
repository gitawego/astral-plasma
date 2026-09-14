import QtQuick
import "../theme"

Rectangle {
    id: root

    default property alias content: contentLayout.data
    property alias spacing: contentLayout.spacing

    implicitWidth: 220
    implicitHeight: contentLayout.implicitHeight + 16

    radius: 14
    color: (typeof Colors !== "undefined" && Colors.surfaceContainerLowest) ? Colors.surfaceContainerLowest : "#1e1b24"
    border.color: (typeof Colors !== "undefined" && Colors.outlineVariant) ? Colors.outlineVariant : "#49454e"
    border.width: 1

    // Inner subtle glow border
    Rectangle {
        anchors.fill: parent
        anchors.margins: -1
        radius: parent.radius + 1
        color: "transparent"
        border.color: (typeof Colors !== "undefined" && Colors.primary) ? Qt.alpha(Colors.primary, 0.15) : Qt.rgba(0.8, 0.7, 1.0, 0.15)
        border.width: 1
        z: -1
    }

    Column {
        id: contentLayout
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 8
        spacing: 4
    }
}
