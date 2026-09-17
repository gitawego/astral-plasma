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

    layer.enabled: true
    layer.effect: MultiEffect {
        shadowEnabled: true
        blurMax: 32
        shadowBlur: 1.0
        shadowVerticalOffset: 3
        shadowColor: Qt.rgba(0, 0, 0, 0.28)
    }

    // Left Dock Surface
    Rectangle {
        id: dockBg
        visible: Config.dockEnabled
        x: 0
        y: 0
        width: root.dockW
        height: root.height
        color: Colors.glassSurface

        Rectangle {
            x: parent.width - 1
            y: root.borderT + root.filletR
            width: 1
            height: Math.max(0, parent.height - (root.borderT * 2 + root.filletR * 2))
            color: root.borderColor
        }
    }

    readonly property real topBorderRightLimit: (typeof NotificationService !== "undefined" && NotificationService.hasNotification)
        ? (root.width - 380 - root.filletR)
        : (root.width - root.borderT - root.filletR)

    // Thin Top Border
    Rectangle {
        id: topBorder
        x: 0
        y: 0
        width: root.width
        height: root.borderT
        color: Colors.glassSurface

        // Segment left of dropdown
        Rectangle {
            x: root.dockW + root.filletR
            y: parent.height - 1
            height: 1
            width: root.dropdownOffsetProgress > 0.001 
                ? Math.max(0, root.dropX - root.filletR - (root.dockW + root.filletR))
                : Math.max(0, root.topBorderRightLimit - (root.dockW + root.filletR))
            color: root.borderColor
        }

        // Segment right of dropdown (only when dropdown is open)
        Rectangle {
            visible: root.dropdownOffsetProgress > 0.001
            x: root.dropX + root.dropW + root.filletR
            y: parent.height - 1
            height: 1
            width: Math.max(0, root.topBorderRightLimit - (root.dropX + root.dropW + root.filletR))
            color: root.borderColor
        }
    }

    readonly property real rightBorderTopLimit: (typeof NotificationService !== "undefined" && NotificationService.hasNotification)
        ? (74 + root.filletR)
        : (root.borderT + root.filletR)
    readonly property real rightBorderBottomLimit: root.height - (root.borderT + root.filletR)

    readonly property real rightControlGapTop: root.rightControlY - root.filletR * root.rightControlOffsetProgress
    readonly property real rightControlGapBottom: root.rightControlY + root.rightControlH + root.filletR * root.rightControlOffsetProgress

    // Thin Right Border
    Rectangle {
        id: rightBorder
        x: root.width - root.borderT
        y: 0
        width: root.borderT
        height: root.height
        color: Colors.glassSurface

        // Upper segment
        Rectangle {
            x: 0
            y: root.rightBorderTopLimit
            width: 1
            height: root.rightControlOffsetProgress > 0.001
                ? Math.max(0, root.rightControlGapTop - y)
                : Math.max(0, root.rightBorderBottomLimit - y)
            color: root.borderColor
        }

        // Lower segment (active when right edge control is open)
        Rectangle {
            visible: root.rightControlOffsetProgress > 0.001
            x: 0
            y: root.rightControlGapBottom
            width: 1
            height: Math.max(0, root.rightBorderBottomLimit - y)
            color: root.borderColor
        }
    }

    // Thin Bottom Border
    Rectangle {
        id: bottomBorder
        x: 0
        y: root.height - root.borderT
        width: root.width
        height: root.borderT
        color: Colors.glassSurface

        Rectangle {
            x: root.dockW + (root.popoutOffsetProgress > 0.001
                ? (root.filletR + root.currentPopW * root.fusedProgress)
                : root.filletR)
            y: 0
            height: 1
            width: Math.max(0, parent.width - x - (root.borderT + root.filletR))
            color: root.borderColor
        }
    }

    // Inner Fillet: Top-Left
    CornerFillet {
        x: root.dockW
        y: root.borderT
        orientation: "topLeft"
        cornerRadius: root.filletR
        fillColor: Colors.glassSurface
        strokeColor: root.borderColor
        strokeWidth: 1
    }

    // Inner Fillet: Top-Right
    CornerFillet {
        visible: !NotificationService.hasNotification
        x: root.width - root.borderT - root.filletR
        y: root.borderT
        orientation: "topRight"
        cornerRadius: root.filletR
        fillColor: Colors.glassSurface
        strokeColor: root.borderColor
        strokeWidth: 1
    }

    // Inner Fillet: Bottom-Left
    CornerFillet {
        visible: (1.0 - (root.fusedProgress * root.popoutOffsetProgress)) > 0.01
        opacity: 1.0 - (root.fusedProgress * root.popoutOffsetProgress)
        x: root.dockW
        y: root.height - root.borderT - root.filletR
        orientation: "bottomLeft"
        cornerRadius: root.filletR
        fillColor: Colors.glassSurface
        strokeColor: root.borderColor
        strokeWidth: 1
    }

    // Inner Fillet: Bottom-Right
    CornerFillet {
        x: root.width - root.borderT - root.filletR
        y: root.height - root.borderT - root.filletR
        orientation: "bottomRight"
        cornerRadius: root.filletR
        fillColor: Colors.glassSurface
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
            fillColor: Colors.glassModalSurface
            strokeColor: "transparent"
            visible: dashSurfaceWrapper.filletFactor > 0.01
            opacity: dashSurfaceWrapper.filletFactor
        }

        CornerFillet {
            x: root.dropW
            y: root.borderT
            orientation: "dropdownRight"
            cornerRadius: root.filletR
            fillColor: Colors.glassModalSurface
            strokeColor: "transparent"
            visible: dashSurfaceWrapper.filletFactor > 0.01
            opacity: dashSurfaceWrapper.filletFactor
        }

        Rectangle {
            x: -2
            y: 0
            width: root.dropW + 4
            height: root.currentDropH
            color: Colors.glassModalSurface
            topLeftRadius: 0
            topRightRadius: 0
            bottomLeftRadius: Theme.radiusGlassModal
            bottomRightRadius: Theme.radiusGlassModal

            // Subtle 1px top specular catch
            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 1
                color: Colors.glassBorderSpecular
                opacity: 0.35
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
                    y: Math.max(root.borderT + root.filletR, root.currentDropH - Theme.radiusGlassModal)
                }
                PathArc {
                    x: Theme.radiusGlassModal
                    y: root.currentDropH
                    radiusX: Theme.radiusGlassModal
                    radiusY: Theme.radiusGlassModal
                    direction: PathArc.Counterclockwise
                }
                PathLine {
                    x: Math.max(Theme.radiusGlassModal, root.dropW - Theme.radiusGlassModal)
                    y: root.currentDropH
                }
                PathArc {
                    x: root.dropW
                    y: Math.max(root.borderT + root.filletR, root.currentDropH - Theme.radiusGlassModal)
                    radiusX: Theme.radiusGlassModal
                    radiusY: Theme.radiusGlassModal
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
                fillColor: (root.fusedProgress < 0.5) ? Colors.glassSurface : "transparent"
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
                fillColor: (root.fusedProgress >= 0.5) ? Colors.glassSurface : "transparent"
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
                fillColor: Colors.glassSurface
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
