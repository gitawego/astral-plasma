import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import "../theme"
import "../config"
import "../components"
import "../services"

Item {
    id: root
    anchors.fill: parent

    required property real dockW
    required property real borderT
    required property real filletR
    required property color borderColor

    // Central dropdown geometry
    required property real dropX
    required property real dropW
    required property real currentDropH
    required property real dropdownOffsetProgress

    // Bottom popout geometry
    required property real currentPopW
    required property real popoutY
    required property real popoutHeight
    required property real popoutOffsetProgress
    required property real fusedProgress

    // Right edge control geometry
    property real rightControlW: 60
    property real rightControlH: 280
    property real rightControlY: Math.round((root.height - rightControlH) / 2)
    property real rightControlOffsetProgress: 0.0

    readonly property color glassFill: (typeof Colors !== "undefined" && Colors.glassSurface) ? Colors.glassSurface : Qt.rgba(0.06, 0.08, 0.12, 0.70)
    readonly property color glassBorder: (typeof Colors !== "undefined" && Colors.glassBorderSpecular) ? Colors.glassBorderSpecular : Qt.rgba(1, 1, 1, 0.12)
    readonly property real modalRadius: root.filletR
    readonly property bool hasMaximizedWindow: (typeof WindowService !== "undefined" && WindowService && (WindowService.hasMaximizedWindow || WindowService.hasActiveMaximized)) ? true : false
    readonly property real cornerFilletR: root.filletR

    // layer.enabled disabled

    readonly property alias topBorderLeftItem: topBorderLeft
    readonly property alias topBorderRightItem: topBorderRight
    readonly property alias rightBorderItem: rightBorder
    readonly property alias bottomBorderItem: bottomBorder
    readonly property alias dashSurfaceWrapperItem: dashSurfaceWrapper
    readonly property alias innerFilletTLItem: innerFilletTL
    readonly property alias innerFilletTRItem: innerFilletTR
    readonly property alias innerFilletBLItem: innerFilletBL
    readonly property alias innerFilletBRItem: innerFilletBR

    // Left Dock Surface
    Rectangle {
        id: dockBg
        visible: (typeof Config !== "undefined" && Config.dockEnabled !== undefined) ? Config.dockEnabled : true
        x: 0
        y: 0
        width: root.dockW
        height: root.height
        color: root.glassFill

        Rectangle {
            x: parent.width - 1
            y: root.borderT + root.cornerFilletR
            width: 1
            height: Math.max(0, parent.height - root.borderT * 2 - root.cornerFilletR * 2)
            color: root.borderColor
        }
    }

    property real notifHeight: 74

    readonly property bool hasNotification: (typeof NotificationService !== "undefined" && NotificationService && NotificationService.hasNotification) ? true : false
    readonly property real topBorderRightLimit: root.hasNotification
        ? (root.width - 380 - root.filletR)
        : (root.width - root.borderT - root.cornerFilletR)
    readonly property real topBorderRightCap: root.hasNotification
        ? (root.width - 380)
        : (root.width - root.borderT)

    // Thin Top Border (Segmented between dockW and width - borderT, avoiding double-translucency overlap)
    Rectangle {
        id: topBorderLeft
        x: root.dockW
        y: 0
        width: Math.max(0, (root.dropdownOffsetProgress > 0.001 ? (root.dropX - root.filletR) : root.topBorderRightCap) - root.dockW)
        height: root.borderT
        color: root.glassFill

        // Segment left of dropdown
        Rectangle {
            x: root.cornerFilletR
            y: parent.height - 1
            height: 1
            width: root.dropdownOffsetProgress > 0.001 
                ? Math.max(0, parent.width - x)
                : Math.max(0, root.topBorderRightLimit - root.dockW - root.cornerFilletR)
            color: root.borderColor
        }
    }

    Rectangle {
        id: topBorderRight
        visible: root.dropdownOffsetProgress > 0.001
        x: root.dropX + root.dropW + root.filletR
        y: 0
        width: Math.max(0, root.topBorderRightCap - x)
        height: root.borderT
        color: root.glassFill

        // Segment right of dropdown
        Rectangle {
            x: 0
            y: parent.height - 1
            height: 1
            width: Math.max(0, root.topBorderRightLimit - parent.x)
            color: root.borderColor
        }
    }

    readonly property real rightBorderTopLimit: root.hasNotification
        ? (root.notifHeight + root.filletR)
        : (root.borderT + root.cornerFilletR - 1)
    readonly property real rightBorderBottomLimit: root.height - (root.borderT + root.cornerFilletR - 1)

    readonly property real rightControlGapTop: root.rightControlY - root.filletR * root.rightControlOffsetProgress
    readonly property real rightControlGapBottom: root.rightControlY + root.rightControlH + root.filletR * root.rightControlOffsetProgress

    // Thin Right Border
    Rectangle {
        id: rightBorder
        x: root.width - root.borderT
        y: root.hasNotification ? root.notifHeight : 0
        width: root.borderT
        height: Math.max(0, root.height - y)
        color: root.glassFill

        // Upper segment
        Rectangle {
            x: 0
            y: Math.max(0, root.rightBorderTopLimit - parent.y)
            width: 1
            height: root.rightControlOffsetProgress > 0.001
                ? Math.max(0, (root.rightControlGapTop - parent.y) - y)
                : Math.max(0, (root.rightBorderBottomLimit - parent.y) - y)
            color: root.borderColor
        }

        // Lower segment (active when right edge control is open)
        Rectangle {
            visible: root.rightControlOffsetProgress > 0.001
            x: 0
            y: Math.max(0, root.rightControlGapBottom - parent.y)
            width: 1
            height: Math.max(0, (root.rightBorderBottomLimit - parent.y) - y)
            color: root.borderColor
        }
    }

    // Thin Bottom Border (Partitioned between dockW and width - borderT)
    Rectangle {
        id: bottomBorder
        x: root.dockW
        y: root.height - root.borderT
        width: Math.max(0, (root.width - root.borderT) - root.dockW)
        height: root.borderT
        color: root.glassFill

        Rectangle {
            x: (root.popoutOffsetProgress > 0.001
                ? (root.currentPopW * root.fusedProgress)
                : root.cornerFilletR)
            y: 0
            height: 1
            width: Math.max(0, parent.width - x - root.cornerFilletR)
            color: root.borderColor
        }
    }

    // Inner Fillet: Top-Left
    CornerFillet {
        id: innerFilletTL
        visible: root.cornerFilletR > 1
        x: root.dockW
        y: root.borderT
        width: root.cornerFilletR
        height: root.cornerFilletR
        orientation: "topLeft"
        cornerRadius: root.cornerFilletR
        fillColor: root.glassFill
        strokeColor: root.borderColor
        strokeWidth: 1
    }

    // Inner Fillet: Top-Right
    CornerFillet {
        id: innerFilletTR
        visible: !root.hasNotification && root.cornerFilletR > 1
        x: root.width - root.borderT - root.cornerFilletR
        y: root.borderT
        width: root.cornerFilletR
        height: root.cornerFilletR
        orientation: "topRight"
        cornerRadius: root.cornerFilletR
        fillColor: root.glassFill
        strokeColor: root.borderColor
        strokeWidth: 1
    }

    // Inner Fillet: Bottom-Left
    CornerFillet {
        id: innerFilletBL
        visible: root.cornerFilletR > 1 && (1.0 - (root.fusedProgress * root.popoutOffsetProgress)) > 0.01
        opacity: 1.0 - (root.fusedProgress * root.popoutOffsetProgress)
        x: root.dockW
        y: root.height - root.borderT - root.cornerFilletR
        width: root.cornerFilletR
        height: root.cornerFilletR
        orientation: "bottomLeft"
        cornerRadius: root.cornerFilletR
        fillColor: root.glassFill
        strokeColor: root.borderColor
        strokeWidth: 1
    }

    // Inner Fillet: Bottom-Right
    CornerFillet {
        id: innerFilletBR
        visible: root.cornerFilletR > 1
        x: root.width - root.borderT - root.cornerFilletR
        y: root.height - root.borderT - root.cornerFilletR
        width: root.cornerFilletR
        height: root.cornerFilletR
        orientation: "bottomRight"
        cornerRadius: root.cornerFilletR
        fillColor: root.glassFill
        strokeColor: root.borderColor
        strokeWidth: 1
    }

    // Central Dashboard Fused Solid Surface & Fillets
    Item {
        id: dashSurfaceWrapper
        x: root.dropX - root.filletR
        y: 0
        width: root.dropW + root.filletR * 2
        height: Math.max(root.borderT, root.currentDropH)
        visible: root.dropdownOffsetProgress > 0.001

        readonly property real extH: Math.max(0, root.currentDropH - root.borderT)
        readonly property real maxRadiusSum: root.filletR + root.modalRadius
        readonly property real k: Math.min(1.0, extH / Math.max(1, maxRadiusSum))
        readonly property real currentFilletR: root.filletR * k
        readonly property real currentModalR: root.modalRadius * k

        // 1. Unified Glass Surface Fill Shape (Top bar strip, dropdown body, and both shoulder fillets)
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                fillColor: root.glassFill
                strokeColor: "transparent"
                strokeWidth: 0

                startX: 0; startY: 0
                PathLine { x: dashSurfaceWrapper.width; y: 0 }
                PathLine { x: dashSurfaceWrapper.width; y: root.borderT }

                // Right shoulder: from right top border down to dropdown body
                PathLine {
                    x: dashSurfaceWrapper.width - (root.filletR - dashSurfaceWrapper.currentFilletR)
                    y: root.borderT
                }
                PathArc {
                    x: dashSurfaceWrapper.width - root.filletR
                    y: root.borderT + dashSurfaceWrapper.currentFilletR
                    radiusX: Math.max(0.1, dashSurfaceWrapper.currentFilletR)
                    radiusY: Math.max(0.1, dashSurfaceWrapper.currentFilletR)
                    direction: PathArc.Counterclockwise
                }
                // Right vertical edge
                PathLine {
                    x: dashSurfaceWrapper.width - root.filletR
                    y: Math.max(root.borderT + dashSurfaceWrapper.currentFilletR, root.currentDropH - dashSurfaceWrapper.currentModalR)
                }
                // Bottom-right corner
                PathArc {
                    x: dashSurfaceWrapper.width - root.filletR - dashSurfaceWrapper.currentModalR
                    y: Math.max(root.borderT, root.currentDropH)
                    radiusX: Math.max(0.1, dashSurfaceWrapper.currentModalR)
                    radiusY: Math.max(0.1, dashSurfaceWrapper.currentModalR)
                    direction: PathArc.Clockwise
                }
                // Bottom edge
                PathLine {
                    x: root.filletR + dashSurfaceWrapper.currentModalR
                    y: Math.max(root.borderT, root.currentDropH)
                }
                // Bottom-left corner
                PathArc {
                    x: root.filletR
                    y: Math.max(root.borderT + dashSurfaceWrapper.currentFilletR, root.currentDropH - dashSurfaceWrapper.currentModalR)
                    radiusX: Math.max(0.1, dashSurfaceWrapper.currentModalR)
                    radiusY: Math.max(0.1, dashSurfaceWrapper.currentModalR)
                    direction: PathArc.Clockwise
                }
                // Left vertical edge
                PathLine {
                    x: root.filletR
                    y: root.borderT + dashSurfaceWrapper.currentFilletR
                }
                // Left shoulder
                PathArc {
                    x: root.filletR - dashSurfaceWrapper.currentFilletR
                    y: root.borderT
                    radiusX: Math.max(0.1, dashSurfaceWrapper.currentFilletR)
                    radiusY: Math.max(0.1, dashSurfaceWrapper.currentFilletR)
                    direction: PathArc.Counterclockwise
                }
                PathLine { x: 0; y: root.borderT }
                PathLine { x: 0; y: 0 }
            }
        }

        // 2a. Flat Horizontal 1px Stroke Shape when drawer is retracted into the top bar (extH < 1)
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            visible: dashSurfaceWrapper.extH < 1

            ShapePath {
                fillColor: "transparent"
                strokeColor: root.borderColor
                strokeWidth: 1
                capStyle: ShapePath.FlatCap

                startX: 0; startY: root.borderT - 0.5
                PathLine { x: dashSurfaceWrapper.width; y: root.borderT - 0.5 }
            }
        }

        // 2b. Continuous Inset 1px Perimeter Stroke Shape when drawer is expanding (extH >= 1)
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            visible: dashSurfaceWrapper.extH >= 1

            ShapePath {
                fillColor: "transparent"
                strokeColor: root.borderColor
                strokeWidth: 1
                capStyle: ShapePath.FlatCap

                startX: 0; startY: root.borderT - 0.5
                PathLine {
                    x: Math.max(0, root.filletR - dashSurfaceWrapper.currentFilletR)
                    y: root.borderT - 0.5
                }
                PathArc {
                    x: root.filletR + 0.5
                    y: root.borderT + dashSurfaceWrapper.currentFilletR
                    radiusX: Math.max(0.1, dashSurfaceWrapper.currentFilletR + 0.5)
                    radiusY: Math.max(0.1, dashSurfaceWrapper.currentFilletR + 0.5)
                    direction: PathArc.Clockwise
                }
                PathLine {
                    x: root.filletR + 0.5
                    y: Math.max(root.borderT + dashSurfaceWrapper.currentFilletR, root.currentDropH - dashSurfaceWrapper.currentModalR)
                }
                PathArc {
                    x: root.filletR + dashSurfaceWrapper.currentModalR
                    y: Math.max(root.borderT - 0.5, root.currentDropH - 0.5)
                    radiusX: Math.max(0.1, dashSurfaceWrapper.currentModalR - 0.5)
                    radiusY: Math.max(0.1, dashSurfaceWrapper.currentModalR - 0.5)
                    direction: PathArc.Counterclockwise
                }
                PathLine {
                    x: Math.max(root.filletR + dashSurfaceWrapper.currentModalR, dashSurfaceWrapper.width - root.filletR - dashSurfaceWrapper.currentModalR)
                    y: Math.max(root.borderT - 0.5, root.currentDropH - 0.5)
                }
                PathArc {
                    x: dashSurfaceWrapper.width - root.filletR - 0.5
                    y: Math.max(root.borderT + dashSurfaceWrapper.currentFilletR, root.currentDropH - dashSurfaceWrapper.currentModalR)
                    radiusX: Math.max(0.1, dashSurfaceWrapper.currentModalR - 0.5)
                    radiusY: Math.max(0.1, dashSurfaceWrapper.currentModalR - 0.5)
                    direction: PathArc.Counterclockwise
                }
                PathLine {
                    x: dashSurfaceWrapper.width - root.filletR - 0.5
                    y: root.borderT + dashSurfaceWrapper.currentFilletR
                }
                PathArc {
                    x: dashSurfaceWrapper.width - (root.filletR - dashSurfaceWrapper.currentFilletR)
                    y: root.borderT - 0.5
                    radiusX: Math.max(0.1, dashSurfaceWrapper.currentFilletR + 0.5)
                    radiusY: Math.max(0.1, dashSurfaceWrapper.currentFilletR + 0.5)
                    direction: PathArc.Clockwise
                }
                PathLine {
                    x: dashSurfaceWrapper.width
                    y: root.borderT - 0.5
                }
            }
        }
    }

    // Bottom Popout Solid Surface (Floating or Bottom-Fused Drawer)
    Item {
        id: bottomPopoutSurface
        x: root.dockW - 1
        y: root.popoutY
        width: root.currentPopW + 1
        height: root.popoutHeight
        visible: root.popoutOffsetProgress > 0.001

        readonly property real filletFactor: Math.max(0.0, Math.min(1.0, root.currentPopW / Math.max(1, root.filletR)))
        readonly property real effectiveR: (root.fusedProgress > 0.5) ? 0 : root.modalRadius

        // 1. Solid Glass Surface Fill
        Rectangle {
            anchors.fill: parent
            color: root.glassFill
            opacity: bottomPopoutSurface.filletFactor
            topLeftRadius: 0
            bottomLeftRadius: 0
            topRightRadius: root.modalRadius
            bottomRightRadius: bottomPopoutSurface.effectiveR

            // Subtle top specular highlight catch
            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.rightMargin: parent.topRightRadius * 0.4
                height: 1
                color: root.glassBorder
                opacity: 0.45
            }
        }

        // 2. Continuous 1px Border Outline (Top, Right, Bottom; Left edge is fused to dock)
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            visible: bottomPopoutSurface.filletFactor > 0.01
            opacity: bottomPopoutSurface.filletFactor

            ShapePath {
                fillColor: "transparent"
                strokeColor: root.borderColor
                strokeWidth: 1
                capStyle: ShapePath.FlatCap

                startX: 0; startY: 0
                PathLine { x: Math.max(0, bottomPopoutSurface.width - root.modalRadius); y: 0 }
                PathArc {
                    x: bottomPopoutSurface.width
                    y: root.modalRadius
                    radiusX: root.modalRadius
                    radiusY: root.modalRadius
                    direction: PathArc.Clockwise
                }
                PathLine { x: bottomPopoutSurface.width; y: Math.max(root.modalRadius, bottomPopoutSurface.height - bottomPopoutSurface.effectiveR) }
                PathArc {
                    x: Math.max(0, bottomPopoutSurface.width - bottomPopoutSurface.effectiveR)
                    y: bottomPopoutSurface.height
                    radiusX: bottomPopoutSurface.effectiveR
                    radiusY: bottomPopoutSurface.effectiveR
                    direction: PathArc.Clockwise
                }
                PathLine { x: 0; y: bottomPopoutSurface.height }
            }
        }
    }

    // Right Border Edge Volume/Brightness Control Surface
    Item {
        id: rightControlSurface
        x: root.width - root.borderT - currentW
        y: root.rightControlY
        width: currentW + 1
        height: root.rightControlH
        visible: root.rightControlOffsetProgress > 0.001

        readonly property real currentW: root.rightControlW * root.rightControlOffsetProgress
        readonly property real filletFactor: Math.max(0.0, Math.min(1.0, currentW / Math.max(1, root.filletR)))

        // 1. Solid Glass Surface Fill
        Rectangle {
            anchors.fill: parent
            color: root.glassFill
            opacity: rightControlSurface.filletFactor
            topRightRadius: 0
            bottomRightRadius: 0
            topLeftRadius: root.modalRadius
            bottomLeftRadius: root.modalRadius

            // Subtle top specular highlight catch
            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: parent.topLeftRadius * 0.4
                height: 1
                color: root.glassBorder
                opacity: 0.45
            }
        }

        // 2. Continuous 1px Border Outline (Top, Left, Bottom; Right edge is fused to right border)
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            visible: rightControlSurface.filletFactor > 0.01
            opacity: rightControlSurface.filletFactor

            ShapePath {
                fillColor: "transparent"
                strokeColor: root.borderColor
                strokeWidth: 1
                capStyle: ShapePath.FlatCap

                startX: rightControlSurface.width; startY: 0
                PathLine { x: root.modalRadius; y: 0 }
                PathArc {
                    x: 0
                    y: root.modalRadius
                    radiusX: root.modalRadius
                    radiusY: root.modalRadius
                    direction: PathArc.Counterclockwise
                }
                PathLine { x: 0; y: Math.max(root.modalRadius, rightControlSurface.height - root.modalRadius) }
                PathArc {
                    x: root.modalRadius
                    y: rightControlSurface.height
                    radiusX: root.modalRadius
                    radiusY: root.modalRadius
                    direction: PathArc.Counterclockwise
                }
                PathLine { x: rightControlSurface.width; y: rightControlSurface.height }
            }
        }
    }
}
