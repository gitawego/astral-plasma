import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Qt5Compat.GraphicalEffects
import "../theme"
import "../config"

Item {
    id: root

    // Active AI agent state
    property bool active: false
    property color brandColor: (typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#818CF8"
    property real rpm: 0.0
    property real tokenRate: 0.0
    property real recentTokens: 0.0
    property real intensity: 0.0
    property string modelDisplayName: ""

    // Frame geometry
    property real borderT: 14
    property real cornerFilletR: 20
    property real bottomWidth: Math.min(680, Math.max(380, 420 + rpm * 24))
    property real rightHeight: Math.min(480, Math.max(220, 240 + rpm * 18))

    // Helper to clamp alpha strictly between 0.0 and 1.0 to prevent Qt setAlphaF warnings
    function safeAlpha(c, a) {
        return Qt.alpha(c, Math.max(0.0, Math.min(1.0, a)));
    }

    // Combined throughput load from request rate (RPM) and token processing rate
    readonly property real throughputLoad: Math.max(0.0, root.rpm + (root.tokenRate / 2500.0) + Math.min(15.0, root.recentTokens / 2000.0))

    // Velocity modulation: higher throughput load accelerates electric travel duration (260ms to 2400ms)
    readonly property int currentTravelDuration: Math.max(260, Math.min(2400, Math.round(2400.0 / (1.0 + 0.28 * throughputLoad))))

    // Electric packet length elongates with higher velocity/momentum (36px to 56px)
    readonly property real packetLength: Math.min(56, Math.max(36, 36 + throughputLoad * 0.9))

    // Energized color modulation based on throughput load
    readonly property color energizedColor: {
        if (throughputLoad >= 8.0) {
            return Qt.lighter(brandColor, 1.40);
        } else if (throughputLoad >= 3.0) {
            return Qt.lighter(brandColor, 1.20);
        } else {
            return brandColor;
        }
    }

    readonly property color accentColor: {
        if (throughputLoad >= 8.0) {
            return Qt.tint(energizedColor, Qt.rgba(1.0, 0.90, 0.40, 0.35));
        } else if (throughputLoad >= 4.0) {
            return Qt.tint(energizedColor, Qt.rgba(0.40, 0.90, 1.0, 0.25));
        } else {
            return energizedColor;
        }
    }

    // Breathing pulse
    property real pulse: 0.0
    SequentialAnimation on pulse {
        running: root.active
        loops: Animation.Infinite
        NumberAnimation {
            to: 1.0
            duration: Math.max(500, Math.min(2200, Math.round(2000.0 / (1.0 + 0.15 * root.throughputLoad))))
            easing.type: Easing.InOutSine
        }
        NumberAnimation {
            to: 0.0
            duration: Math.max(500, Math.min(2200, Math.round(2000.0 / (1.0 + 0.15 * root.throughputLoad))))
            easing.type: Easing.InOutSine
        }
    }

    // Synchronized electric current travel progress across both borders
    property real currentTravelProgress: 0.0
    NumberAnimation on currentTravelProgress {
        running: root.active && root.growthProgress > 0.01
        loops: Animation.Infinite
        from: 0.0
        to: 1.0
        duration: root.currentTravelDuration
    }

    // Smooth entry / exit fade
    property real growthProgress: active ? 1.0 : 0.0
    Behavior on growthProgress {
        NumberAnimation {
            duration: Theme.animDurationNormal
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.curveExpressiveDefaultSpatial
        }
    }

    visible: active || growthProgress > 0.001
    opacity: growthProgress

    // =========================================================================
    // 1. BACKGROUND GROWING LIGHTING (Smooth 2D Optical Bloom into wallpaper)
    // =========================================================================
    Item {
        id: bottomAmbientGlow
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        width: Math.min(720, Math.max(380, 420 + root.rpm * 24))
        height: Math.min(520, Math.max(240, 260 + root.rpm * 18))
        z: 0

        RadialGradient {
            anchors.fill: parent
            horizontalOffset: width * 0.5
            verticalOffset: height * 0.5
            horizontalRadius: width
            verticalRadius: height

            gradient: Gradient {
                GradientStop { position: 0.0; color: root.safeAlpha(root.energizedColor, 0.36 * (0.6 + 0.4 * root.pulse) * root.growthProgress) }
                GradientStop { position: 0.22; color: root.safeAlpha(root.brandColor, 0.18 * root.intensity * root.growthProgress) }
                GradientStop { position: 0.55; color: root.safeAlpha(root.brandColor, 0.06 * root.intensity * root.growthProgress) }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }
    }

    // =========================================================================
    // 2. FUSED CORNER NEXUS (Concave Inverted Fillet bridging bottom & right)
    // =========================================================================
    Item {
        id: fusedCornerNexus
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        width: root.borderT + root.cornerFilletR
        height: root.borderT + root.cornerFilletR
        z: 1

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            // Fused Glass Fill (Single continuous closed polygon wrapping around the concave curve)
            ShapePath {
                fillColor: root.safeAlpha(root.energizedColor, 0.48 * (0.7 + 0.3 * root.pulse))
                strokeColor: "transparent"
                strokeWidth: 0
                startX: parent.width; startY: 0
                PathLine { x: parent.width; y: parent.height }
                PathLine { x: 0; y: parent.height }
                PathLine { x: 0; y: root.cornerFilletR }
                PathArc {
                    x: root.cornerFilletR
                    y: 0
                    radiusX: root.cornerFilletR
                    radiusY: root.cornerFilletR
                    direction: PathArc.Counterclockwise
                }
                PathLine { x: parent.width; y: 0 }
            }

            // Continuous Specular Arc Stroke (1px hairline curving from bottom to right)
            ShapePath {
                fillColor: "transparent"
                strokeColor: Qt.lighter(root.energizedColor, 1.40)
                strokeWidth: 1
                capStyle: ShapePath.FlatCap
                startX: root.cornerFilletR; startY: 0
                PathArc {
                    x: 0
                    y: root.cornerFilletR
                    radiusX: root.cornerFilletR
                    radiusY: root.cornerFilletR
                    direction: PathArc.Clockwise
                }
            }

            // Luminous Arc Flash when electric currents meet at the nexus
            ShapePath {
                fillColor: "transparent"
                strokeColor: root.safeAlpha("#FFFFFF", Math.max(0.0, Math.sin(Math.max(0.0, root.currentTravelProgress - 0.7) / 0.3 * Math.PI) * 0.95))
                strokeWidth: 1.5
                capStyle: ShapePath.RoundCap
                startX: root.cornerFilletR; startY: 0
                PathArc {
                    x: 0
                    y: root.cornerFilletR
                    radiusX: root.cornerFilletR
                    radiusY: root.cornerFilletR
                    direction: PathArc.Clockwise
                }
            }
        }
    }

    // =========================================================================
    // 3. BORDER SURFACE COLOR & SPECULAR DEGRADATION (Strictly 14px thickness)
    // =========================================================================

    // A. Bottom Border Section (Height is strictly root.borderT = 14px, partitioned before fusedCornerNexus)
    Rectangle {
        id: bottomBorderSection
        anchors.bottom: parent.bottom
        anchors.right: fusedCornerNexus.left
        height: root.borderT
        width: Math.max(0, root.bottomWidth - (root.borderT + root.cornerFilletR))
        z: 1

        // Smooth color degradation along the bottom border
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 0.25; color: root.safeAlpha(root.brandColor, 0.12 * root.intensity) }
            GradientStop { position: 0.70; color: root.safeAlpha(root.brandColor, 0.28 * root.intensity) }
            GradientStop { position: 1.0; color: root.safeAlpha(root.energizedColor, 0.48 * (0.7 + 0.3 * root.pulse)) }
        }

        // Top 1px specular hairline with seamless degradation merging with desktop frame
        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            z: 5

            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.20; color: root.safeAlpha(root.brandColor, 0.35 * root.intensity) }
                GradientStop { position: 0.65; color: root.safeAlpha(root.energizedColor, 0.85) }
                GradientStop { position: 1.0; color: Qt.lighter(root.energizedColor, 1.40) }
            }
        }

        // Traveling digital data packet (horizontal electric current) across the 1px specular border
        Rectangle {
            id: dataPacket
            y: 0
            width: root.packetLength
            height: 1
            z: 6
            color: "transparent"
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.25; color: root.safeAlpha(root.accentColor, 0.70) }
                GradientStop { position: 0.50; color: "#FFFFFF" }
                GradientStop { position: 0.75; color: root.safeAlpha(root.accentColor, 0.70) }
                GradientStop { position: 1.0; color: "transparent" }
            }

            x: Math.round(root.currentTravelProgress * (bottomBorderSection.width - width))
        }

        // =====================================================================
        // 4. MATRIX HORIZONTAL DIGITAL CODE RAIN & EMBEDDED HUD
        // =====================================================================
        Row {
            id: matrixHorizontalTrack
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            anchors.rightMargin: 4
            spacing: 5
            z: 10

            // Trailing Matrix Glyphs (Left side, fading out)
            Repeater {
                model: 12
                delegate: Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.matrixGlyphs[(index * 3 + root.matrixTick) % root.matrixGlyphs.length]
                    font.family: (typeof Theme !== "undefined" && Theme.fontFamilyMonospace) ? Theme.fontFamilyMonospace : "monospace"
                    font.pixelSize: 9
                    font.weight: Font.Bold
                    color: {
                        // Degradation from left (faint) to right (brighter)
                        const alpha = Math.min(0.9, Math.max(0.08, (index + 1) / 12 * 0.9));
                        return root.safeAlpha(root.brandColor, alpha * (0.8 + 0.2 * root.pulse));
                    }
                }
            }

            // Central High-Contrast Cyberpunk / Matrix HUD Capsule
            Rectangle {
                id: hudCapsule
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: 0.5
                height: 12
                width: hudRow.width + 10
                radius: 3
                color: root.safeAlpha("#0A090D", 0.88)
                border.width: 1
                border.color: root.safeAlpha(root.energizedColor, 0.45)

                Row {
                    id: hudRow
                    anchors.centerIn: parent
                    spacing: 4

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "["
                        font.family: (typeof Theme !== "undefined" && Theme.fontFamilyMonospace) ? Theme.fontFamilyMonospace : "monospace"
                        font.pixelSize: 9
                        font.bold: true
                        color: Qt.lighter(root.energizedColor, 1.35)
                    }

                    // Stacked Token Glyphs
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "\uf51e" // FontAwesome / Material stacked tokens
                        font.family: "Material Symbols Outlined, Font Awesome 6 Free, sans-serif"
                        font.pixelSize: 10
                        color: root.energizedColor
                        scale: 0.92 + (root.pulse * 0.16)
                    }

                    // Active Model Code Name (Title Case, clean bold, letter spacing)
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: (root.modelDisplayName && root.modelDisplayName !== "AI Agent")
                            ? root.modelDisplayName
                            : "Matrix AI"
                        font.family: (typeof Theme !== "undefined" && Theme.fontFamilyMonospace) ? Theme.fontFamilyMonospace : "monospace"
                        font.pixelSize: 9
                        font.bold: true
                        font.letterSpacing: 0.3
                        color: "#FFFFFF"
                        style: Text.Outline
                        styleColor: Qt.rgba(0.0, 0.0, 0.0, 0.60)
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "::"
                        font.family: (typeof Theme !== "undefined" && Theme.fontFamilyMonospace) ? Theme.fontFamilyMonospace : "monospace"
                        font.pixelSize: 9
                        font.bold: true
                        color: root.safeAlpha("#FFFFFF", 0.65)
                    }

                    // Live RPM / Frequency Indicator & Token throughput
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: {
                            if (root.recentTokens >= 1000) {
                                const kTok = (root.recentTokens / 1000).toFixed(root.recentTokens >= 10000 ? 0 : 1);
                                return ((root.rpm > 0 ? (root.rpm >= 10 ? root.rpm.toFixed(0) : root.rpm.toFixed(1)) + " RPM " : "") + kTok + "k Tok").trim();
                            } else if (root.rpm > 0) {
                                return (root.rpm >= 10 ? root.rpm.toFixed(0) : root.rpm.toFixed(1)) + " RPM";
                            } else {
                                return "ACTIVE";
                            }
                        }
                        font.family: (typeof Theme !== "undefined" && Theme.fontFamilyMonospace) ? Theme.fontFamilyMonospace : "monospace"
                        font.pixelSize: 9
                        font.bold: true
                        font.letterSpacing: 0.2
                        color: Qt.lighter(root.energizedColor, 1.35)
                        style: Text.Outline
                        styleColor: Qt.rgba(0.0, 0.0, 0.0, 0.50)
                    }

                    // Digital Equalizer Binary Pulses
                    Row {
                        spacing: 2
                        anchors.verticalCenter: parent.verticalCenter

                        Rectangle {
                            width: 2
                            height: Math.min(7, Math.max(2, 3 + Math.round(4 * Math.abs(Math.sin(root.pulse * Math.PI)) * Math.min(1.2, Math.max(0.6, root.throughputLoad * 0.20)))))
                            color: root.energizedColor
                            radius: 0.5
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Rectangle {
                            width: 2
                            height: Math.min(7, Math.max(2, 4 + Math.round(5 * Math.abs(Math.cos(root.pulse * Math.PI)) * Math.min(1.2, Math.max(0.6, root.throughputLoad * 0.20)))))
                            color: root.accentColor
                            radius: 0.5
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Rectangle {
                            width: 2
                            height: Math.min(7, Math.max(2, 3 + Math.round(4 * Math.abs(Math.sin((root.pulse + 0.5) * Math.PI)) * Math.min(1.2, Math.max(0.6, root.throughputLoad * 0.20)))))
                            color: root.energizedColor
                            radius: 0.5
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "]"
                        font.family: (typeof Theme !== "undefined" && Theme.fontFamilyMonospace) ? Theme.fontFamilyMonospace : "monospace"
                        font.pixelSize: 9
                        font.bold: true
                        color: Qt.lighter(root.energizedColor, 1.35)
                    }
                }
            }

            // Leading Head Matrix Glyphs (Right side, glowing intense phosphor white & brand)
            Repeater {
                model: 8
                delegate: Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: 0.5
                    text: root.matrixGlyphs[(index * 5 + root.matrixTick + 7) % root.matrixGlyphs.length]
                    font.family: (typeof Theme !== "undefined" && Theme.fontFamilyMonospace) ? Theme.fontFamilyMonospace : "monospace"
                    font.pixelSize: 9
                    font.weight: (index >= 6) ? Font.Black : Font.Bold
                    color: (index >= 6) ? "#FFFFFF" : Qt.lighter(root.energizedColor, 1.25)
                    style: Text.Outline
                    styleColor: Qt.rgba(0.0, 0.0, 0.0, 0.40)
                }
            }
        }
    }

    // B. Right Border Section (Width is strictly root.borderT = 14px, partitioned above fusedCornerNexus)
    Rectangle {
        id: rightBorderSection
        anchors.right: parent.right
        anchors.bottom: fusedCornerNexus.top
        width: root.borderT
        height: Math.max(0, root.rightHeight - (root.borderT + root.cornerFilletR))
        z: 1

        // Smooth vertical color degradation
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 0.25; color: root.safeAlpha(root.brandColor, 0.12 * root.intensity) }
            GradientStop { position: 0.70; color: root.safeAlpha(root.brandColor, 0.28 * root.intensity) }
            GradientStop { position: 1.0; color: root.safeAlpha(root.energizedColor, 0.48 * (0.7 + 0.3 * root.pulse)) }
        }

        // Left 1px specular hairline with seamless vertical degradation
        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 1
            z: 5

            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.25; color: root.safeAlpha(root.brandColor, 0.35 * root.intensity) }
                GradientStop { position: 0.70; color: root.safeAlpha(root.energizedColor, 0.85) }
                GradientStop { position: 1.0; color: Qt.lighter(root.energizedColor, 1.40) }
            }
        }

        // Traveling digital data packet (vertical electric current) across the 1px specular border
        Rectangle {
            id: dataPacketVertical
            x: 0
            width: 1
            height: root.packetLength
            z: 6
            color: "transparent"
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.25; color: root.safeAlpha(root.accentColor, 0.70) }
                GradientStop { position: 0.50; color: "#FFFFFF" }
                GradientStop { position: 0.75; color: root.safeAlpha(root.accentColor, 0.70) }
                GradientStop { position: 1.0; color: "transparent" }
            }

            y: Math.round(root.currentTravelProgress * (rightBorderSection.height - height))
        }

        // =====================================================================
        // 5. MATRIX VERTICAL DIGITAL RAIN (Falling downward into the corner)
        // =====================================================================
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 4
            spacing: 2
            z: 10

            Repeater {
                model: 14
                delegate: Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.matrixGlyphs[(index * 7 + root.matrixTick + 3) % root.matrixGlyphs.length]
                    font.family: (typeof Theme !== "undefined" && Theme.fontFamilyMonospace) ? Theme.fontFamilyMonospace : "monospace"
                    font.pixelSize: 9
                    font.weight: (index >= 12) ? Font.Black : Font.Bold
                    color: {
                        if (index >= 12) {
                            return "#FFFFFF"; // Leading head is brilliant white
                        } else if (index >= 8) {
                            return Qt.lighter(root.energizedColor, 1.25);
                        } else {
                            const alpha = Math.max(0.12, index / 8 * 0.85);
                            return root.safeAlpha(root.brandColor, alpha);
                        }
                    }
                }
            }
        }
    }

    // =========================================================================
    // 5. MATRIX ANIMATION TIMERS & GLYPH CYCLING (0% CPU when idle)
    // =========================================================================
    property int matrixTick: 0
    readonly property var matrixGlyphs: [
        "0", "1", "7", "A", "F", "X", "9", "4", "Z", "8", "E", "C", "3", "5", "B", "D",
        "\uFF66", "\uFF71", "\uFF76", "\uFF7E", "\uFF82", "\uFF84", "\uFF89", "\uFF8D", "\uFF90", "\uFF97"
    ]

    Timer {
        id: matrixStreamTimer
        interval: Math.max(50, 110 - Math.round(root.rpm * 6))
        repeat: true
        running: root.active && root.growthProgress > 0.01
        onTriggered: {
            root.matrixTick = (root.matrixTick + 1) % 10000;
        }
    }
}
