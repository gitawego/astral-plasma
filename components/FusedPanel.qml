import QtQuick
import "../theme"

Item {
    id: root

    property string attachEdge: "top" // "top", "topRight", "bottomLeft"
    property real panelWidth: 400
    property real panelHeight: 300
    property real borderThickness: (typeof Config !== "undefined" && Config.borderThickness) ? Config.borderThickness : 14
    property real borderRounding: (typeof Config !== "undefined" && Config.borderRounding) ? Config.borderRounding : 20
    property color fillColor: (typeof Colors !== "undefined" && Colors.surface) ? Colors.surface : "#141318"
    property bool isOpen: false

    property real offsetProgress: isOpen ? 1.0 : 0.0

    readonly property alias card: cardRectangle
    readonly property alias fillet1: filletItem1
    readonly property alias fillet2: filletItem2
    default property alias content: cardContent.data

    width: panelWidth
    height: panelHeight
    visible: offsetProgress > 0.01

    Behavior on offsetProgress {
        NumberAnimation {
            duration: (typeof Theme !== "undefined" && Theme.animExpressiveDefaultSpatial) ? Theme.animExpressiveDefaultSpatial : 500
            easing.type: Easing.BezierSpline
            easing.bezierCurve: (typeof Theme !== "undefined" && Theme.curveExpressiveDefaultSpatial) ? Theme.curveExpressiveDefaultSpatial : [0.38, 1.21, 0.22, 1.0, 1.0, 1.0]
        }
    }

    transform: Translate {
        y: {
            if (root.attachEdge === "top" || root.attachEdge === "topRight") {
                return -root.panelHeight * (1.0 - root.offsetProgress);
            } else if (root.attachEdge === "bottomLeft") {
                return root.panelHeight * (1.0 - root.offsetProgress);
            }
            return 0;
        }
    }

    // Inverted Fillet 1 (Top-Left junction with Top Border)
    CornerFillet {
        id: filletItem1
        visible: root.offsetProgress > 0.05
        cornerRadius: root.borderRounding
        fillColor: root.fillColor
        strokeColor: "transparent"
        z: 1

        x: -root.borderRounding
        y: root.borderThickness
        orientation: "dropdownLeft"
    }

    // Inverted Fillet 2 (Right junction)
    CornerFillet {
        id: filletItem2
        visible: root.offsetProgress > 0.05
        cornerRadius: root.borderRounding
        fillColor: root.fillColor
        strokeColor: "transparent"
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
                return root.panelHeight;
            }
            return root.borderThickness;
        }
        orientation: root.attachEdge === "topRight" ? "topRight" : "dropdownRight"
    }

    // Main Fused Card Surface
    Rectangle {
        id: cardRectangle
        x: 0
        y: 0
        width: root.panelWidth
        height: root.panelHeight
        color: root.fillColor

        // Flush at fused screen boundaries, rounded on free interior sides
        topLeftRadius: 0
        topRightRadius: 0
        bottomLeftRadius: root.borderRounding
        bottomRightRadius: (root.attachEdge === "topRight") ? 0 : root.borderRounding

        border.width: 0

        Item {
            id: cardContent
            anchors.fill: parent
        }
    }
}
