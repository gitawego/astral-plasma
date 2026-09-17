import QtQuick
import "../theme"

Rectangle {
    id: root

    property alias content: root.children
    property int padding: Theme.padMedium

    radius: Theme.radiusGlassCard
    color: Colors.glassCard
    border.color: Colors.glassBorderSubtle
    border.width: 1

    Behavior on color {
        ColorAnimation { duration: Theme.animExpressiveFastEffects }
    }

    Behavior on border.color {
        ColorAnimation { duration: Theme.animExpressiveFastEffects }
    }

    // Top specular glare line
    Rectangle {
        anchors.top: parent.top
        anchors.topMargin: 0.5
        anchors.left: parent.left
        anchors.leftMargin: parent.radius * 0.4
        anchors.right: parent.right
        anchors.rightMargin: parent.radius * 0.4
        height: 1
        color: Colors.glassBorderSpecular
        opacity: 0.75
    }
}
