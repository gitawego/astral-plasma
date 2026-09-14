import QtQuick
import "../theme"

Item {
    id: root

    property real value: 0.5 // 0.0 to 1.0
    property string iconText: ""
    property color fillColor: Colors.primary
    property color trackColor: Qt.alpha(Colors.outlineVariant, 0.35)
    property bool interactive: false
    signal valueModified(real newValue)

    implicitWidth: 20
    implicitHeight: 120

    Column {
        anchors.fill: parent
        spacing: Theme.spaceSmall

        // Vertical Bar Container
        Rectangle {
            id: barContainer
            width: root.width
            height: root.height - iconItem.height - Theme.spaceSmall
            radius: Theme.radiusFull
            color: root.trackColor
            clip: true

            Rectangle {
                id: fillRect
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: Math.max(width, parent.height * Math.min(1.0, Math.max(0.0, root.value)))
                radius: Theme.radiusFull
                color: root.fillColor

                Behavior on height {
                    NumberAnimation { duration: Theme.animDurationNormal; easing.type: Theme.animEasing }
                }
            }

            MouseArea {
                anchors.fill: parent
                enabled: root.interactive
                hoverEnabled: true
                cursorShape: root.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor

                function updateFromY(mouseY) {
                    const norm = 1.0 - (mouseY / barContainer.height);
                    const clamped = Math.min(1.0, Math.max(0.0, norm));
                    root.valueModified(clamped);
                }

                onPressed: mouse => updateFromY(mouse.y)
                onPositionChanged: mouse => {
                    if (pressed) updateFromY(mouse.y)
                }
            }
        }

        // Icon underneath
        MaterialIcon {
            id: iconItem
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.iconText
            size: 14
            color: Colors.m3onSurfaceVariant
        }
    }
}
