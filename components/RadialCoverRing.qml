import QtQuick
import "motion"
import "../theme"
import "../services"
import "../config"

// ============================================================================
// RadialCoverRing — 40 spectrum bars around the album cover
// ============================================================================
// Drawn into one Canvas that repaints on the shared decorative clock.
//
// It used to be a Repeater of 40 Items, each owning `Behavior on height` (75 ms)
// and `Behavior on opacity` (200 ms). The band stream re-triggered both before
// they could finish, so the ring ran 80 animations that never ended, at display
// refresh, for as long as the dashboard was open — ~25 % of a CPU core on its own
// (see docs/LESSONS.md 32/34). One canvas at `Theme.decorativeMaxFps` draws the
// same ring, and a stopped ring repaints once and then holds no clock at all.
//
// The smoothing that the Behaviors provided is kept, computed per painted frame -
// presentation only. The values themselves are still real stream data.
Item {
    id: root

    property real innerRadius: 58
    property bool isTargetVisible: true
    property bool isPlaying: (typeof MprisMedia !== "undefined" && MprisMedia) ? MprisMedia.isPlaying : false

    implicitWidth: (innerRadius + maxBarHeight + barSpacing) * 2 + 10
    implicitHeight: implicitWidth
    width: implicitWidth
    height: implicitHeight

    readonly property int barsCount: 40
    readonly property real barSpacing: 2
    readonly property real baseBarHeight: 2.5
    readonly property real maxBarHeight: 11
    readonly property real barWidth: 2.5

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
    // frame - the presentation smoothing the removed per-bar Behaviors provided
    // (75 ms for height, 200 ms for opacity).
    property var barLevels: []
    property var barAlphas: []
    readonly property real levelEase: 0.45
    readonly property real alphaEase: 0.22

    function getBarValue(idx) {
        if (!root.isPlaying || !root.isVisualizerActive || !AudioVisualizer.displayBands || AudioVisualizer.displayBands.length === 0) {
            return 0.0;
        }

        let bandIdx = Math.floor((idx / root.barsCount) * 16);
        let raw = AudioVisualizer.displayBands[bandIdx] || 0.0;
        let boosted = raw * (0.8 + root.audioEnergy * 0.5 + (root.audioBeat > 0.05 ? root.audioBeat * 0.3 : 0.0));
        return Math.max(0.0, Math.min(1.0, boosted));
    }

    readonly property bool isCyberStyle: (typeof Theme !== "undefined" && (Theme.isCyberpunk || Theme.mediaCoverStyle === "cyber_radial"))

    Canvas {
        id: ring
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
            const inner = root.innerRadius + root.barSpacing;
            const col = (typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : Qt.color("#a8c7fa");
            const secCol = (typeof Colors !== "undefined" && Colors.secondary) ? Colors.secondary : Qt.color("#ff007f");
            const levels = root.barLevels;
            const alphas = root.barAlphas;
            const next = [];
            const nextAlphas = [];
            const cyber = root.isCyberStyle;

            // Cyberpunk HUD inner laser track & cardinal reticle ticks
            if (cyber) {
                ctx.beginPath();
                ctx.arc(cx, cy, inner - 1.5, 0, 2 * Math.PI);
                ctx.strokeStyle = Qt.rgba(col.r, col.g, col.b, 0.40 + root.audioEnergy * 0.40);
                ctx.lineWidth = 1;
                ctx.stroke();

                // 4 cardinal reticle ticks
                const tickLen = 3;
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

                // Brightness eases slower than the bar grows, as the 200 ms
                // opacity Behavior did against the 75 ms height Behavior.
                const targetAlpha = root.isPlaying ? (0.7 + level * 0.3) : (cyber ? 0.4 : 0.25);
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
                        const peakDist = inner + length + 2;
                        const capLen = 1.2;
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

    // One repaint per decorative frame while the ring is actually live; nothing
    // at all when it is stopped or hidden.
    MotionTick {
        running: root.isPlaying && root.isTargetVisible
        onTicked: ring.requestPaint()
    }

    onIsPlayingChanged: ring.requestPaint()
    onIsTargetVisibleChanged: ring.requestPaint()
    Component.onCompleted: ring.requestPaint()
}
