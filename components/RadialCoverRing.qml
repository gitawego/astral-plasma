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

    // Gentle idle wave phase when playing without audio stream. Capped at
    // Theme.decorativeMaxFps so the full-screen shell surfaces stay idle-capable.
    MotionPacer {
        id: idlePacer
        running: root.isPlaying && root.isTargetVisible
        period: 3500
    }
    readonly property real idlePhase: idlePacer.phase * Math.PI * 2

    // Smoothed bar values (0..1), advanced once per painted frame.
    property var barLevels: []
    // Fraction of the remaining distance a bar covers per frame: the 75 ms
    // OutQuad feel the removed `Behavior on height` had at the clock's 30 fps.
    readonly property real levelEase: 0.45

    function getBarValue(idx) {
        if (!root.isPlaying) return 0.0;

        if (root.isVisualizerActive && AudioVisualizer.displayBands && AudioVisualizer.displayBands.length > 0) {
            let bandIdx = Math.floor((idx / root.barsCount) * 16);
            let raw = AudioVisualizer.displayBands[bandIdx] || 0.0;
            let boosted = raw * (0.8 + root.audioEnergy * 0.5 + root.audioBeat * 0.3);
            return Math.max(0.0, Math.min(1.0, boosted));
        }

        // Idle wave animation
        let wave = Math.sin(root.idlePhase + idx * 0.45) * 0.3 + 0.3;
        return Math.max(0.0, Math.min(0.7, wave));
    }

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
            const col = (typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#a8c7fa";
            const levels = root.barLevels;
            const next = [];

            ctx.lineCap = "round";
            ctx.lineWidth = root.barWidth;

            for (let i = 0; i < count; ++i) {
                const target = root.getBarValue(i);
                const previous = (levels[i] !== undefined) ? levels[i] : target;
                const level = (root.isPlaying && root.isTargetVisible)
                    ? previous + (target - previous) * root.levelEase
                    : target;
                next.push(level);

                const angle = (i * 2 * Math.PI) / count - Math.PI / 2;
                const cosA = Math.cos(angle);
                const sinA = Math.sin(angle);
                const length = root.baseBarHeight + level * root.maxBarHeight;

                ctx.globalAlpha = root.isPlaying ? (0.7 + level * 0.3) : 0.25;
                ctx.strokeStyle = Qt.rgba(col.r, col.g, col.b, 1.0);
                ctx.beginPath();
                ctx.moveTo(cx + cosA * inner, cy + sinA * inner);
                ctx.lineTo(cx + cosA * (inner + length), cy + sinA * (inner + length));
                ctx.stroke();
            }

            ctx.globalAlpha = 1.0;
            root.barLevels = next;
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
