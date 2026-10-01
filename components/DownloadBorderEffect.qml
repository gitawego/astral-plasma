import QtQuick
import QtQuick.Shapes
import "motion"
import "../theme"
import "../config"

// Top-right aggregate download progress effect (D10–D15): the symmetric mirror of
// MatrixBorderEffect (bottom-right AI), featuring progression of total download,
// session max/min download speed telemetry, streaming ingress matrix rain, and
// an interactive cyberpunk HUD capsule.
//
// Geometry: top segment growing leftwards from the corner + short right-top leg
// downwards + fused top-right nexus. Strictly inside borderT: 14 (no physical growth).
// Capped widths (topWidth <= 420, rightHeight <= 260) to avoid dropdown invasion.
//
// Encoding:
// - Prominent 2px progress rail along the bottom edge with glowing fill & specular pip.
// - Static fill fraction = totalProgress (Σ done / Σ total) along the top segment.
// - Traveling digital packet whose speed/momentum follows totalSpeed.
// - High-contrast HUD capsule: [ ↓ {count} · {pct}% ▏ {done}/{total} :: {cur} (▲{max} · ▼{min}) · {eta} ılı ]
// - Streaming digital hex rain driven by MotionClock for 0% idle CPU.
// - Error state: warm-red tint (#f87171). Complete: emerald green flash (#34d399).
//
// Performance:
// Timers gate on `running: root.active && root.growthProgress > 0.01` (0% idle CPU).
Item {
    id: root

    // Aggregate inputs (bound to DownloadService by the shell).
    property real totalProgress: 0.0
    property double totalCompletedBytes: 0
    property double totalBytes: 0
    property real totalSpeed: 0
    property real sessionMaxSpeed: 0
    property real sessionMinSpeed: 0
    property int activeCount: 0
    property bool indeterminate: false
    property bool isPaused: false
    property bool hasError: false
    property bool showCompleteFlash: false
    property bool effectEnabled: true
    property bool cornerBusy: false // notification popup owns the corner
    property string hudText: ""

    // Frame geometry (strictly adheres to shell border contracts).
    property real borderT: 14
    property real cornerFilletR: 20
    property real topWidth: 400
    property real rightHeight: 220

    property color baseColor: (typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#38bdf8"

    readonly property bool hasActivity: root.activeCount > 0 || root.showCompleteFlash || root.isPaused
    readonly property bool active: root.effectEnabled && root.hasActivity && !root.cornerBusy

    // Expose hudSlot item for automated test introspection
    property alias hudSlotItem: hudSlot

    function safeAlpha(c, a) {
        return Qt.alpha(c, Math.max(0.0, Math.min(1.0, a)));
    }

    readonly property color stateColor: {
        if (root.hasError) return "#f87171";
        if (root.showCompleteFlash) return "#34d399";
        return root.baseColor;
    }

    readonly property color secondaryColor: {
        if (root.hasError) return "#fca5a5";
        if (root.showCompleteFlash) return "#6ee7b7";
        return (typeof Colors !== "undefined" && Colors.tertiary) ? Colors.tertiary : "#a855f7";
    }

    // Dynamic session peak/floor speed tracking
    onTotalSpeedChanged: {
        if (root.active && root.totalSpeed > 0 && !root.isPaused) {
            if (root.sessionMaxSpeed <= 0 || root.totalSpeed > root.sessionMaxSpeed) {
                root.sessionMaxSpeed = root.totalSpeed;
            }
            if (root.sessionMinSpeed <= 0 || root.totalSpeed < root.sessionMinSpeed) {
                root.sessionMinSpeed = root.totalSpeed;
            }
        }
    }

    onActiveCountChanged: {
        if (root.activeCount === 0 && !root.isPaused) {
            root.sessionMaxSpeed = 0;
            root.sessionMinSpeed = 0;
        }
    }

    // Packet travel: speed-modulated like throughputLoad (faster when moving
    // bytes, calm otherwise); frozen when stalled or paused.
    readonly property real speedNorm: Math.min(1.0, (root.totalSpeed || 0) / 5242880)
    readonly property int travelDuration: root.indeterminate
        ? 2200
        : Math.max(1350, Math.min(3200, Math.round(3200.0 / (1.0 + 3.0 * root.speedNorm))))
    readonly property real packetLength: root.indeterminate ? 72 : Math.min(96, Math.max(48, 48 + root.speedNorm * 48))

    // Formatters for byte sizes and transfer rates
    function formatBytes(bytes) {
        if (!bytes || bytes <= 0) return "0 B";
        const units = ["B", "KiB", "MiB", "GiB", "TiB"];
        const i = Math.floor(Math.log(bytes) / Math.log(1024));
        const p = Math.min(Math.max(0, i), units.length - 1);
        return (bytes / Math.pow(1024, p)).toFixed(1) + " " + units[p];
    }

    function formatBytesCompact(bytes) {
        if (!bytes || bytes <= 0) return "0B";
        const units = ["B", "K", "M", "G", "T"];
        const i = Math.floor(Math.log(bytes) / Math.log(1024));
        const p = Math.min(Math.max(0, i), units.length - 1);
        return (bytes / Math.pow(1024, p)).toFixed(1) + units[p];
    }

    function formatSpeed(bytesPerSec) {
        if (root.isPaused) return "PAUSED";
        if (!bytesPerSec || bytesPerSec <= 0) return "stalled";
        return formatBytes(bytesPerSec) + "/s";
    }

    function formatSpeedCompact(bytesPerSec) {
        if (root.isPaused) return "PAUSED";
        if (!bytesPerSec || bytesPerSec <= 0) return "0B/s";
        return formatBytesCompact(bytesPerSec) + "/s";
    }

    function formatEta() {
        if (root.isPaused) return "--";
        if (!root.totalSpeed || root.totalSpeed <= 0) return "--";
        const remain = Math.max(0, root.totalBytes - root.totalCompletedBytes);
        if (remain <= 0) return "0s";
        const s = Math.floor(remain / root.totalSpeed);
        if (s < 60) return s + "s";
        if (s < 3600) return Math.floor(s / 60) + "m";
        return Math.floor(s / 3600) + "h " + Math.floor((s % 3600) / 60) + "m";
    }

    readonly property string formattedHudText: {
        if (root.hudText && root.hudText.length > 0) return root.hudText;
        if (root.activeCount <= 0 && !root.isPaused) return "";
        const pct = Math.round(root.totalProgress * 100);
        const curSpd = root.isPaused ? "PAUSED" : root.formatSpeed(root.totalSpeed);
        const maxSpd = (!root.isPaused && root.sessionMaxSpeed > 0) ? (" ▲ " + root.formatSpeed(root.sessionMaxSpeed)) : "";
        const minSpd = (!root.isPaused && root.sessionMinSpeed > 0) ? (" ▼ " + root.formatSpeed(root.sessionMinSpeed)) : "";
        const speedText = curSpd + (maxSpd || minSpd ? (" (" + (maxSpd ? maxSpd.trim() : "") + (minSpd ? (" · " + minSpd.trim()) : "") + ")") : "");
        const doneText = root.totalBytes > 0 ? (" · " + root.formatBytes(root.totalCompletedBytes) + "/" + root.formatBytes(root.totalBytes)) : "";
        return "↓ " + root.activeCount + " · " + pct + "%" + doneText + " · " + speedText + (!root.isPaused ? (" · " + root.formatEta()) : "");
    }

    // Breathing pulse driven by MotionPacer (Theme.decorativeMaxFps) for 0% idle CPU
    MotionPacer {
        id: pulsePacer
        running: root.active && root.growthProgress > 0.01
        period: root.isPaused ? 3600 : Math.max(1200, Math.min(2800, Math.round(2800 / (1.0 + 2.0 * root.speedNorm))))
    }
    readonly property real pulse: pulsePacer.breath

    // Traveling packet motion: speed-modulated liveness (flows calmly when paused/stalled, accelerates with speed)
    MotionPacer {
        id: travelPacer
        running: root.active && root.growthProgress > 0.01
        period: root.travelDuration
    }
    readonly property real travelProgress: travelPacer.phase

    // Smooth entry / exit fade
    property real growthProgress: active ? 1.0 : 0.0
    Behavior on growthProgress {
        NumberAnimation {
            duration: (typeof Theme !== "undefined" && Theme.animDurationNormal) ? Theme.animDurationNormal : 300
            easing.type: Easing.BezierSpline
            easing.bezierCurve: (typeof Theme !== "undefined" && Theme.curveExpressiveDefaultSpatial) ? Theme.curveExpressiveDefaultSpatial : [0.38, 1.2, 0.24, 1.0, 1.0, 1.0]
        }
    }

    // Eased fill fraction (property changes at <=2/s; animation smooths)
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

    // Complete flash auto-clear (1.5s success hold)
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

    // Digital rain glyphs cycling via MotionClock (0% CPU when idle)
    property int matrixTick: 0
    readonly property var matrixGlyphs: [
        "0", "1", "7", "A", "F", "X", "9", "4", "Z", "8", "E", "C", "3", "5", "B", "D",
        "\uFF66", "\uFF71", "\uFF76", "\uFF7E", "\uFF82", "\uFF84", "\uFF89", "\uFF8D", "\uFF90", "\uFF97"
    ]

    property double lastRainMs: 0
    Connections {
        target: MotionClock
        function onTickChanged() {
            if (!root.active || root.growthProgress <= 0.01) {
                root.lastRainMs = MotionClock.elapsedMs;
                return;
            }
            const interval = Math.max(50, 110 - Math.round(root.speedNorm * 50));
            if (MotionClock.elapsedMs - root.lastRainMs < interval) return;
            root.lastRainMs = MotionClock.elapsedMs;
            root.matrixTick = (root.matrixTick + 1) % 10000;
        }
    }

    // =========================================================================
    // 1. TOP AMBIENT GLOW (Subtle Optical Bloom Contained to Frame Rim)
    // =========================================================================
    Item {
        id: topAmbientGlow
        anchors.right: parent.right
        anchors.top: parent.top
        width: Math.min(220, Math.max(140, 150 + root.speedNorm * 60))
        height: Math.min(140, Math.max(90, 100 + root.speedNorm * 40))
        z: 0

        opacity: root.growthProgress * (0.6 + 0.4 * root.pulse)
        Rectangle {
            anchors.fill: parent
            color: "transparent"
            gradient: Gradient {
                GradientStop { position: 0.0; color: root.safeAlpha(root.stateColor, 0.09) }
                GradientStop { position: 0.45; color: root.safeAlpha(root.stateColor, 0.03) }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }
    }

    // =========================================================================
    // 2. FUSED TOP-RIGHT NEXUS (Concave Inverted Fillet bridging top & right)
    // =========================================================================
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

            // Fused Glass Fill (Single continuous closed polygon wrapping around the concave curve)
            ShapePath {
                fillColor: root.safeAlpha(root.stateColor, 0.48 * (0.7 + 0.3 * root.pulse))
                strokeColor: "transparent"
                strokeWidth: 0
                startX: 0; startY: 0
                PathLine { x: fusedTopNexus.width; y: 0 }
                PathLine { x: fusedTopNexus.width; y: fusedTopNexus.height }
                PathLine { x: root.cornerFilletR; y: fusedTopNexus.height }
                PathArc {
                    x: 0
                    y: root.borderT
                    radiusX: root.cornerFilletR
                    radiusY: root.cornerFilletR
                    direction: PathArc.Counterclockwise
                }
                PathLine { x: 0; y: 0 }
            }

            // Continuous Specular Arc Stroke (1px hairline curving from right to top)
            ShapePath {
                fillColor: "transparent"
                strokeColor: Qt.lighter(root.stateColor, 1.25)
                strokeWidth: 1
                capStyle: ShapePath.FlatCap
                startX: root.cornerFilletR; startY: fusedTopNexus.height
                PathArc {
                    x: 0
                    y: root.borderT
                    radiusX: root.cornerFilletR
                    radiusY: root.cornerFilletR
                    direction: PathArc.Counterclockwise
                }
            }

            // Luminous Arc Flash when electric currents meet at the nexus
            ShapePath {
                fillColor: "transparent"
                strokeColor: {
                    const p1 = Math.max(0.0, Math.sin(Math.max(0.0, root.travelProgress - 0.70) / 0.30 * Math.PI));
                    const p2 = Math.max(0.0, Math.sin(Math.max(0.0, ((root.travelProgress + 0.50) % 1.0) - 0.70) / 0.30 * Math.PI));
                    return root.safeAlpha(root.stateColor, Math.max(p1, p2) * 0.75);
                }
                strokeWidth: 1.4
                capStyle: ShapePath.RoundCap
                startX: root.cornerFilletR; startY: fusedTopNexus.height
                PathArc {
                    x: 0
                    y: root.borderT
                    radiusX: root.cornerFilletR
                    radiusY: root.cornerFilletR
                    direction: PathArc.Counterclockwise
                }
            }

            // Prismatic chromatic corona halo when ingress converges at the nexus
            ShapePath {
                fillColor: "transparent"
                strokeColor: {
                    const p2 = Math.max(0.0, Math.sin(Math.max(0.0, ((root.travelProgress + 0.50) % 1.0) - 0.70) / 0.30 * Math.PI));
                    return root.safeAlpha(root.secondaryColor, p2 * 0.75);
                }
                strokeWidth: 3.5
                capStyle: ShapePath.RoundCap
                startX: root.cornerFilletR; startY: fusedTopNexus.height
                PathArc {
                    x: 0
                    y: root.borderT
                    radiusX: root.cornerFilletR
                    radiusY: root.cornerFilletR
                    direction: PathArc.Counterclockwise
                }
            }
        }
    }

    // =========================================================================
    // 3. TOP BORDER SECTION (Strictly 14px thickness, partitioned before nexus)
    // =========================================================================
    Rectangle {
        id: topBorderSection
        anchors.top: parent.top
        anchors.right: fusedTopNexus.left
        height: root.borderT
        width: Math.max(0, root.topWidth - (root.borderT + root.cornerFilletR))
        z: 1

        // Smooth horizontal color degradation merging into the nexus
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 0.30; color: root.safeAlpha(root.stateColor, 0.10) }
            GradientStop { position: 0.75; color: root.safeAlpha(root.stateColor, 0.26) }
            GradientStop { position: 1.0; color: root.safeAlpha(root.stateColor, 0.48 * (0.7 + 0.3 * root.pulse)) }
        }

        // Bottom 1px specular hairline (seamless light catch merging with desktop frame & corner arc)
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            z: 5
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.30; color: root.safeAlpha(root.stateColor, 0.45) }
                GradientStop { position: 0.75; color: root.safeAlpha(root.stateColor, 0.75) }
                GradientStop { position: 1.0; color: Qt.lighter(root.stateColor, 1.25) }
            }
        }

        // Soft electric glow halo (horizontal)
        Rectangle {
            id: topPacketGlow
            anchors.bottom: parent.bottom
            anchors.bottomMargin: -2
            height: 5
            width: Math.round(root.packetLength * 1.25)
            z: 20
            radius: 2.5
            color: "transparent"
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.50; color: root.safeAlpha(root.stateColor, 0.45 * (0.8 + 0.2 * root.pulse)) }
                GradientStop { position: 1.0; color: "transparent" }
            }
            x: Math.round(root.travelProgress * (topBorderSection.width - width))
        }

        // Traveling electric data packet (lead horizontal electric current towards corner)
        Rectangle {
            id: topPacket
            anchors.bottom: parent.bottom
            anchors.bottomMargin: -1
            width: root.packetLength
            height: 3
            z: 21
            radius: 1.5
            color: "transparent"
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.20; color: root.safeAlpha(root.stateColor, 0.85) }
                GradientStop { position: 0.50; color: "#FFFFFF" }
                GradientStop { position: 0.80; color: root.safeAlpha(root.stateColor, 0.85) }
                GradientStop { position: 1.0; color: "transparent" }
            }
            x: Math.round(root.travelProgress * (topBorderSection.width - width))
        }

        // Secondary interleaved traveling electric pulse (ensures continuous electrical flow)
        Rectangle {
            id: topPacketSecondary
            anchors.bottom: parent.bottom
            anchors.bottomMargin: -1
            width: Math.round(root.packetLength * 0.85)
            height: 3
            z: 21
            radius: 1.5
            color: "transparent"
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.25; color: root.safeAlpha(root.secondaryColor, 0.75) }
                GradientStop { position: 0.50; color: (root.activeCount > 1) ? "#FFFFFF" : Qt.lighter(root.secondaryColor, 1.30) }
                GradientStop { position: 0.75; color: root.safeAlpha(root.secondaryColor, 0.75) }
                GradientStop { position: 1.0; color: "transparent" }
            }
            x: Math.round(((root.travelProgress + 0.50) % 1.0) * (topBorderSection.width - width))
        }

        // =====================================================================
        // STREAMING DIGITAL CODE RAIN & EMBEDDED HUD CAPSULE
        // =====================================================================
        Row {
            id: matrixHorizontalTrack
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            anchors.rightMargin: 4
            spacing: 5
            z: 10

            // Trailing digital hex glyphs (left of HUD, fading outward)
            Repeater {
                model: 8
                delegate: Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.matrixGlyphs[(index * 3 + root.matrixTick) % root.matrixGlyphs.length]
                    font.family: (typeof Theme !== "undefined" && Theme.fontFamilyMonospace) ? Theme.fontFamilyMonospace : "monospace"
                    font.pixelSize: 9
                    font.weight: Font.Bold
                    color: {
                        const alpha = Math.min(0.85, Math.max(0.08, (index + 1) / 8 * 0.85));
                        return root.safeAlpha(root.stateColor, alpha * (0.8 + 0.2 * root.pulse));
                    }
                }
            }

            // Central High-Contrast Cyberpunk / Matrix HUD Capsule
            Item {
                id: hudSlot
                anchors.verticalCenter: parent.verticalCenter
                width: hudCapsule.width
                height: 12

                property string hudText: root.formattedHudText
                property bool hovered: false

                function openDownloads() {
                    if (typeof Config === "undefined") return;
                    Config.activeDashboardTab = "downloads";
                    Config.dashboardVisible = true;
                }

                Rectangle {
                    id: hudCapsule
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: 0.5
                    height: 12
                    width: hudRow.width + 10
                    radius: 3
                    color: root.safeAlpha("#0A090D", 0.88)
                    border.width: 1
                    border.color: root.safeAlpha(root.stateColor, hudSlot.hovered ? 0.90 : 0.45)

                    Behavior on border.color { ColorAnimation { duration: 150 } }

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
                            color: Qt.lighter(root.stateColor, 1.35)
                        }

                        // Download Direction Glyph (static when paused, pulsing when active)
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "↓"
                            font.family: (typeof Theme !== "undefined" && Theme.fontFamilyMonospace) ? Theme.fontFamilyMonospace : "monospace"
                            font.pixelSize: 10
                            font.bold: true
                            color: root.stateColor
                            scale: (root.active && !root.isPaused && root.totalSpeed > 0)
                                ? (0.92 + (root.pulse * 0.16))
                                : 1.0
                        }

                        // Prominent Visual Progress Bar Pill (High human visibility)
                        Item {
                            id: progressBarContainer
                            anchors.verticalCenter: parent.verticalCenter
                            width: 52
                            height: 6

                            // Progress Track
                            Rectangle {
                                anchors.fill: parent
                                radius: 2
                                color: root.safeAlpha("#FFFFFF", 0.14)
                            }

                            // Glowing Progress Fill (Liquid gradient)
                            Rectangle {
                                id: progressBar
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                x: root.indeterminate
                                    ? Math.round(root.travelProgress * (progressBarContainer.width - width))
                                    : 0
                                width: root.indeterminate
                                    ? Math.round(parent.width * 0.35)
                                    : Math.max(0, Math.min(parent.width, Math.round(parent.width * root.fillProgress)))
                                radius: 2
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0.0; color: root.safeAlpha(root.stateColor, 0.40) }
                                    GradientStop { position: 0.85; color: root.safeAlpha(root.stateColor, 0.85) }
                                    GradientStop { position: 1.0; color: "#FFFFFF" }
                                }
                            }

                            // High-contrast specular glowing pip at leading edge
                            Rectangle {
                                id: progressPip
                                visible: !root.indeterminate && root.fillProgress > 0.02 && root.fillProgress < 0.98
                                anchors.verticalCenter: parent.verticalCenter
                                x: Math.max(0, Math.min(progressBarContainer.width - width, Math.round(progressBarContainer.width * root.fillProgress - (width / 2))))
                                width: 3
                                height: 4
                                radius: 1.5
                                color: "#FFFFFF"
                                border.width: 1
                                border.color: root.stateColor
                            }
                        }

                        // Bold Readable Percentage / Status Badge
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: {
                                if (root.showCompleteFlash) return "100%";
                                if (root.hasError) return "ERROR";
                                if (root.indeterminate) return "SYNC";
                                return Math.round(root.totalProgress * 100) + "%";
                            }
                            font.family: (typeof Theme !== "undefined" && Theme.fontFamilyMonospace) ? Theme.fontFamilyMonospace : "monospace"
                            font.pixelSize: 9
                            font.bold: true
                            font.letterSpacing: 0.2
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
                            color: root.safeAlpha(root.stateColor, 0.85)
                        }

                        // Speed / Paused Badge
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: {
                                if (root.isPaused) return "PAUSED";
                                return root.totalSpeed > 0 ? root.formatSpeed(root.totalSpeed) : "stalled";
                            }
                            font.family: (typeof Theme !== "undefined" && Theme.fontFamilyMonospace) ? Theme.fontFamilyMonospace : "monospace"
                            font.pixelSize: 9
                            font.bold: true
                            color: root.isPaused
                                ? Qt.lighter("#fbbf24", 1.15)
                                : Qt.lighter(root.stateColor, 1.25)
                            style: Text.Outline
                            styleColor: Qt.rgba(0.0, 0.0, 0.0, 0.50)
                        }

                        // 3-Bar Digital Equalizer Activity Pulses (active when downloading)
                        Row {
                            spacing: 2
                            anchors.verticalCenter: parent.verticalCenter
                            visible: root.totalSpeed > 0 && !root.isPaused

                            Rectangle {
                                width: 2
                                height: Math.min(6, Math.max(2, 3 + Math.round(3 * Math.abs(Math.sin(root.pulse * Math.PI)) * Math.min(1.2, Math.max(0.6, root.speedNorm * 1.5)))))
                                color: root.stateColor
                                radius: 0.5
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Rectangle {
                                width: 2
                                height: Math.min(6, Math.max(2, 3 + Math.round(4 * Math.abs(Math.cos(root.pulse * Math.PI)) * Math.min(1.2, Math.max(0.6, root.speedNorm * 1.5)))))
                                color: Qt.lighter(root.stateColor, 1.30)
                                radius: 0.5
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Rectangle {
                                width: 2
                                height: Math.min(6, Math.max(2, 2 + Math.round(3 * Math.abs(Math.sin((root.pulse + 0.5) * Math.PI)) * Math.min(1.2, Math.max(0.6, root.speedNorm * 1.5)))))
                                color: root.stateColor
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
            }

            // Leading Head Matrix Glyphs (Right side, glowing intense phosphor white & stateColor into corner)
            Repeater {
                model: 6
                delegate: Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: 0.5
                    text: root.matrixGlyphs[(index * 5 + root.matrixTick + 5) % root.matrixGlyphs.length]
                    font.family: (typeof Theme !== "undefined" && Theme.fontFamilyMonospace) ? Theme.fontFamilyMonospace : "monospace"
                    font.pixelSize: 9
                    font.weight: (index >= 4) ? Font.Black : Font.Bold
                    color: (index >= 4) ? "#FFFFFF" : Qt.lighter(root.stateColor, 1.25)
                    style: Text.Outline
                    styleColor: Qt.rgba(0.0, 0.0, 0.0, 0.40)
                }
            }
        }
    }

    // =========================================================================
    // 4. RIGHT-TOP LEG (Strictly 14px thickness, partitioned below nexus)
    // =========================================================================
    Rectangle {
        id: rightTopSection
        anchors.right: parent.right
        anchors.top: fusedTopNexus.bottom
        width: root.borderT
        height: Math.max(0, root.rightHeight - (root.borderT + root.cornerFilletR))
        z: 1

        // Smooth vertical color degradation
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: root.safeAlpha(root.stateColor, 0.48 * (0.7 + 0.3 * root.pulse)) }
            GradientStop { position: 0.50; color: root.safeAlpha(root.stateColor, 0.20) }
            GradientStop { position: 1.0; color: "transparent" }
        }

        // Left 1px specular hairline (continuous vertical light catch)
        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 1
            z: 5
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0.0; color: Qt.lighter(root.stateColor, 1.25) }
                GradientStop { position: 0.60; color: root.safeAlpha(root.stateColor, 0.55) }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }

        // Soft electric glow halo (vertical)
        Rectangle {
            id: rightPacketGlow
            x: -2
            width: 5
            height: Math.round(root.packetLength * 1.25)
            z: 20
            radius: 2.5
            color: "transparent"
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.50; color: root.safeAlpha(root.stateColor, 0.45 * (0.8 + 0.2 * root.pulse)) }
                GradientStop { position: 1.0; color: "transparent" }
            }
            y: Math.round((1.0 - root.travelProgress) * (rightTopSection.height - height))
        }

        // Traveling digital data packet (lead vertical electric current) across the 1px specular border
        Rectangle {
            id: rightPacket
            x: -1
            width: 3
            height: root.packetLength
            z: 21
            radius: 1.5
            color: "transparent"
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.20; color: root.safeAlpha(root.stateColor, 0.85) }
                GradientStop { position: 0.50; color: "#FFFFFF" }
                GradientStop { position: 0.80; color: root.safeAlpha(root.stateColor, 0.85) }
                GradientStop { position: 1.0; color: "transparent" }
            }
            y: Math.round((1.0 - root.travelProgress) * (rightTopSection.height - height))
        }

        // Interleaved trailing secondary vertical electric pulse (ensures continuous electrical flow)
        Rectangle {
            id: rightPacketSecondary
            x: -1
            width: 3
            height: Math.round(root.packetLength * 0.85)
            z: 21
            radius: 1.5
            color: "transparent"
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.25; color: root.safeAlpha(root.secondaryColor, 0.75) }
                GradientStop { position: 0.50; color: (root.activeCount > 1) ? "#FFFFFF" : Qt.lighter(root.secondaryColor, 1.30) }
                GradientStop { position: 0.75; color: root.safeAlpha(root.secondaryColor, 0.75) }
                GradientStop { position: 1.0; color: "transparent" }
            }
            y: Math.round((1.0 - ((root.travelProgress + 0.50) % 1.0)) * (rightTopSection.height - height))
        }

        // Vertical matrix digital rain falling downward
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 4
            spacing: 2
            z: 10

            Repeater {
                model: 10
                delegate: Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.matrixGlyphs[(index * 7 + root.matrixTick + 3) % root.matrixGlyphs.length]
                    font.family: (typeof Theme !== "undefined" && Theme.fontFamilyMonospace) ? Theme.fontFamilyMonospace : "monospace"
                    font.pixelSize: 9
                    font.weight: (index <= 2) ? Font.Black : Font.Bold
                    color: {
                        if (index <= 1) {
                            return "#FFFFFF";
                        } else if (index <= 4) {
                            return Qt.lighter(root.stateColor, 1.25);
                        } else {
                            const alpha = Math.max(0.10, (10 - index) / 10 * 0.75);
                            return root.safeAlpha(root.stateColor, alpha);
                        }
                    }
                }
            }
        }
    }
}
