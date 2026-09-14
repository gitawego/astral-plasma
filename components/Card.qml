import QtQuick
import "../theme"

Rectangle {
    id: root

    property alias content: root.children
    property int padding: Theme.padMedium

    radius: Theme.radiusLarge
    color: Colors.cardBackground
    border.color: Theme.borderSubtle
    border.width: 1

    Behavior on color {
        ColorAnimation { duration: Theme.animDurationNormal }
    }
}
