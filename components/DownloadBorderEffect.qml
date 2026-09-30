import QtQuick
import QtQuick.Shapes
import "motion"
import "../theme"
import "../config"

// Top-right aggregate download progress effect (D10–D15): the mirror of
// MatrixBorderEffect (bottom-right AI), but progress-driven instead of
// activity-driven.
//
// Geometry (Q10): top segment growing leftwards from the corner + short
// right-top leg downwards + fused top-right nexus. Strictly inside borderT
// (no physical growth). Capped widths so it never invades the dropdown.
//
// Encoding (Q11): static fill fraction = totalProgress (Σ done / Σ total)
// along the top segment + traveling packet whose speed/brightness follows
// totalSpeed. Indeterminate (unknown lengths) falls back to AI-style loop.
// Error state (Q13): warm-red tint held until dismissed. Complete: brief
// success flash then fade. Paused-all: dim frozen fill, no travel.
//
// Perf: timers gate on `running: root.active && root.growthProgress > 0.01`
// (same 0%-idle-CPU contract as MatrixBorderEffect). Property updates arrive
// only on daemon change events (≤2/s active, 1/5s idle) — the fill eases via
// Theme curves, never via a repaint loop. Hidden while a notification owns
// the corner (Q15, popup z:1000 wins).
Item {
    id: root

    // Aggregate inputs (bound to DownloadService by the shell).
    property real totalProgress: 0.0
    property real totalSpeed: 0
    property int activeCount: 0
    property bool indeterminate: false
    property bool hasError: false
    property bool showCompleteFlash: false
    property bool effectEnabled: true
    property bool cornerBusy: false // notification popup owns the corner

    // Frame geometry (same contract as MatrixBorderEffect).
    property real borderT: 14
    property real cornerFilletR: 20
    property real topWidth: 380
    property real rightHeight: 220

    property color baseColor: (typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#38bdf8"

    readonly property bool hasActivity: root.activeCount > 0 || root.showCompleteFlash
    readonly property bool active: root.effectEnabled && root.hasActivity && !root.cornerBusy

    function safeAlpha(c, a) {
        return Qt.alpha(c, Math.max(0.0, Math.min(1.0, a)));
    }

    readonly property color stateColor: {
        if (root.hasError) return "#f87171";
        if (root.showCompleteFlash) return "#34d399";
        return root.baseColor;
    }

    // Packet travel: speed-modulated like throughputLoad (faster when moving
    // bytes, calm otherwise); frozen when nothing moves (paused = dim hold).
    readonly property real speedNorm: Math.min(1.0, (root.totalSpeed || 0) / 5242880)
    readonly property int travelDuration: root.indeterminate
        ? 2200
        : Math.max(1350, Math.min(3200, Math.round(3200.0 / (1.0 + 3.0 * root.speedNorm))))
    readonly property real packetLength: root.indeterminate ? 72 : Math.min(96, Math.max(48, 48 + root.speedNorm * 48))

    // Breathing pulse. Capped by MotionPacer: a download can run for hours, so an
    // uncapped vsync-rate animation would keep the full-screen shell rendering at
    // display refresh (165–240 Hz) for the entire transfer.
    MotionPacer {
        id: pulsePacer
        running: root.active && root.growthProgress > 0.01 && root.totalSpeed > 0
        period: 2800
    }
    readonly property real pulse: pulsePacer.breath

    // Traveling packet progress: indeterminate loops; determinate loops too
    // (fill carries progress, motion carries liveness — Q11 dual encode).
    MotionPacer {
        id: travelPacer
        running: root.active && root.growthProgress > 0.01 && (root.totalSpeed > 0 || root.indeterminate)
        period: root.travelDuration
    }
    readonly property real travelProgress: travelPacer.phase

    // Smooth entry / exit fade.
    property real growthProgress: active ? 1.0 : 0.0
    Behavior on growthProgress {
        NumberAnimation {
            duration: Theme.animDurationNormal
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.curveExpressiveDefaultSpatial
        }
    }

    // Eased fill fraction (property changes at ≤2/s; animation smooths).
    property real fillProgress: 0.0
    onTotalProgressChanged: {
        if (!root.indeterminate) root.fillProgress = Math.min(1.0, Math.max(0.0, root.totalProgress));
    }
    Behavior on fillProgress {
        NumberAnimation {
            duration: (typeof Theme !== "undefined" && Theme.animExpressiveDefaultEffects) ? Theme.animExpressiveDefaultEffects : 200
            easing.type: Easing.BezierSpline
            easing.bezierCurve: (typeof Theme !== "undefined" && Theme.curveExpressiveDefaultEffects) ? Theme.curveExpressiveDefaultEffects : [0.34, 0.80, 0.34, 1.0, 1.0, 1.0]
        }
    }

    visible: active || growthProgress > 0.001
    opacity: growthProgress

    // Complete flash auto-clear (1.5s success hold, Q13).
    Timer {
        id: flashTimer
        interval: 1500
        repeat: false
        onTriggered: root.showCompleteFlash = false
    }
    onShowCompleteFlashChanged: {
        if (root.showCompleteFlash) flashTimer.restart();
        else flashTimer.stop();
    }

    // =====================================================================
    // 1. TOP AMBIENT GLOW (restrained: matches AI glow budget ≤220x160)
    // =====================================================================
    Item {
        id: topAmbientGlow
        anchors.right: parent.right
        anchors.top: parent.top
        width: 200
        height: 120
        z: 0

        // Gradient stays static (no per-frame stop churn); the breathing is a cheap
        // node-opacity update.
        opacity: root.growthProgress * (0.6 + 0.4 * root.pulse)
        Rectangle {
            anchors.fill: parent
            color: "transparent"
            gradient: Gradient {
                GradientStop { position: 0.0; color: root.safeAlpha(root.stateColor, 0.08) }
                GradientStop { position: 0.5; color: root.safeAlpha(root.stateColor, 0.03) }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }
    }

    // =====================================================================
    // 2. FUSED TOP-RIGHT NEXUS (mirror of bottom-right fusedCornerNexus)
    // =====================================================================
    Item {
        id: fusedTopNexus
        anchors.right: parent.right
        anchors.top: parent.top
        width: root.borderT + root.cornerFilletR
        height: root.borderT + root.cornerFilletR
        z: 1

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                fillColor: root.safeAlpha(root.stateColor, 0.44 * (0.7 + 0.3 * root.pulse))
                strokeColor: "transparent"
                strokeWidth: 0
                startX: 0; startY: 0
                PathLine { x: 0; y: parent.height }
                PathLine { x: parent.width; y: parent.height }
                PathLine { x: parent.width; y: root.cornerFilletR }
                PathArc {
                    x: parent.width - root.cornerFilletR
                    y: 0
                    radiusX: root.cornerFilletR
                    radiusY: root.cornerFilletR
                    direction: PathArc.Clockwise
                }
                PathLine { x: 0; y: 0 }
            }

            ShapePath {
                fillColor: "transparent"
                strokeColor: Qt.lighter(root.stateColor, 1.20)
                strokeWidth: 1
                capStyle: ShapePath.FlatCap
                startX: 0; startY: root.cornerFilletR
                PathArc {
                    x: parent.width - root.cornerFilletR
                    y: 0
                    radiusX: root.cornerFilletR
                    radiusY: root.cornerFilletR
                    direction: PathArc.Counterclockwise
                }
            }
        }
    }

    // =====================================================================
    // 3. TOP BORDER SECTION (fill fraction + traveling packet, in borderT)
    // =====================================================================
    Rectangle {
        id: topBorderSection
        anchors.top: parent.top
        anchors.right: fusedTopNexus.left
        height: root.borderT
        width: Math.max(0, root.topWidth - (root.borderT + root.cornerFilletR))
        z: 1
        color: "transparent"

        // Base degradation wash.
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.30; color: root.safeAlpha(root.stateColor, 0.10) }
                GradientStop { position: 1.0; color: root.safeAlpha(root.stateColor, 0.30 * (0.7 + 0.3 * root.pulse)) }
            }
        }

        // Static progress fill (grows right→left toward the corner).
        Rectangle {
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            width: parent.width * (root.indeterminate ? 0.0 : root.fillProgress)
            visible: !root.indeterminate
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: root.safeAlpha(root.stateColor, 0.12) }
                GradientStop { position: 0.60; color: root.safeAlpha(root.stateColor, 0.28) }
                GradientStop { position: 1.0; color: root.safeAlpha(root.stateColor, 0.48 * (0.7 + 0.3 * root.pulse)) }
            }
        }

        // Bottom 1px specular hairline (the light catch, like AI's top hairline).
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            z: 5
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.35; color: root.safeAlpha(root.stateColor, 0.55) }
                GradientStop { position: 1.0; color: root.safeAlpha(root.stateColor, 0.85) }
            }
        }

        // Traveling packet (liveness; speed = download speed).
        Rectangle {
            id: topPacket
            y: parent.height - 4
            width: root.packetLength
            height: 3
            z: 6
            radius: 1.5
            visible: root.totalSpeed > 0 || root.indeterminate
            color: "transparent"
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.20; color: root.safeAlpha(root.stateColor, 0.85) }
                GradientStop { position: 0.50; color: "#FFFFFF" }
                GradientStop { position: 0.80; color: root.safeAlpha(root.stateColor, 0.85) }
                GradientStop { position: 1.0; color: "transparent" }
            }
            x: Math.round((1.0 - root.travelProgress) * (topBorderSection.width - width))
        }
    }

    // =====================================================================
    // 4. RIGHT-TOP LEG (short glow leg mirroring AI's right section)
    // =====================================================================
    Rectangle {
        id: rightTopSection
        anchors.right: parent.right
        anchors.top: fusedTopNexus.bottom
        width: root.borderT
        height: Math.max(0, root.rightHeight - (root.borderT + root.cornerFilletR))
        z: 1
        color: "transparent"

        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0.0; color: root.safeAlpha(root.stateColor, 0.30 * (0.7 + 0.3 * root.pulse)) }
                GradientStop { position: 0.70; color: root.safeAlpha(root.stateColor, 0.10) }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }

        // Left 1px specular hairline.
        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 1
            z: 5
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0.0; color: root.safeAlpha(root.stateColor, 0.85) }
                GradientStop { position: 0.65; color: root.safeAlpha(root.stateColor, 0.55) }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }

        // Descending packet (phase-offset twin of the top packet).
        Rectangle {
            x: parent.width - 4
            width: 3
            height: Math.round(root.packetLength * 0.85)
            z: 6
            radius: 1.5
            visible: topPacket.visible
            color: "transparent"
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.25; color: root.safeAlpha(root.stateColor, 0.75) }
                GradientStop { position: 0.50; color: "#FFFFFF" }
                GradientStop { position: 0.75; color: root.safeAlpha(root.stateColor, 0.75) }
                GradientStop { position: 1.0; color: "transparent" }
            }
            y: Math.round(((root.travelProgress + 0.50) % 1.0) * (rightTopSection.height - height))
        }
    }

    // =====================================================================
    // 5. HUD CAPSULE (aggregate text; capsule-only click → DownloadsTab, Q14)
    // =====================================================================
    Item {
        id: hudSlot
        anchors.top: parent.top
        anchors.topMargin: Math.max(0, (root.borderT - 12) / 2)
        anchors.right: fusedTopNexus.left
        anchors.rightMargin: 6
        width: hudCapsule.width
        height: 12
        z: 10
        visible: root.growthProgress > 0.01

        property string hudText: ""
        property bool hovered: false

        Rectangle {
            id: hudCapsule
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            height: 12
            width: hudRow.width + 10
            radius: 3
            color: root.safeAlpha("#0A090D", 0.88)
            border.width: 1
            border.color: root.safeAlpha(root.stateColor, hudSlot.hovered ? 0.75 : 0.45)

            Behavior on border.color { ColorAnimation { duration: 150 } }

            Row {
                id: hudRow
                anchors.centerIn: parent
                spacing: 4

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "["
                    font.family: (typeof Theme !== "undefined" && Theme.fontMonospace) ? Theme.fontMonospace : "monospace"
                    font.pixelSize: 9
                    font.bold: true
                    color: Qt.lighter(root.stateColor, 1.35)
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: hudSlot.hudText
                    font.family: (typeof Theme !== "undefined" && Theme.fontMonospace) ? Theme.fontMonospace : "monospace"
                    font.pixelSize: 9
                    font.bold: true
                    font.letterSpacing: 0.2
                    color: "#FFFFFF"
                    style: Text.Outline
                    styleColor: Qt.rgba(0.0, 0.0, 0.0, 0.60)
                }

                // Liveness pulses (freeze when stalled: height collapses).
                Row {
                    spacing: 2
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.totalSpeed > 0

                    Rectangle {
                        width: 2
                        height: Math.min(7, Math.max(2, 3 + Math.round(4 * Math.abs(Math.sin(root.pulse * Math.PI)))))
                        color: root.stateColor
                        radius: 0.5
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Rectangle {
                        width: 2
                        height: Math.min(7, Math.max(2, 4 + Math.round(5 * Math.abs(Math.cos(root.pulse * Math.PI)))))
                        color: Qt.lighter(root.stateColor, 1.30)
                        radius: 0.5
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "]"
                    font.family: (typeof Theme !== "undefined" && Theme.fontMonospace) ? Theme.fontMonospace : "monospace"
                    font.pixelSize: 9
                    font.bold: true
                    color: Qt.lighter(root.stateColor, 1.35)
                }
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: hudSlot.hovered = true
                onExited: hudSlot.hovered = false
                onClicked: hudSlot.openDownloads()
            }
        }

        function openDownloads() {
            if (typeof Config === "undefined") return;
            Config.activeDashboardTab = "downloads";
            Config.dashboardVisible = true;
        }
    }
}
