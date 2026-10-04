import QtQuick
import "../theme"
import "../services"
import "../config"

Item {
    id: root

    property bool isTargetVisible: true
    property real lineWidth: 1.5
    property color waveColor: Colors.primary
    property color gridColor: Qt.alpha(Colors.primary, 0.12)
    property bool showGrid: true
    property bool showAreaFill: true
    property string mode: "oscilloscope" // "oscilloscope" | "spectrum"

    readonly property bool isPlaying: (typeof MprisMedia !== "undefined" && MprisMedia) ? MprisMedia.isPlaying : false
    readonly property bool isVisualizerActive: (typeof AudioVisualizer !== "undefined" && AudioVisualizer && AudioVisualizer.active === true)

    // Substrate background: OLED black with subtle high-contrast border
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0.01, 0.02, 0.04, 0.90)
        border.color: Qt.alpha(Colors.primary, 0.35)
        border.width: 1
    }

    // Oscilloscope canvas drawing the cyber grid and real-time audio wave
    Canvas {
        id: oscCanvas
        anchors.fill: parent
        anchors.margins: 1

        Connections {
            target: (typeof AudioVisualizer !== "undefined") ? AudioVisualizer : null
            function onFrameUpdated() {
                if (root.isTargetVisible && root.isPlaying && root.isVisualizerActive) {
                    oscCanvas.requestPaint();
                }
            }
            function onBandsChanged() {
                if (root.isTargetVisible && root.isPlaying && root.isVisualizerActive) {
                    oscCanvas.requestPaint();
                }
            }
            function onActiveChanged() {
                oscCanvas.requestPaint();
            }
        }

        Connections {
            target: root
            function onIsPlayingChanged() { oscCanvas.requestPaint(); }
            function onIsTargetVisibleChanged() { oscCanvas.requestPaint(); }
        }

        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();

            var w = width;
            var h = height;
            var midY = h / 2;

            // 1. Draw subtle cyber grid
            if (root.showGrid) {
                ctx.strokeStyle = root.gridColor;
                ctx.lineWidth = 1;
                ctx.beginPath();

                // Center baseline
                ctx.moveTo(0, midY);
                ctx.lineTo(w, midY);

                // Vertical grid lines every 24px
                for (var gx = 24; gx < w; gx += 24) {
                    ctx.moveTo(gx, 0);
                    ctx.lineTo(gx, h);
                }
                ctx.stroke();
            }

            var bands = (typeof AudioVisualizer !== "undefined" && AudioVisualizer.displayBands) ? AudioVisualizer.displayBands : [];
            var isSilent = !root.isPlaying || !root.isVisualizerActive || bands.length === 0;

            // If silent, draw flat baseline and exit
            if (isSilent) {
                ctx.strokeStyle = Qt.alpha(root.waveColor, 0.35);
                ctx.lineWidth = root.lineWidth;
                ctx.beginPath();
                ctx.moveTo(0, midY);
                ctx.lineTo(w, midY);
                ctx.stroke();
                return;
            }

            // 2. Generate smooth points from physical FFT frequency bands
            var points = [];
            var numPoints = 24;
            var maxAmp = (h / 2) - 3;
            var beat = (typeof AudioVisualizer !== "undefined") ? (AudioVisualizer.displayBeat || 0.0) : 0.0;

            if (root.mode === "spectrum") {
                // Unipolar spectrum mode: rises from bottom (h - 2) upward
                var baselineY = h - 2;
                points.push({ x: 0, y: baselineY });
                for (var si = 0; si <= 16; si++) {
                    var sx = (si / 16) * w;
                    var bIdx = Math.min(15, si);
                    var bVal = bands[bIdx] || 0.0;
                    var sy = Math.max(3, baselineY - (bVal * (h - 6)));
                    points.push({ x: sx, y: sy });
                }
                points.push({ x: w, y: baselineY });

                if (root.showAreaFill) {
                    var sGrad = ctx.createLinearGradient(0, 0, 0, h);
                    sGrad.addColorStop(0.0, Qt.alpha(root.waveColor, 0.40));
                    sGrad.addColorStop(0.6, Qt.alpha(root.waveColor, 0.12));
                    sGrad.addColorStop(1.0, Qt.alpha(root.waveColor, 0.02));
                    ctx.fillStyle = sGrad;
                    ctx.beginPath();
                    ctx.moveTo(points[0].x, points[0].y);
                    for (var sp = 1; sp < points.length; sp++) {
                        ctx.lineTo(points[sp].x, points[sp].y);
                    }
                    ctx.closePath();
                    ctx.fill();
                }

                ctx.shadowColor = root.waveColor;
                ctx.shadowBlur = 5;
                ctx.strokeStyle = root.waveColor;
                ctx.lineWidth = root.lineWidth;
                ctx.beginPath();
                ctx.moveTo(points[1].x, points[1].y);
                for (var sk = 2; sk < points.length - 1; sk++) {
                    var sxc = (points[sk].x + points[sk - 1].x) / 2;
                    var syc = (points[sk].y + points[sk - 1].y) / 2;
                    ctx.quadraticCurveTo(points[sk - 1].x, points[sk - 1].y, sxc, syc);
                }
                ctx.stroke();
                ctx.shadowBlur = 0;
                return;
            }

            // Bipolar oscilloscope mode: symmetrical frequency waveform around midY
            for (var i = 0; i <= numPoints; i++) {
                var normX = i / numPoints;
                var x = normX * w;

                var bandIdx = Math.min(15, Math.floor(normX * 16));
                var bandVal = bands[bandIdx] || 0.0;

                var sign = (i % 2 === 0) ? 1 : -1;
                var edgeTaper = Math.sin(normX * Math.PI); // Smoothly tapers to 0 at edges
                var amp = bandVal * maxAmp * 0.95;
                var y = midY - (amp * sign * edgeTaper) - (beat * 3.0 * sign * edgeTaper);

                points.push({ x: x, y: y });
            }

            // 3. Draw gradient area fill
            if (root.showAreaFill && points.length > 0) {
                var grad = ctx.createLinearGradient(0, 0, 0, h);
                grad.addColorStop(0.0, Qt.alpha(root.waveColor, 0.25));
                grad.addColorStop(0.5, Qt.alpha(root.waveColor, 0.08));
                grad.addColorStop(1.0, Qt.alpha(root.waveColor, 0.0));

                ctx.fillStyle = grad;
                ctx.beginPath();
                ctx.moveTo(0, midY);
                for (var p = 0; p < points.length; p++) {
                    ctx.lineTo(points[p].x, points[p].y);
                }
                ctx.lineTo(w, midY);
                ctx.closePath();
                ctx.fill();
            }

            // 4. Draw glowing neon waveform trace
            var strokeCol = root.waveColor;
            ctx.shadowColor = strokeCol;
            ctx.shadowBlur = 6;
            ctx.strokeStyle = strokeCol;
            ctx.lineWidth = root.lineWidth;

            ctx.beginPath();
            ctx.moveTo(points[0].x, points[0].y);
            for (var k = 1; k < points.length; k++) {
                var xc = (points[k].x + points[k - 1].x) / 2;
                var yc = (points[k].y + points[k - 1].y) / 2;
                ctx.quadraticCurveTo(points[k - 1].x, points[k - 1].y, xc, yc);
            }
            ctx.lineTo(points[points.length - 1].x, points[points.length - 1].y);
            ctx.stroke();

            ctx.shadowBlur = 0;
        }
    }

    // Small cyber telemetry corner label
    Text {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.topMargin: 2
        anchors.leftMargin: 4
        text: "OSC // 48K"
        font.family: Theme.fontMonospace
        font.pixelSize: 6
        font.weight: Font.Bold
        color: Qt.alpha(Colors.primary, 0.6)
        visible: root.isPlaying
    }
}
