import QtQuick
import "../theme"

Item {
    id: root

    property real value: 0.0 // 0.0 to 1.0
    property string iconText: ""
    property string nerdGlyph: ""
    property color fillColor: Colors.primary
    property color trackColor: (typeof Colors !== "undefined" && Colors.onSurface)
        ? Qt.alpha(Colors.onSurface, 0.08)
        : Qt.rgba(1, 1, 1, 0.08)
    property string tooltipText: ""
    property int barWidth: 12

    readonly property alias trackRectItem: trackRect
    readonly property alias fillPillItem: fillPill
    readonly property alias iconLabelItem: iconLabel

    implicitWidth: root.barWidth
    implicitHeight: 130
    width: root.barWidth

    Column {
        anchors.fill: parent
        spacing: 6

        // Vertical Pill Track
        Rectangle {
            id: trackRect
            width: root.barWidth
            height: Math.max(10, root.height - iconLabel.height - 6)
            anchors.horizontalCenter: parent.horizontalCenter
            radius: (typeof Theme !== "undefined" && Theme.material && Theme.material.surfaceStyle === "neon_cyber") ? 0 : width / 2
            color: root.trackColor
            clip: true

            border.width: 1
            border.color: (typeof Colors !== "undefined" && Colors.outlineVariant)
                ? Qt.alpha(Colors.outlineVariant, 0.20)
                : Qt.rgba(1, 1, 1, 0.12)

            // Dynamic Fill Pill
            Rectangle {
                id: fillPill
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: root.value > 0.005 ? Math.max(width, parent.height * Math.min(1.0, root.value)) : 0
                visible: height > 0
                radius: (typeof Theme !== "undefined" && Theme.material && Theme.material.surfaceStyle === "neon_cyber") ? 0 : width / 2
                color: root.fillColor

                Behavior on height {
                    NumberAnimation {
                        duration: (typeof Theme !== "undefined") ? Theme.animExpressiveFastSpatial : 350
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: (typeof Theme !== "undefined") ? Theme.curveExpressiveFastSpatial : [0.42, 1.67, 0.21, 0.9, 1.0, 1.0]
                    }
                }

                Behavior on color {
                    ColorAnimation {
                        duration: (typeof Theme !== "undefined") ? Theme.animExpressiveFastEffects : 150
                    }
                }
            }
        }

        // Hardware Resource Icon underneath
        Item {
            id: iconLabel
            width: parent.width
            height: 18
            anchors.horizontalCenter: parent.horizontalCenter

            MaterialIcon {
                anchors.centerIn: parent
                text: root.iconText !== "" ? root.iconText : root.nerdGlyph
                size: 15
                color: (typeof Colors !== "undefined" && Colors.onSurfaceVariant) ? Colors.onSurfaceVariant : "#A0A0A0"
            }
        }
    }
}
