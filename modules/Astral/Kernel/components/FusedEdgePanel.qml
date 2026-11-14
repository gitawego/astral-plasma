import QtQuick
import QtQuick.Shapes
import "../theme"
import "../config"

// FusedEdgePanel is the shared geometry for panels that are welded to a screen
// edge (the top border today, the top-right notification corner, and the dock
// edges). It is geometry only: the caller owns offsetProgress and its motion.
//
// motion: "grow"      the envelope grows from the edge (the existing behavior)
//         "slideBody" the top strip + shoulders stay welded and only the body
//                     (and its clipped content) slides in from above.
//
// bodyInset keeps the body inside a wider panel when the shoulder fillets live
// inside the panel bounds instead of outside it (the central dashboard uses
// bodyInset = shoulder radius; notifications use 0).
Item {
    id: root

    property string attachEdge: "top" // "top", "topRight", "bottomLeft", "left"
    property alias edge: root.attachEdge
    property real panelWidth: 400
    property real panelHeight: 300
    /// Space between the panel's outer edge and the body on each side.
    property real bodyInset: 0
    property real borderThickness: (typeof Config !== "undefined" && Config.borderThickness) ? Config.borderThickness : 14
    property real borderRounding: (typeof Config !== "undefined" && Config.borderRounding) ? Config.borderRounding : 20
    property real bodyRounding: root.borderRounding
    property color fillColor: (typeof Colors !== "undefined" && Colors.glassSurface) ? Colors.glassSurface : Qt.rgba(0.08, 0.07, 0.10, 1.0)
    property color borderColor: (typeof Colors !== "undefined" && Colors.glassBorderSpecular) ? Colors.glassBorderSpecular : Qt.rgba(1, 1, 1, 0.12)
    property real strokeWidth: 1
    property bool isOpen: false
    property real offsetProgress: isOpen ? 1.0 : 0.0
    /// "grow" (envelope morph) or "slideBody" (static header, sliding body).
    property string motion: "grow"

    readonly property bool slideBodyMotion: motion === "slideBody" && attachEdge === "top"
    readonly property real bodyWidth: Math.max(0, panelWidth - bodyInset * 2)
    readonly property real bodyHeight: Math.max(0, panelHeight - borderThickness)
    /// Slide progress clamped to [0, 1]: the expressive bezier overshoots, and
    /// a body offset past its resting position would detach from the header.
    readonly property real slideProgress: Math.max(0.0, Math.min(1.0, offsetProgress))
    readonly property real bodyOffset: slideBodyMotion ? -(bodyHeight * (1.0 - slideProgress)) : 0
    readonly property real visibleBodyHeight: slideBodyMotion
        ? Math.max(0, bodyHeight + bodyOffset)
        : Math.max(0, currentEnvelopeHeight - borderThickness)

    // Dynamic morphing envelope dimensions for the grow choreography.
    readonly property real currentEnvelopeHeight: {
        if (root.slideBodyMotion) return root.panelHeight;
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
        if (root.slideBodyMotion) return 1.0;
        if (root.attachEdge === "top" || root.attachEdge === "topRight") {
            return Math.max(0.0, Math.min(1.0, (root.currentEnvelopeHeight - root.borderThickness) / Math.max(1, root.borderRounding)));
        }
        return Math.max(0.0, Math.min(1.0, root.offsetProgress));
    }

    /// Blur footprint readouts, in panel-local coordinates. The shell composes
    /// these with the panel's position; it must never re-derive the shape.
    readonly property rect headerBlurRect: Qt.rect(0, 0, panelWidth, borderThickness + borderRounding)
    readonly property rect bodyBlurRect: Qt.rect(bodyInset, borderThickness, bodyWidth, visibleBodyHeight)

    readonly property alias card: cardRectangle
    readonly property alias fillet1: filletItem1
    readonly property alias fillet2: filletItem2
    readonly property alias bodyItem: bodyRect
    readonly property alias bodyClipItem: bodyClip
    readonly property alias contentHostItem: contentHost
    readonly property alias headerItem: headerStrip
    default property alias content: contentHost.data

    width: panelWidth
    height: panelHeight
    visible: offsetProgress > 0.001

    // ---------------------------------------------------------------------
    // Grow geometry (existing behavior). The fillets stay welded to the edge;
    // the card envelope grows under them.
    // ---------------------------------------------------------------------
    CornerFillet {
        id: filletItem1
        visible: !root.slideBodyMotion && root.filletFactor > 0.01
        opacity: root.filletFactor
        cornerRadius: root.borderRounding
        fillColor: root.fillColor
        strokeColor: root.strokeWidth > 0 ? root.borderColor : "transparent"
        strokeWidth: root.strokeWidth
        z: 1

        x: root.bodyInset - root.borderRounding
        y: root.borderThickness
        orientation: "dropdownLeft"
    }

    CornerFillet {
        id: filletItem2
        visible: !root.slideBodyMotion && root.filletFactor > 0.01
        opacity: root.filletFactor
        cornerRadius: root.borderRounding
        fillColor: root.fillColor
        strokeColor: root.strokeWidth > 0 ? root.borderColor : "transparent"
        strokeWidth: root.strokeWidth
        z: 1

        x: {
            if (root.attachEdge === "top") {
                return root.bodyInset + root.bodyWidth;
            } else if (root.attachEdge === "topRight") {
                return root.bodyInset + (root.bodyWidth - root.borderThickness) - root.borderRounding;
            }
            return root.bodyInset + root.bodyWidth;
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

    // Dedicated outline stroke for the topRight fused panel.
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        visible: !root.slideBodyMotion && root.attachEdge === "topRight" && root.filletFactor > 0.01 && root.strokeWidth > 0
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
                x: Math.max(root.borderRounding, (root.bodyWidth - root.borderThickness) - root.borderRounding)
                y: root.currentEnvelopeHeight
            }
        }
    }

    Rectangle {
        id: cardRectangle
        visible: !root.slideBodyMotion
        x: root.bodyInset
        y: 0
        width: root.bodyWidth
        height: root.currentEnvelopeHeight
        color: root.fillColor

        topLeftRadius: 0
        topRightRadius: 0
        bottomLeftRadius: root.bodyRounding
        bottomRightRadius: (root.attachEdge === "topRight") ? 0 : root.bodyRounding

        border.width: 0
        clip: true
    }

    // ---------------------------------------------------------------------
    // slideBody geometry: the top strip + shoulder fillets stay welded; the
    // body and its content are clipped to the space below the top border and
    // slide in from above.
    // ---------------------------------------------------------------------
    Item {
        id: bodyClip
        visible: root.slideBodyMotion
        x: root.bodyInset
        y: root.borderThickness
        width: root.bodyWidth
        height: root.bodyHeight
        clip: true

        Rectangle {
            id: bodyRect
            x: 0
            y: root.bodyOffset
            width: root.bodyWidth
            height: root.bodyHeight
            color: root.fillColor
            topLeftRadius: 0
            topRightRadius: 0
            bottomLeftRadius: root.bodyRounding
            bottomRightRadius: root.bodyRounding
            border.width: 0
        }

        // Side + bottom stroke only: the top edge is welded under the header
        // strip and must not draw a line across the body.
        Shape {
            x: 0
            y: root.bodyOffset
            width: root.bodyWidth
            height: root.bodyHeight
            visible: root.strokeWidth > 0
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                fillColor: "transparent"
                strokeColor: root.borderColor
                strokeWidth: root.strokeWidth
                capStyle: ShapePath.FlatCap

                startX: 0.5
                startY: root.bodyRounding
                PathLine {
                    x: 0.5
                    y: Math.max(root.bodyRounding, root.bodyHeight - root.bodyRounding)
                }
                PathArc {
                    x: root.bodyRounding
                    y: root.bodyHeight - 0.5
                    radiusX: Math.max(0.1, root.bodyRounding - 0.5)
                    radiusY: Math.max(0.1, root.bodyRounding - 0.5)
                    direction: PathArc.Counterclockwise
                }
                PathLine {
                    x: Math.max(root.bodyRounding, root.bodyWidth - root.bodyRounding)
                    y: root.bodyHeight - 0.5
                }
                PathArc {
                    x: root.bodyWidth - 0.5
                    y: Math.max(root.bodyRounding, root.bodyHeight - root.bodyRounding)
                    radiusX: Math.max(0.1, root.bodyRounding - 0.5)
                    radiusY: Math.max(0.1, root.bodyRounding - 0.5)
                    direction: PathArc.Counterclockwise
                }
                PathLine {
                    x: root.bodyWidth - 0.5
                    y: root.bodyRounding
                }
            }
        }
    }

    // Welded header: top strip + the two shoulder fillets. Static by design.
    Rectangle {
        id: headerStrip
        visible: root.slideBodyMotion
        x: 0
        y: 0
        width: root.panelWidth
        height: root.borderThickness
        color: root.fillColor
        z: 2
    }

    CornerFillet {
        id: slideFillet1
        visible: root.slideBodyMotion
        x: root.bodyInset - root.borderRounding
        y: root.borderThickness
        cornerRadius: root.borderRounding
        fillColor: root.fillColor
        strokeColor: root.strokeWidth > 0 ? root.borderColor : "transparent"
        strokeWidth: root.strokeWidth
        orientation: "dropdownLeft"
        z: 3
    }

    CornerFillet {
        id: slideFillet2
        visible: root.slideBodyMotion
        x: root.bodyInset + root.bodyWidth
        y: root.borderThickness
        cornerRadius: root.borderRounding
        fillColor: root.fillColor
        strokeColor: root.strokeWidth > 0 ? root.borderColor : "transparent"
        strokeWidth: root.strokeWidth
        orientation: "dropdownRight"
        z: 3
    }

    // Content lives in one host so callers keep the same default `content`
    // slot in both choreographies; placeContent reparents it, never duplicates.
    Item {
        id: contentHost
        visible: false
    }

    function placeContent() {
        if (root.slideBodyMotion) {
            contentHost.parent = bodyClip;
            contentHost.x = 0;
            contentHost.y = Qt.binding(function () { return root.bodyOffset; });
            contentHost.width = root.bodyWidth;
            contentHost.height = root.bodyHeight;
        } else {
            contentHost.parent = cardRectangle;
            contentHost.x = 0;
            contentHost.y = Qt.binding(function () {
                return Math.min(0, root.currentEnvelopeHeight - root.panelHeight);
            });
            contentHost.width = root.bodyWidth;
            contentHost.height = root.panelHeight;
        }
        contentHost.visible = true;
    }

    Component.onCompleted: placeContent()
    onSlideBodyMotionChanged: placeContent()
}
