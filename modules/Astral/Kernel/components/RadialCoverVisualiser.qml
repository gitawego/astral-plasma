import QtQuick
import QtQuick.Effects
import "motion"
import "../theme"
import "../services"
import "../config"

Item {
    id: root

    property bool isPlaying: (typeof MprisMedia !== "undefined" && MprisMedia) ? MprisMedia.isPlaying : false
    property string artUrl: (typeof MprisMedia !== "undefined" && MprisMedia) ? MprisMedia.artUrl : ""
    property string title: (typeof MprisMedia !== "undefined" && MprisMedia) ? MprisMedia.title : ""
    property string artist: (typeof MprisMedia !== "undefined" && MprisMedia) ? MprisMedia.artist : ""
    property bool isTargetVisible: (typeof Config !== "undefined")
        ? (Config.dashboardVisible && Config.activeDashboardTab === "media")
        : true

    implicitWidth: 240
    implicitHeight: 240

    readonly property int barsCount: 48
    readonly property real coverRadius: 58
    readonly property real barSpacing: 7
    readonly property real barWidth: 3
    readonly property real baseBarHeight: 4
    readonly property real maxBarHeight: 32

    // Audio reactivity
    readonly property bool isVisualizerActive: (typeof AudioVisualizer !== "undefined" && AudioVisualizer && AudioVisualizer.active === true)
    readonly property real audioEnergy: (isVisualizerActive && root.isTargetVisible && root.isPlaying) ? AudioVisualizer.displayEnergy : 0.0
    readonly property real audioBeat: (isVisualizerActive && root.isTargetVisible && root.isPlaying) ? AudioVisualizer.displayBeat : 0.0

    // Clock pacer for smooth continuous bar interpolation when active audio flows.
    // Capped at Theme.decorativeMaxFps so full-screen surfaces stay idle-capable.
    MotionPacer {
        id: audioPacer
        running: root.isPlaying && root.isTargetVisible && root.isVisualizerActive && root.audioEnergy > 0.005
        period: 4000
    }

    // Smoothed bar values (0..1) and their brightness, advanced once per painted
    // frame - the presentation smoothing the removed per-bar Behaviors provided.
    property var barLevels: []
    property var barAlphas: []
    readonly property real levelEase: 0.45
    readonly property real alphaEase: 0.22

    // The cover's beat pulse: eased on the shared clock instead of the removed
    // 90 ms `Behavior on scale`, so it swells rather than snapping between frames.
    MotionValue {
        id: coverPulse
        animated: root.isPlaying && root.isTargetVisible
        duration: 80
        bezier: (typeof Theme !== "undefined" && Theme.curveExpressiveFastEffects) ? Theme.curveExpressiveFastEffects : null
        target: (root.isPlaying && root.isTargetVisible && root.audioBeat > 0.08)
            ? (1.0 + Math.min(0.04, root.audioBeat * 0.06))
            : 1.0
    }

    function getBarValue(idx) {
        if (!root.isPlaying || !root.isVisualizerActive || !AudioVisualizer.displayBands || AudioVisualizer.displayBands.length === 0) {
            return 0.0;
        }

        // Map 48 bars into 16 bands symmetrically (bass at sides/bottom, highs across)
        let bandIdx = Math.floor((idx / root.barsCount) * 16);
        let raw = AudioVisualizer.displayBands[bandIdx] || 0.0;
        let boosted = raw * (0.8 + root.audioEnergy * 0.5 + (root.audioBeat > 0.05 ? root.audioBeat * 0.3 : 0.0));
        return Math.max(0.0, Math.min(1.0, boosted));
    }

    readonly property bool isCyberStyle: (typeof Theme !== "undefined" && (Theme.isCyberpunk || Theme.mediaCoverStyle === "cyber_radial"))

    // 1. Radial Audio Visualizer Bars
    //
    // One Canvas on the shared clock instead of 48 Items each owning a Qt
    // animation that the 30 fps band stream re-triggered before it could finish
    // (see RadialCoverRing and docs/LESSONS.md 34).
    Canvas {
        id: barsCanvas
        anchors.fill: parent
        antialiasing: true

        onPaint: {
            const ctx = getContext("2d");
            const w = width;
            const h = height;
            ctx.clearRect(0, 0, w, h);
            if (w <= 0 || h <= 0) {
                return;
            }

            const count = root.barsCount;
            const cx = w / 2;
            const cy = h / 2;
            const inner = root.coverRadius + root.barSpacing;
            const col = (typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : Qt.color("#a8c7fa");
            const secCol = (typeof Colors !== "undefined" && Colors.secondary) ? Colors.secondary : Qt.color("#ff007f");
            const levels = root.barLevels;
            const alphas = root.barAlphas;
            const next = [];
            const nextAlphas = [];
            const cyber = root.isCyberStyle;

            // Cyberpunk HUD inner laser track & cardinal reticle ticks
            if (cyber) {
                // Continuous laser track ring
                ctx.beginPath();
                ctx.arc(cx, cy, inner - 1.5, 0, 2 * Math.PI);
                ctx.strokeStyle = Qt.rgba(col.r, col.g, col.b, 0.40 + root.audioEnergy * 0.40);
                ctx.lineWidth = 1;
                ctx.stroke();

                // 4 cardinal reticle ticks
                const tickLen = 4;
                for (let k = 0; k < 4; ++k) {
                    const tAngle = (k * Math.PI) / 2;
                    const cosT = Math.cos(tAngle);
                    const sinT = Math.sin(tAngle);
                    ctx.beginPath();
                    ctx.moveTo(cx + cosT * (inner - tickLen), cy + sinT * (inner - tickLen));
                    ctx.lineTo(cx + cosT * (inner + 1), cy + sinT * (inner + 1));
                    ctx.strokeStyle = Qt.rgba(col.r, col.g, col.b, 0.75);
                    ctx.lineWidth = 1.5;
                    ctx.stroke();
                }
            }

            ctx.lineCap = cyber ? "butt" : "round";
            ctx.lineWidth = root.barWidth;

            for (let i = 0; i < count; ++i) {
                const target = root.getBarValue(i);
                const previous = (levels[i] !== undefined) ? levels[i] : target;
                const level = (root.isPlaying && root.isTargetVisible)
                    ? previous + (target - previous) * root.levelEase
                    : target;
                next.push(level);

                const targetAlpha = root.isPlaying ? (0.65 + level * 0.35) : (cyber ? 0.4 : 0.3);
                const previousAlpha = (alphas[i] !== undefined) ? alphas[i] : targetAlpha;
                const alpha = (root.isPlaying && root.isTargetVisible)
                    ? previousAlpha + (targetAlpha - previousAlpha) * root.alphaEase
                    : targetAlpha;
                nextAlphas.push(alpha);

                const angle = (i * 2 * Math.PI) / count - Math.PI / 2;
                const cosA = Math.cos(angle);
                const sinA = Math.sin(angle);
                const length = root.baseBarHeight + level * root.maxBarHeight;

                const x0 = cx + cosA * inner;
                const y0 = cy + sinA * inner;
                const x1 = cx + cosA * (inner + length);
                const y1 = cy + sinA * (inner + length);

                ctx.globalAlpha = alpha;

                if (cyber) {
                    // Dual-color cyber gradient: Cyan (#00F0FF) to Neon Magenta (#FF007F) at peak
                    const grad = ctx.createLinearGradient(x0, y0, x1, y1);
                    grad.addColorStop(0, Qt.rgba(col.r, col.g, col.b, 1.0));
                    const tipMix = Math.min(1.0, level * 1.5);
                    const tipR = col.r + (secCol.r - col.r) * tipMix;
                    const tipG = col.g + (secCol.g - col.g) * tipMix;
                    const tipB = col.b + (secCol.b - col.b) * tipMix;
                    grad.addColorStop(1, Qt.rgba(tipR, tipG, tipB, 1.0));

                    ctx.strokeStyle = grad;
                    ctx.beginPath();
                    ctx.moveTo(x0, y0);
                    ctx.lineTo(x1, y1);
                    ctx.stroke();

                    // Floating neon peak cap tick for high-energy bursts
                    if (level > 0.35 && root.isPlaying) {
                        const peakDist = inner + length + 2.5;
                        const capLen = 1.5;
                        ctx.beginPath();
                        ctx.moveTo(cx + cosA * peakDist, cy + sinA * peakDist);
                        ctx.lineTo(cx + cosA * (peakDist + capLen), cy + sinA * (peakDist + capLen));
                        ctx.strokeStyle = Qt.rgba(secCol.r, secCol.g, secCol.b, Math.min(1.0, level * 1.3));
                        ctx.lineWidth = root.barWidth;
                        ctx.stroke();
                    }
                } else {
                    ctx.strokeStyle = Qt.rgba(col.r, col.g, col.b, 1.0);
                    ctx.beginPath();
                    ctx.moveTo(x0, y0);
                    ctx.lineTo(x1, y1);
                    ctx.stroke();
                }
            }

            ctx.globalAlpha = 1.0;
            root.barLevels = next;
            root.barAlphas = nextAlphas;
        }
    }

    MotionTick {
        running: root.isPlaying && root.isTargetVisible
        onTicked: barsCanvas.requestPaint()
    }

    onIsPlayingChanged: barsCanvas.requestPaint()
    onIsTargetVisibleChanged: barsCanvas.requestPaint()
    Component.onCompleted: barsCanvas.requestPaint()

    // Circular Mask for MultiEffect
    Rectangle {
        id: coverCircleMask
        width: root.coverRadius * 2
        height: root.coverRadius * 2
        radius: width / 2
        color: "black"
        visible: false
        layer.enabled: true
    }

    // 2. Circular Album Art with Beat Pulse & Mask
    Item {
        id: coverWrapper
        width: root.coverRadius * 2
        height: root.coverRadius * 2
        anchors.centerIn: parent

        scale: coverPulse.value

        // presentation smoothing removed: these values already arrive at
        // Theme.decorativeMaxFps (see AudioVisualizer.display*); a Behavior
        // here re-animated them at display refresh and never finished


        // Content layer masked to circle
        Item {
            id: coverArtContent
            anchors.fill: parent
            layer.enabled: true
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: coverCircleMask
            }

            // Fallback placeholder background & icon
            Rectangle {
                anchors.fill: parent
                color: Colors.surfaceContainerHighest

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "music_note"
                    size: 42
                    color: Colors.onSurfaceVariant
                    visible: !albumImage.visible || albumImage.status !== Image.Ready
                }
            }

            // Album Art Image
            Image {
                id: albumImage
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                source: root.artUrl
                asynchronous: true
                smooth: true
                mipmap: true
                visible: root.artUrl !== "" && status === Image.Ready
            }
        }

        // Circular Glass / Cyber Border Ring
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "transparent"
            border.color: root.isCyberStyle ? Colors.primary : Colors.glassBorderSubtle
            border.width: 1.5
        }
    }

    // ==========================================
    // 3. Cyber HUD Corner Brackets & Telemetry
    // ==========================================
    Item {
        id: cyberHudFrame
        anchors.fill: parent
        visible: root.isCyberStyle

        // Top-Left Bracket
        Item {
            anchors.top: parent.top
            anchors.left: parent.left
            width: 10; height: 10
            Rectangle { anchors.top: parent.top; anchors.left: parent.left; width: 10; height: 1; color: Colors.primary }
            Rectangle { anchors.top: parent.top; anchors.left: parent.left; width: 1; height: 10; color: Colors.primary }
        }

        // Top-Right Bracket
        Item {
            anchors.top: parent.top
            anchors.right: parent.right
            width: 10; height: 10
            Rectangle { anchors.top: parent.top; anchors.right: parent.right; width: 10; height: 1; color: Colors.primary }
            Rectangle { anchors.top: parent.top; anchors.right: parent.right; width: 1; height: 10; color: Colors.primary }
        }

        // Bottom-Left Bracket
        Item {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            width: 10; height: 10
            Rectangle { anchors.bottom: parent.bottom; anchors.left: parent.left; width: 10; height: 1; color: Colors.primary }
            Rectangle { anchors.bottom: parent.bottom; anchors.left: parent.left; width: 1; height: 10; color: Colors.primary }
        }

        // Bottom-Right Bracket
        Item {
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            width: 10; height: 10
            Rectangle { anchors.bottom: parent.bottom; anchors.right: parent.right; width: 10; height: 1; color: Colors.primary }
            Rectangle { anchors.bottom: parent.bottom; anchors.right: parent.right; width: 1; height: 10; color: Colors.primary }
        }

        // Micro Telemetry Tags
        Text {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.margins: 4
            text: "RADIAL // 48K"
            font.family: (typeof Theme !== "undefined") ? Theme.fontMonospace : "monospace"
            font.pixelSize: 8
            font.weight: Font.DemiBold
            color: Qt.alpha(Colors.primary, 0.70)
        }

        Text {
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            anchors.margins: 4
            text: "EQ // [20Hz - 20kHz]"
            font.family: (typeof Theme !== "undefined") ? Theme.fontMonospace : "monospace"
            font.pixelSize: 8
            font.weight: Font.DemiBold
            color: Qt.alpha(Colors.primary, 0.70)
        }
    }
}
