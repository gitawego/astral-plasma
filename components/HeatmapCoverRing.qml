import QtQuick
import "../theme"
import "../services"

Item {
    id: root

    property real innerRadius: 41
    property real outerRadius: 50
    property bool isTargetVisible: true
    property bool showAura: true
    property bool showNotes: true

    implicitWidth: outerRadius * 2 + 36
    implicitHeight: outerRadius * 2 + 36
    width: implicitWidth
    height: implicitHeight

    readonly property real centerX: width / 2
    readonly property real centerY: height / 2
    readonly property real midRadius: (innerRadius + outerRadius) / 2
    readonly property real ringThickness: Math.max(3, outerRadius - innerRadius)

    readonly property bool isPlaying: (typeof MprisMedia !== "undefined" && MprisMedia) ? MprisMedia.isPlaying : false
    readonly property bool isVisualizerActive: (typeof AudioVisualizer !== "undefined" && AudioVisualizer && AudioVisualizer.active === true)
    readonly property real audioEnergy: (root.isPlaying && isVisualizerActive && root.isTargetVisible) ? AudioVisualizer.energy : 0.0
    readonly property real audioBass: (root.isPlaying && isVisualizerActive && root.isTargetVisible) ? AudioVisualizer.bass : 0.0
    readonly property real audioTreble: (root.isPlaying && isVisualizerActive && root.isTargetVisible) ? AudioVisualizer.treble : 0.0
    readonly property real audioBeat: (root.isPlaying && isVisualizerActive && root.isTargetVisible) ? AudioVisualizer.beat : 0.0

    // Gentle orbital phase animation
    property real animPhase: 0.0
    NumberAnimation on animPhase {
        from: 0.0
        to: Math.PI * 2
        duration: 8000
        loops: Animation.Infinite
        running: root.isPlaying && root.isTargetVisible && root.isVisualizerActive && root.audioEnergy > 0.005
    }


    // ==========================================
    // 1. DYNAMIC JUMPING MUSIC DOTS & RAINBOW NOTES (DASHBOARD)
    // ==========================================
    // Balanced distribution of bass, mid, and treble bands around 360 degrees
    readonly property var dynamicElements: [
        { type: "note", text: "♪", angle: 260, rBase: 1.22, color: "#FFD600", size: 11, bandIdx: 1 },
        { type: "dot",  dotSize: 5, angle: 285, rBase: 1.20, color: "#FFEA00", bandIdx: 4 },
        { type: "note", text: "♫", angle: 310, rBase: 1.23, color: "#76FF03", size: 12, bandIdx: 2 },
        { type: "dot",  dotSize: 6, angle: 335, rBase: 1.21, color: "#00E5FF", bandIdx: 6 },
        { type: "note", text: "♬", angle: 0,   rBase: 1.23, color: "#00B0FF", size: 12, bandIdx: 1 },
        { type: "dot",  dotSize: 5, angle: 25,  rBase: 1.20, color: "#2979FF", bandIdx: 5 },
        { type: "note", text: "♪", angle: 50,  rBase: 1.22, color: "#651FFF", size: 11, bandIdx: 2 },
        { type: "dot",  dotSize: 6, angle: 75,  rBase: 1.21, color: "#7C4DFF", bandIdx: 7 },
        { type: "note", text: "♫", angle: 100, rBase: 1.23, color: "#D500F9", size: 12, bandIdx: 0 },
        { type: "dot",  dotSize: 5, angle: 125, rBase: 1.20, color: "#E040FB", bandIdx: 3 },
        { type: "note", text: "♬", angle: 150, rBase: 1.22, color: "#FF1744", size: 11, bandIdx: 1 },
        { type: "dot",  dotSize: 6, angle: 175, rBase: 1.21, color: "#FF5252", bandIdx: 6 },
        { type: "note", text: "♪", angle: 205, rBase: 1.22, color: "#FF9100", size: 11, bandIdx: 2 },
        { type: "dot",  dotSize: 5, angle: 235, rBase: 1.20, color: "#FFC107", bandIdx: 4 }
    ]

    Item {
        anchors.fill: parent
        visible: root.isPlaying && root.showNotes && root.isTargetVisible && root.isVisualizerActive && (root.audioEnergy > 0.005 || root.audioBeat > 0.005)

        Repeater {
            model: root.dynamicElements

            delegate: Item {
                required property var modelData
                required property int index

                readonly property real rad: (modelData.angle * Math.PI / 180)
                readonly property real bandAmp: (typeof AudioVisualizer !== "undefined" && AudioVisualizer && AudioVisualizer.bands && AudioVisualizer.bands[modelData.bandIdx] !== undefined)
                    ? AudioVisualizer.bands[modelData.bandIdx]
                    : 0.0

                // DYNAMIC BEAT JUMP: energetic, visible 15 to 20 pixel hop on every beat transient
                property real beatJump: (root.audioBeat * 15.0) + (bandAmp * 5.0)
                readonly property real floatBob: Math.sin(root.animPhase + index * 0.5) * 1.5
                readonly property real currentR: (root.outerRadius * modelData.rBase) + floatBob + beatJump

                Behavior on beatJump {
                    NumberAnimation { duration: 45; easing.type: Easing.OutQuad }
                }

                x: root.centerX + Math.cos(rad) * currentR - width / 2
                y: root.centerY + Math.sin(rad) * currentR - height / 2
                width: modelData.type === "note" ? 16 : modelData.dotSize
                height: width

                scale: 1.0 + (root.audioBeat * 0.40) + (bandAmp * 0.18)
                Behavior on scale {
                    NumberAnimation { duration: 45; easing.type: Easing.OutQuad }
                }

                opacity: 0.80 + root.audioEnergy * 0.20

                // Visual: Musical Note
                Text {
                    visible: modelData.type === "note"
                    anchors.centerIn: parent
                    text: modelData.text || "♪"
                    font.pixelSize: modelData.size || 11
                    font.bold: true
                    color: modelData.color
                }

                // Visual: Glowing Music Dot
                Rectangle {
                    visible: modelData.type === "dot"
                    anchors.fill: parent
                    radius: width / 2
                    color: modelData.color
                    border.color: Qt.rgba(1, 1, 1, 0.7)
                    border.width: 1
                }
            }
        }
    }

    // ==========================================
    // 2. RADIANT HEATMAP CORONA & SPARKS CANVAS
    // ==========================================
    Canvas {
        id: coronaCanvas
        anchors.fill: parent

        Connections {
            target: (typeof AudioVisualizer !== "undefined") ? AudioVisualizer : null
            function onFrameUpdated() {
                if (root.isTargetVisible && root.isVisualizerActive) {
                    coronaCanvas.requestPaint();
                }
            }
            function onBandsChanged() {
                if (root.isTargetVisible && root.isVisualizerActive) {
                    coronaCanvas.requestPaint();
                }
            }
            function onActiveChanged() {
                coronaCanvas.requestPaint();
            }
        }

        Connections {
            target: root
            function onIsPlayingChanged() {
                coronaCanvas.requestPaint();
            }
            function onIsTargetVisibleChanged() {
                coronaCanvas.requestPaint();
            }
            function onIsVisualizerActiveChanged() {
                coronaCanvas.requestPaint();
            }
        }

        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();

            var cx = root.centerX;
            var cy = root.centerY;
            var energy = root.audioEnergy;

            if (!root.isPlaying || !root.isVisualizerActive || !root.isTargetVisible || energy <= 0.005) {
                ctx.beginPath();
                ctx.arc(cx, cy, root.midRadius, 0, Math.PI * 2);
                ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.08);
                ctx.lineWidth = 2.0;
                ctx.stroke();
                return;
            }

            // A. Soft backdrop aura
            if (root.showAura) {
                var glowRadius = root.outerRadius * (1.18 + energy * 0.18);
                var glowGrad = ctx.createRadialGradient(cx, cy, root.innerRadius, cx, cy, glowRadius);
                glowGrad.addColorStop(0.0, "rgba(255, 140, 0, 0.26)");
                glowGrad.addColorStop(0.5, "rgba(213, 0, 249, 0.14)");
                glowGrad.addColorStop(1.0, "rgba(0, 0, 0, 0.0)");
                ctx.fillStyle = glowGrad;
                ctx.beginPath();
                ctx.arc(cx, cy, glowRadius, 0, Math.PI * 2);
                ctx.fill();
            }

            // B. Multi-color radiant heatmap corona ring (Double Pass Bloom)
            var segCount = 36;
            var rimW = root.ringThickness + energy * 3.5;

            // Pass 1: Outer Soft Bloom
            ctx.lineCap = "round";
            for (var b = 0; b < segCount; b++) {
                var ba1 = (b / segCount) * Math.PI * 2;
                var ba2 = ((b + 1.1) / segCount) * Math.PI * 2;
                var bNorm = b / segCount;

                var bloomColor;
                if (bNorm < 0.16) bloomColor = "rgba(0, 229, 255, 0.35)";
                else if (bNorm < 0.33) bloomColor = "rgba(41, 121, 255, 0.35)";
                else if (bNorm < 0.50) bloomColor = "rgba(213, 0, 249, 0.35)";
                else if (bNorm < 0.66) bloomColor = "rgba(255, 23, 68, 0.35)";
                else if (bNorm < 0.83) bloomColor = "rgba(255, 145, 0, 0.40)";
                else bloomColor = "rgba(255, 214, 0, 0.45)";

                ctx.strokeStyle = bloomColor;
                ctx.lineWidth = rimW * 1.5;
                ctx.beginPath();
                ctx.arc(cx, cy, root.midRadius, ba1, ba2);
                ctx.stroke();
            }

            // Pass 2: Core Spectrum Ring
            for (var s = 0; s < segCount; s++) {
                var a1 = (s / segCount) * Math.PI * 2;
                var a2 = ((s + 1.05) / segCount) * Math.PI * 2;
                var normA = s / segCount;

                var hColor;
                if (normA < 0.16) hColor = "rgb(0, 229, 255)";
                else if (normA < 0.33) hColor = "rgb(41, 121, 255)";
                else if (normA < 0.50) hColor = "rgb(213, 0, 249)";
                else if (normA < 0.66) hColor = "rgb(255, 23, 68)";
                else if (normA < 0.83) hColor = "rgb(255, 145, 0)";
                else hColor = "rgb(255, 214, 0)";

                ctx.strokeStyle = hColor;
                ctx.lineWidth = rimW;
                ctx.beginPath();
                ctx.arc(cx, cy, root.midRadius, a1, a2);
                ctx.stroke();
            }

            // Specular sheen highlight
            ctx.strokeStyle = "rgba(255, 255, 255, 0.70)";
            ctx.lineWidth = 1.8;
            ctx.beginPath();
            ctx.arc(cx, cy, root.midRadius - rimW * 0.28, -Math.PI * 0.25, Math.PI * 0.4);
            ctx.stroke();
        }
    }
}
