import QtQuick
import "../theme"

Rectangle {
    id: root

    width: parent ? parent.width : 200
    height: 1
    color: (typeof Colors !== "undefined" && Colors.outlineVariant) ? Colors.outlineVariant : "#49454e"
    opacity: 0.6
}
