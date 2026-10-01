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

    // Gentle idle wave phase when playing without audio stream. Capped at
    // Theme.decorativeMaxFps: a playing track would otherwise keep the whole
    // shell rendering at display refresh (165–240 Hz) while the media UI is up.
    MotionPacer {
        id: idlePacer
        running: root.isPlaying && root.isTargetVisible
        period: 3500
    }
    readonly property real idlePhase: idlePacer.phase * Math.PI * 2

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
        if (!root.isPlaying) return 0.0;

        if (root.isVisualizerActive && AudioVisualizer.displayBands && AudioVisualizer.displayBands.length > 0) {
            // Map 48 bars into 16 bands symmetrically (bass at sides/bottom, highs across)
            let bandIdx = Math.floor((idx / root.barsCount) * 16);
            let raw = AudioVisualizer.displayBands[bandIdx] || 0.0;
            let boosted = raw * (0.8 + root.audioEnergy * 0.5 + root.audioBeat * 0.3);
            return Math.max(0.0, Math.min(1.0, boosted));
        }

        // Idle sine wave animation when playing
        let wave = Math.sin(root.idlePhase + idx * 0.38) * 0.3 + 0.3;
        return Math.max(0.0, Math.min(0.7, wave));
    }

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
            const col = (typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#a8c7fa";
            const levels = root.barLevels;
            const alphas = root.barAlphas;
            const next = [];
            const nextAlphas = [];

            ctx.lineCap = "round";
            ctx.lineWidth = root.barWidth;

            for (let i = 0; i < count; ++i) {
                const target = root.getBarValue(i);
                const previous = (levels[i] !== undefined) ? levels[i] : target;
                const level = (root.isPlaying && root.isTargetVisible)
                    ? previous + (target - previous) * root.levelEase
                    : target;
                next.push(level);

                const targetAlpha = root.isPlaying ? (0.65 + level * 0.35) : 0.3;
                const previousAlpha = (alphas[i] !== undefined) ? alphas[i] : targetAlpha;
                const alpha = (root.isPlaying && root.isTargetVisible)
                    ? previousAlpha + (targetAlpha - previousAlpha) * root.alphaEase
                    : targetAlpha;
                nextAlphas.push(alpha);

                const angle = (i * 2 * Math.PI) / count - Math.PI / 2;
                const cosA = Math.cos(angle);
                const sinA = Math.sin(angle);
                const length = root.baseBarHeight + level * root.maxBarHeight;

                ctx.globalAlpha = alpha;
                ctx.strokeStyle = Qt.rgba(col.r, col.g, col.b, 1.0);
                ctx.beginPath();
                ctx.moveTo(cx + cosA * inner, cy + sinA * inner);
                ctx.lineTo(cx + cosA * (inner + length), cy + sinA * (inner + length));
                ctx.stroke();
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

        // Circular Glass Border Ring
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "transparent"
            border.color: Colors.glassBorderSubtle
            border.width: 1.5
        }
    }
}
