import QtQuick
import QtQuick.Shapes
import "../theme"

Rectangle {
    id: root

    default property alias content: contentLayout.data
    property alias spacing: contentLayout.spacing

    implicitWidth: 260
    implicitHeight: contentLayout.implicitHeight + 16

    // Fused cleanly against the dock on the left: strictly flush
    readonly property real cardRadius: (typeof Theme !== "undefined" && Theme.radiusGlassCard) ? Theme.radiusGlassCard : 20
    radius: root.cardRadius
    topLeftRadius: 0
    bottomLeftRadius: 0
    topRightRadius: root.cardRadius
    bottomRightRadius: root.cardRadius

    color: (typeof Colors !== "undefined" && Colors.glassSurface) ? Colors.glassSurface : Qt.rgba(0.08, 0.07, 0.10, 1.0)
    border.width: 0

    // Perimeter stroke for top, right, bottom (left edge seamlessly fused with dock)
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor: "transparent"
            strokeColor: (typeof Colors !== "undefined" && Colors.glassBorderSpecular) ? Colors.glassBorderSpecular : Qt.rgba(1, 1, 1, 0.12)
            strokeWidth: 1
            capStyle: ShapePath.FlatCap

            startX: 0
            startY: 0
            PathLine { x: Math.max(0, root.width - root.topRightRadius); y: 0 }
            PathArc { x: root.width; y: root.topRightRadius; radiusX: root.topRightRadius; radiusY: root.topRightRadius; direction: PathArc.Clockwise }
            PathLine { x: root.width; y: Math.max(root.topRightRadius, root.height - root.bottomRightRadius) }
            PathArc { x: Math.max(0, root.width - root.bottomRightRadius); y: root.height; radiusX: root.bottomRightRadius; radiusY: root.bottomRightRadius; direction: PathArc.Clockwise }
            PathLine { x: 0; y: root.height }
        }
    }

    // Top specular highlight line
    Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.rightMargin: root.topRightRadius * 0.4
        height: 1
        color: (typeof Colors !== "undefined" && Colors.glassBorderSpecular) ? Colors.glassBorderSpecular : Qt.rgba(1, 1, 1, 0.12)
        opacity: 0.45
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
