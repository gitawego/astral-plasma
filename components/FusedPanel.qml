import QtQuick
import QtQuick.Shapes
import "../theme"
import "../config"

Item {
    id: root

    property string attachEdge: "top" // "top", "topRight", "bottomLeft", "left"
    property real panelWidth: 400
    property real panelHeight: 300
    property real borderThickness: (typeof Config !== "undefined" && Config.borderThickness) ? Config.borderThickness : 14
    property real borderRounding: (typeof Config !== "undefined" && Config.borderRounding) ? Config.borderRounding : 24
    property color fillColor: (typeof Colors !== "undefined" && Colors.glassSurface) ? Colors.glassSurface : Qt.rgba(0.08, 0.07, 0.10, 0.32)
    property color borderColor: (typeof Colors !== "undefined" && Colors.glassBorderSpecular) ? Colors.glassBorderSpecular : Qt.rgba(1, 1, 1, 0.12)
    property real strokeWidth: 1
    property bool isOpen: false

    property real offsetProgress: isOpen ? 1.0 : 0.0

    // Dynamic morphing envelope dimensions
    readonly property real currentEnvelopeHeight: {
        if (root.attachEdge === "top" || root.attachEdge === "topRight") {
            return root.borderThickness + (root.panelHeight - root.borderThickness) * root.offsetProgress;
        }
        return root.panelHeight;
    }

    readonly property real currentEnvelopeWidth: {
        if (root.attachEdge === "left" || root.attachEdge === "bottomLeft") {
            return root.panelWidth * root.offsetProgress;
        }
        return root.panelWidth;
    }

    readonly property real filletFactor: {
        if (root.attachEdge === "top" || root.attachEdge === "topRight") {
            return Math.max(0.0, Math.min(1.0, (root.currentEnvelopeHeight - root.borderThickness) / Math.max(1, root.borderRounding)));
        }
        return Math.max(0.0, Math.min(1.0, root.offsetProgress));
    }

    readonly property alias card: cardRectangle
    readonly property alias fillet1: filletItem1
    readonly property alias fillet2: filletItem2
    default property alias content: cardContent.data

    width: panelWidth
    height: panelHeight
    visible: offsetProgress > 0.001

    Behavior on offsetProgress {
        NumberAnimation {
            duration: (typeof Theme !== "undefined" && Theme.animExpressiveDefaultSpatial) ? Theme.animExpressiveDefaultSpatial : 500
            easing.type: Easing.BezierSpline
            easing.bezierCurve: (typeof Theme !== "undefined" && Theme.curveExpressiveDefaultSpatial) ? Theme.curveExpressiveDefaultSpatial : [0.38, 1.21, 0.22, 1.0, 1.0, 1.0]
        }
    }

    // Inverted Fillet 1 (Top-Left junction with Top Border or Left Dock)
    CornerFillet {
        id: filletItem1
        visible: root.filletFactor > 0.01
        opacity: root.filletFactor
        cornerRadius: root.borderRounding
        fillColor: root.fillColor
        strokeColor: root.strokeWidth > 0 ? root.borderColor : "transparent"
        strokeWidth: root.strokeWidth
        z: 1

        x: -root.borderRounding
        y: root.borderThickness
        orientation: "dropdownLeft"
    }

    // Inverted Fillet 2 (Right junction or bottom junction)
    CornerFillet {
        id: filletItem2
        visible: root.filletFactor > 0.01
        opacity: root.filletFactor
        cornerRadius: root.borderRounding
        fillColor: root.fillColor
        strokeColor: root.strokeWidth > 0 ? root.borderColor : "transparent"
        strokeWidth: root.strokeWidth
        z: 1

        x: {
            if (root.attachEdge === "top") {
                return root.panelWidth;
            } else if (root.attachEdge === "topRight") {
                return (root.panelWidth - root.borderThickness) - root.borderRounding;
            }
            return root.panelWidth;
        }
        y: {
            if (root.attachEdge === "top") {
                return root.borderThickness;
            } else if (root.attachEdge === "topRight") {
                return root.currentEnvelopeHeight;
            }
            return root.borderThickness;
        }
        orientation: root.attachEdge === "topRight" ? "topRight" : "dropdownRight"
    }

    // Dedicated Outline Stroke for topRight fused panel
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        visible: root.attachEdge === "topRight" && root.filletFactor > 0.01 && root.strokeWidth > 0
        opacity: root.filletFactor
        z: 2

        ShapePath {
            fillColor: "transparent"
            strokeColor: root.borderColor
            strokeWidth: root.strokeWidth
            capStyle: ShapePath.FlatCap

            startX: 0
            startY: root.borderThickness + root.borderRounding
            PathLine {
                x: 0
                y: Math.max(root.borderThickness + root.borderRounding, root.currentEnvelopeHeight - root.borderRounding)
            }
            PathArc {
                x: root.borderRounding
                y: root.currentEnvelopeHeight
                radiusX: root.borderRounding
                radiusY: root.borderRounding
                direction: PathArc.Counterclockwise
            }
            PathLine {
                x: Math.max(root.borderRounding, (root.panelWidth - root.borderThickness) - root.borderRounding)
                y: root.currentEnvelopeHeight
            }
        }
    }

    // Main Fused Card Surface - Permanently anchored to the border, height morphs organically
    Rectangle {
        id: cardRectangle
        x: 0
        y: 0
        width: root.panelWidth
        height: root.currentEnvelopeHeight
        color: root.fillColor

        // Flush at fused screen boundaries, rounded on free interior sides
        topLeftRadius: 0
        topRightRadius: 0
        bottomLeftRadius: root.borderRounding
        bottomRightRadius: (root.attachEdge === "topRight") ? 0 : root.borderRounding

        border.width: 0
        clip: true

        // Content envelope synchronized with the descending/morphing bottom edge
        Item {
            id: cardContent
            x: 0
            y: Math.min(0, root.currentEnvelopeHeight - root.panelHeight)
            width: root.panelWidth
            height: root.panelHeight
        }
    }
}
