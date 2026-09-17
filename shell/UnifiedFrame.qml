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

    readonly property color glassFill: (typeof Colors !== "undefined" && Colors.glassSurface) ? Colors.glassSurface : Qt.rgba(0.08, 0.07, 0.10, 0.32)
    readonly property color glassBorder: (typeof Colors !== "undefined" && Colors.glassBorderSpecular) ? Colors.glassBorderSpecular : Qt.rgba(1, 1, 1, 0.12)
    readonly property real modalRadius: (typeof Theme !== "undefined" && Theme.radiusGlassModal) ? Theme.radiusGlassModal : 24
    readonly property real cornerFilletR: (typeof Config !== "undefined" && Config.borderRounding !== undefined) ? Config.borderRounding : 6

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
            y: root.borderT + root.cornerFilletR - 1
            width: 1
            height: Math.max(0, parent.height - 2 * (root.borderT + root.cornerFilletR - 1))
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
        width: Math.max(0, (root.dropdownOffsetProgress > 0.001 ? root.dropX : root.topBorderRightCap) - root.dockW)
        height: root.borderT
        color: root.glassFill

        // Segment left of dropdown
        Rectangle {
            x: root.cornerFilletR - 1
            y: parent.height - 1
            height: 1
            width: root.dropdownOffsetProgress > 0.001 
                ? Math.max(0, root.dropX - root.dockW - root.filletR - (root.cornerFilletR - 1))
                : Math.max(0, root.topBorderRightLimit - root.dockW - (root.cornerFilletR - 1))
            color: root.borderColor
        }
    }

    Rectangle {
        id: topBorderRight
        visible: root.dropdownOffsetProgress > 0.001
        x: root.dropX + root.dropW
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
                ? (root.filletR + root.currentPopW * root.fusedProgress)
                : (root.cornerFilletR - 1))
            y: 0
            height: 1
            width: Math.max(0, parent.width - x - root.cornerFilletR)
            color: root.borderColor
        }
    }

    // Inner Fillet: Top-Left
    CornerFillet {
        id: innerFilletTL
        visible: true
        x: root.dockW - 1
        y: root.borderT - 1
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
        visible: !root.hasNotification
        x: root.width - root.borderT - root.cornerFilletR
        y: root.borderT - 1
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
        visible: (1.0 - (root.fusedProgress * root.popoutOffsetProgress)) > 0.01
        opacity: 1.0 - (root.fusedProgress * root.popoutOffsetProgress)
        x: root.dockW - 1
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
        visible: true
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
        x: root.dropX
        y: 0
        width: root.dropW
        height: root.currentDropH
        visible: root.dropdownOffsetProgress > 0.001

        readonly property real filletFactor: Math.max(0.0, Math.min(1.0, (root.currentDropH - root.borderT) / Math.max(1, root.filletR)))

        CornerFillet {
            x: -root.filletR
            y: root.borderT
            orientation: "dropdownLeft"
            cornerRadius: root.filletR
            fillColor: root.glassFill
            strokeColor: root.borderColor
            strokeWidth: 1
            visible: dashSurfaceWrapper.filletFactor > 0.01
            opacity: dashSurfaceWrapper.filletFactor
        }

        CornerFillet {
            x: root.dropW
            y: root.borderT
            orientation: "dropdownRight"
            cornerRadius: root.filletR
            fillColor: root.glassFill
            strokeColor: root.borderColor
            strokeWidth: 1
            visible: dashSurfaceWrapper.filletFactor > 0.01
            opacity: dashSurfaceWrapper.filletFactor
        }

        Rectangle {
            x: 0
            y: 0
            width: root.dropW
            height: root.currentDropH
            color: root.glassFill
            topLeftRadius: 0
            topRightRadius: 0
            bottomLeftRadius: root.modalRadius
            bottomRightRadius: root.modalRadius

            // Subtle 1px top specular catch
            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 1
                color: root.glassBorder
                opacity: 0.45
            }
        }

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            visible: dashSurfaceWrapper.filletFactor > 0.01
            opacity: dashSurfaceWrapper.filletFactor

            ShapePath {
                fillColor: "transparent"
                strokeColor: root.borderColor
                strokeWidth: 1
                capStyle: ShapePath.FlatCap

                startX: -root.filletR; startY: root.borderT
                PathArc {
                    x: 0
                    y: root.borderT + root.filletR
                    radiusX: root.filletR
                    radiusY: root.filletR
                    direction: PathArc.Clockwise
                }
                PathLine {
                    x: 0
                    y: Math.max(root.borderT + root.filletR, root.currentDropH - root.modalRadius)
                }
                PathArc {
                    x: root.modalRadius
                    y: root.currentDropH
                    radiusX: root.modalRadius
                    radiusY: root.modalRadius
                    direction: PathArc.Counterclockwise
                }
                PathLine {
                    x: Math.max(root.modalRadius, root.dropW - root.modalRadius)
                    y: root.currentDropH
                }
                PathArc {
                    x: root.dropW
                    y: Math.max(root.borderT + root.filletR, root.currentDropH - root.modalRadius)
                    radiusX: root.modalRadius
                    radiusY: root.modalRadius
                    direction: PathArc.Counterclockwise
                }
                PathLine {
                    x: root.dropW
                    y: root.borderT + root.filletR
                }
                PathArc {
                    x: root.dropW + root.filletR
                    y: root.borderT
                    radiusX: root.filletR
                    radiusY: root.filletR
                    direction: PathArc.Clockwise
                }
            }
        }
    }

    // Bottom Popout Fused Solid Surface & Fillets
    Item {
        id: bottomPopoutSurface
        x: root.dockW
        y: root.popoutY
        width: root.currentPopW + (root.fusedProgress > 0.5 ? root.filletR : 0)
        height: root.popoutHeight
        visible: root.popoutOffsetProgress > 0.001

        readonly property real filletFactor: Math.max(0.0, Math.min(1.0, root.currentPopW / Math.max(1, root.filletR)))

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            visible: bottomPopoutSurface.filletFactor > 0.01
            opacity: bottomPopoutSurface.filletFactor

            // 1A. Solid Surface Fill (Floating drawer)
            ShapePath {
                fillColor: (root.fusedProgress < 0.5) ? root.glassFill : "transparent"
                strokeColor: "transparent"
                strokeWidth: 0

                startX: -2; startY: -root.filletR
                PathLine { x: 0; y: -root.filletR }
                PathArc {
                    x: root.filletR
                    y: 0
                    radiusX: root.filletR
                    radiusY: root.filletR
                    direction: PathArc.Counterclockwise
                }
                PathLine {
                    x: Math.max(root.filletR, root.currentPopW - root.filletR)
                    y: 0
                }
                PathArc {
                    x: root.currentPopW
                    y: root.filletR
                    radiusX: root.filletR
                    radiusY: root.filletR
                    direction: PathArc.Clockwise
                }
                PathLine {
                    x: root.currentPopW
                    y: Math.max(root.filletR, root.popoutHeight - root.filletR)
                }
                PathArc {
                    x: Math.max(root.filletR, root.currentPopW - root.filletR)
                    y: root.popoutHeight
                    radiusX: root.filletR
                    radiusY: root.filletR
                    direction: PathArc.Clockwise
                }
                PathLine {
                    x: root.filletR
                    y: root.popoutHeight
                }
                PathArc {
                    x: 0
                    y: root.popoutHeight + root.filletR
                    radiusX: root.filletR
                    radiusY: root.filletR
                    direction: PathArc.Counterclockwise
                }
                PathLine {
                    x: -2
                    y: root.popoutHeight + root.filletR
                }
                PathLine {
                    x: -2
                    y: -root.filletR
                }
            }

            // 1B. Continuous 1px Gray Border Outline (Floating drawer)
            ShapePath {
                fillColor: "transparent"
                strokeColor: (root.fusedProgress < 0.5) ? root.borderColor : "transparent"
                strokeWidth: (root.fusedProgress < 0.5) ? 1 : 0
                capStyle: ShapePath.FlatCap

                startX: 0; startY: -root.filletR
                PathArc {
                    x: root.filletR
                    y: 0
                    radiusX: root.filletR
                    radiusY: root.filletR
                    direction: PathArc.Counterclockwise
                }
                PathLine {
                    x: Math.max(root.filletR, root.currentPopW - root.filletR)
                    y: 0
                }
                PathArc {
                    x: root.currentPopW
                    y: root.filletR
                    radiusX: root.filletR
                    radiusY: root.filletR
                    direction: PathArc.Clockwise
                }
                PathLine {
                    x: root.currentPopW
                    y: Math.max(root.filletR, root.popoutHeight - root.filletR)
                }
                PathArc {
                    x: Math.max(root.filletR, root.currentPopW - root.filletR)
                    y: root.popoutHeight
                    radiusX: root.filletR
                    radiusY: root.filletR
                    direction: PathArc.Clockwise
                }
                PathLine {
                    x: root.filletR
                    y: root.popoutHeight
                }
                PathArc {
                    x: 0
                    y: root.popoutHeight + root.filletR
                    radiusX: root.filletR
                    radiusY: root.filletR
                    direction: PathArc.Counterclockwise
                }
            }

            // 2A. Solid Surface Fill (Bottom-fused drawer)
            ShapePath {
                fillColor: (root.fusedProgress >= 0.5) ? root.glassFill : "transparent"
                strokeColor: "transparent"
                strokeWidth: 0

                startX: -2; startY: -root.filletR
                PathLine { x: 0; y: -root.filletR }
                PathArc {
                    x: root.filletR
                    y: 0
                    radiusX: root.filletR
                    radiusY: root.filletR
                    direction: PathArc.Counterclockwise
                }
                PathLine {
                    x: Math.max(root.filletR, root.currentPopW - root.filletR)
                    y: 0
                }
                PathArc {
                    x: root.currentPopW
                    y: root.filletR
                    radiusX: root.filletR
                    radiusY: root.filletR
                    direction: PathArc.Clockwise
                }
                PathLine {
                    x: root.currentPopW
                    y: Math.max(root.filletR, root.popoutHeight - root.filletR)
                }
                PathArc {
                    x: root.currentPopW + root.filletR
                    y: root.popoutHeight
                    radiusX: root.filletR
                    radiusY: root.filletR
                    direction: PathArc.Counterclockwise
                }
                PathLine {
                    x: root.currentPopW + root.filletR
                    y: root.popoutHeight + root.borderT + 2
                }
                PathLine {
                    x: -2
                    y: root.popoutHeight + root.borderT + 2
                }
                PathLine {
                    x: -2
                    y: -root.filletR
                }
            }

            // 2B. Continuous 1px Gray Border Outline (Bottom-fused drawer)
            ShapePath {
                fillColor: "transparent"
                strokeColor: (root.fusedProgress >= 0.5) ? root.borderColor : "transparent"
                strokeWidth: (root.fusedProgress >= 0.5) ? 1 : 0
                capStyle: ShapePath.FlatCap

                startX: 0; startY: -root.filletR
                PathArc {
                    x: root.filletR
                    y: 0
                    radiusX: root.filletR
                    radiusY: root.filletR
                    direction: PathArc.Counterclockwise
                }
                PathLine {
                    x: Math.max(root.filletR, root.currentPopW - root.filletR)
                    y: 0
                }
                PathArc {
                    x: root.currentPopW
                    y: root.filletR
                    radiusX: root.filletR
                    radiusY: root.filletR
                    direction: PathArc.Clockwise
                }
                PathLine {
                    x: root.currentPopW
                    y: Math.max(root.filletR, root.popoutHeight - root.filletR)
                }
                PathArc {
                    x: root.currentPopW + root.filletR
                    y: root.popoutHeight
                    radiusX: root.filletR
                    radiusY: root.filletR
                    direction: PathArc.Counterclockwise
                }
            }
        }
    }

    // Right Border Edge Volume/Brightness Control Fused Solid Surface & Fillets
    Item {
        id: rightControlSurface
        x: root.width - root.borderT - currentW
        y: root.rightControlY - root.filletR
        width: currentW + root.borderT
        height: root.rightControlH + root.filletR * 2
        visible: root.rightControlOffsetProgress > 0.001

        readonly property real currentW: root.rightControlW * root.rightControlOffsetProgress
        readonly property real filletFactor: Math.max(0.0, Math.min(1.0, currentW / Math.max(1, root.filletR)))
        readonly property real activeR: root.filletR * filletFactor
        readonly property real offsetY: root.filletR
        readonly property real h: root.rightControlH

        // Fused solid surface fill
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            visible: rightControlSurface.filletFactor > 0.01
            opacity: rightControlSurface.filletFactor

            ShapePath {
                fillColor: root.glassFill
                strokeColor: "transparent"
                strokeWidth: 0

                startX: rightControlSurface.currentW
                startY: rightControlSurface.offsetY - rightControlSurface.activeR

                PathArc {
                    x: rightControlSurface.currentW - rightControlSurface.activeR
                    y: rightControlSurface.offsetY
                    radiusX: rightControlSurface.activeR
                    radiusY: rightControlSurface.activeR
                    direction: PathArc.Clockwise
                }

                PathLine {
                    x: rightControlSurface.activeR
                    y: rightControlSurface.offsetY
                }

                PathArc {
                    x: 0
                    y: rightControlSurface.offsetY + rightControlSurface.activeR
                    radiusX: rightControlSurface.activeR
                    radiusY: rightControlSurface.activeR
                    direction: PathArc.Counterclockwise
                }

                PathLine {
                    x: 0
                    y: rightControlSurface.offsetY + rightControlSurface.h - rightControlSurface.activeR
                }

                PathArc {
                    x: rightControlSurface.activeR
                    y: rightControlSurface.offsetY + rightControlSurface.h
                    radiusX: rightControlSurface.activeR
                    radiusY: rightControlSurface.activeR
                    direction: PathArc.Counterclockwise
                }

                PathLine {
                    x: rightControlSurface.currentW - rightControlSurface.activeR
                    y: rightControlSurface.offsetY + rightControlSurface.h
                }

                PathArc {
                    x: rightControlSurface.currentW
                    y: rightControlSurface.offsetY + rightControlSurface.h + rightControlSurface.activeR
                    radiusX: rightControlSurface.activeR
                    radiusY: rightControlSurface.activeR
                    direction: PathArc.Clockwise
                }

                PathLine {
                    x: rightControlSurface.width + 2
                    y: rightControlSurface.offsetY + rightControlSurface.h + rightControlSurface.activeR
                }
                PathLine {
                    x: rightControlSurface.width + 2
                    y: rightControlSurface.offsetY - rightControlSurface.activeR
                }
                PathLine {
                    x: rightControlSurface.currentW
                    y: rightControlSurface.offsetY - rightControlSurface.activeR
                }
            }
        }

        // Continuous Border Outline Stroke
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

                startX: rightControlSurface.currentW
                startY: rightControlSurface.offsetY - rightControlSurface.activeR

                PathArc {
                    x: rightControlSurface.currentW - rightControlSurface.activeR
                    y: rightControlSurface.offsetY
                    radiusX: rightControlSurface.activeR
                    radiusY: rightControlSurface.activeR
                    direction: PathArc.Clockwise
                }

                PathLine {
                    x: rightControlSurface.activeR
                    y: rightControlSurface.offsetY
                }

                PathArc {
                    x: 0
                    y: rightControlSurface.offsetY + rightControlSurface.activeR
                    radiusX: rightControlSurface.activeR
                    radiusY: rightControlSurface.activeR
                    direction: PathArc.Counterclockwise
                }

                PathLine {
                    x: 0
                    y: rightControlSurface.offsetY + rightControlSurface.h - rightControlSurface.activeR
                }

                PathArc {
                    x: rightControlSurface.activeR
                    y: rightControlSurface.offsetY + rightControlSurface.h
                    radiusX: rightControlSurface.activeR
                    radiusY: rightControlSurface.activeR
                    direction: PathArc.Counterclockwise
                }

                PathLine {
                    x: rightControlSurface.currentW - rightControlSurface.activeR
                    y: rightControlSurface.offsetY + rightControlSurface.h
                }

                PathArc {
                    x: rightControlSurface.currentW
                    y: rightControlSurface.offsetY + rightControlSurface.h + rightControlSurface.activeR
                    radiusX: rightControlSurface.activeR
                    radiusY: rightControlSurface.activeR
                    direction: PathArc.Clockwise
                }
            }
        }
    }
}
