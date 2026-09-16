import QtQuick
import QtQuick.Effects
import "../theme"
import "../services"
import "../config"

Item {
    id: root

    property bool isPlaying: false
    property string artUrl: ""
    property string title: ""
    property string artist: ""
    property bool isTargetVisible: (typeof Config !== "undefined")
        ? (Config.dashboardVisible && Config.activeDashboardTab === "media")
        : true

    implicitWidth: 260
    implicitHeight: 260

    readonly property real centerX: width / 2
    readonly property real centerY: height / 2
    readonly property real speakerRadius: Math.min(width, height) * 0.28
    readonly property real rimThickness: 14
    readonly property real innerSpeakerRadius: speakerRadius - (rimThickness / 2) - 2

    // Real-time audio reactive variables
    readonly property real audioEnergy: (AudioVisualizer.active && root.isTargetVisible) ? AudioVisualizer.energy : 0.0
    readonly property real audioBass: (AudioVisualizer.active && root.isTargetVisible) ? AudioVisualizer.bass : 0.0
    readonly property real audioTreble: (AudioVisualizer.active && root.isTargetVisible) ? AudioVisualizer.treble : 0.0
    readonly property real audioBeat: (AudioVisualizer.active && root.isTargetVisible) ? AudioVisualizer.beat : 0.0

    // Animation timer for gentle orbital float
    property real animPhase: 0.0
    NumberAnimation on animPhase {
        from: 0.0
        to: Math.PI * 2
        duration: 8000
        loops: Animation.Infinite
        running: root.isPlaying && root.isTargetVisible
    }

    // High-framerate render pulse to guarantee 100% fluid dynamic canvas repainting
    Timer {
        interval: 33 // ~30 FPS
        running: root.isTargetVisible && AudioVisualizer.active
        repeat: true
        onTriggered: coronaCanvas.requestPaint()
    }

    // ==========================================
    // 1. DYNAMIC JUMPING MUSIC DOTS & RAINBOW NOTES
    // ==========================================
    // Array of both musical notes AND music dots (beads) orbiting comfortably outside the speaker rim
    readonly property var dynamicElements: [
        // Top-left (Golden / Amber) - Bass & Low Mids
        { type: "note", text: "♪", angle: 260, rBase: 1.35, color: "#FFD600", size: 15, bandIdx: 1 },
        { type: "dot",  dotSize: 6, angle: 275, rBase: 1.33, color: "#FFEA00", bandIdx: 2 },
        { type: "note", text: "♫", angle: 290, rBase: 1.37, color: "#FFEE58", size: 16, bandIdx: 3 },
        { type: "dot",  dotSize: 5, angle: 305, rBase: 1.34, color: "#FFF176", bandIdx: 4 },
        { type: "dot",  dotSize: 7, angle: 315, rBase: 1.35, color: "#EEFF41", bandIdx: 1 },

        // Top / Top-Right (Lime & Cyan / Turquoise) - High Mids & Treble
        { type: "note", text: "♬", angle: 328, rBase: 1.37, color: "#76FF03", size: 15, bandIdx: 2 },
        { type: "dot",  dotSize: 6, angle: 340, rBase: 1.33, color: "#00E676", bandIdx: 5 },
        { type: "note", text: "♪", angle: 352, rBase: 1.36, color: "#00E5FF", size: 14, bandIdx: 1 },
        { type: "dot",  dotSize: 7, angle: 5,   rBase: 1.34, color: "#00B0FF", bandIdx: 3 },
        { type: "note", text: "♫", angle: 20,  rBase: 1.38, color: "#0091EA", size: 16, bandIdx: 2 },
        { type: "dot",  dotSize: 5, angle: 32,  rBase: 1.33, color: "#40C4FF", bandIdx: 4 },

        // Right & Bottom-Right (Electric Cobalt & Indigo) - Highs
        { type: "note", text: "♩", angle: 45,  rBase: 1.36, color: "#2979FF", size: 15, bandIdx: 1 },
        { type: "dot",  dotSize: 6, angle: 60,  rBase: 1.33, color: "#3D5AFE", bandIdx: 3 },
        { type: "note", text: "♪", angle: 75,  rBase: 1.35, color: "#651FFF", size: 14, bandIdx: 2 },
        { type: "dot",  dotSize: 5, angle: 90,  rBase: 1.33, color: "#7C4DFF", bandIdx: 5 },
        { type: "note", text: "♫", angle: 105, rBase: 1.37, color: "#B388FF", size: 16, bandIdx: 0 },

        // Bottom & Bottom-Left (Magenta, Hot Pink & Crimson) - Sub-Bass & Kick
        { type: "dot",  dotSize: 7, angle: 120, rBase: 1.34, color: "#D500F9", bandIdx: 1 },
        { type: "note", text: "♬", angle: 135, rBase: 1.37, color: "#E040FB", size: 15, bandIdx: 2 },
        { type: "dot",  dotSize: 5, angle: 150, rBase: 1.33, color: "#F50057", bandIdx: 3 },
        { type: "note", text: "♪", angle: 165, rBase: 1.36, color: "#FF1744", size: 14, bandIdx: 0 },
        { type: "dot",  dotSize: 7, angle: 180, rBase: 1.34, color: "#FF5252", bandIdx: 1 },

        // Left (Fiery Amber & Deep Orange) - Powerful Bass
        { type: "note", text: "♫", angle: 195, rBase: 1.38, color: "#FF6D00", size: 16, bandIdx: 2 },
        { type: "dot",  dotSize: 6, angle: 210, rBase: 1.33, color: "#FF9100", bandIdx: 0 },
        { type: "note", text: "♪", angle: 225, rBase: 1.36, color: "#FFA000", size: 14, bandIdx: 1 },
        { type: "dot",  dotSize: 7, angle: 240, rBase: 1.35, color: "#FFC107", bandIdx: 2 },
        { type: "dot",  dotSize: 5, angle: 250, rBase: 1.33, color: "#FFD54F", bandIdx: 3 }
    ]

    Item {
        id: elementsLayer
        anchors.fill: parent

        Repeater {
            model: root.dynamicElements

            delegate: Item {
                id: elemDelegate
                required property var modelData
                required property int index

                readonly property real rad: (modelData.angle * Math.PI / 180)
                readonly property real bandAmp: (AudioVisualizer.bands && AudioVisualizer.bands[modelData.bandIdx] !== undefined)
                    ? AudioVisualizer.bands[modelData.bandIdx]
                    : 0.0

                // DYNAMIC BEAT JUMP: energetic, visible 18 to 25 pixel hop on every beat transient
                property real beatJump: (root.audioBeat * 18.0) + (bandAmp * 6.0)
                readonly property real floatBob: Math.sin(root.animPhase + index * 0.4) * 2.0
                readonly property real currentR: (root.speakerRadius * modelData.rBase) + floatBob + beatJump

                Behavior on beatJump {
                    NumberAnimation { duration: 45; easing.type: Easing.OutQuad }
                }

                x: root.centerX + Math.cos(rad) * currentR - width / 2
                y: root.centerY + Math.sin(rad) * currentR - height / 2
                width: modelData.type === "note" ? 19 : modelData.dotSize
                height: width

                scale: 1.0 + (root.audioBeat * 0.40) + (bandAmp * 0.20)
                Behavior on scale {
                    NumberAnimation { duration: 45; easing.type: Easing.OutQuad }
                }

                opacity: 0.75 + root.audioEnergy * 0.25

                // Visual: Musical Note
                Text {
                    visible: modelData.type === "note"
                    anchors.centerIn: parent
                    text: modelData.text || "♪"
                    font.family: "Noto Sans, sans-serif"
                    font.pixelSize: modelData.size || 15
                    font.bold: true
                    color: modelData.color
                    rotation: (modelData.angle + 90) + Math.sin(root.animPhase + index) * 12.0
                    style: Text.Outline
                    styleColor: Qt.alpha(modelData.color, 0.45)
                }

                // Visual: Glowing Music Dot / Bead
                Rectangle {
                    visible: modelData.type === "dot"
                    anchors.fill: parent
                    radius: width / 2
                    color: modelData.color
                    border.color: Qt.rgba(1, 1, 1, 0.7)
                    border.width: 1

                    // Subtle dot outer glow halo
                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width * 1.8
                        height: width
                        radius: width / 2
                        color: Qt.alpha(modelData.color, 0.3)
                        z: -1
                    }
                }
            }
        }
    }

    // ==========================================
    // 2. AUDIO-REACTIVE HEATMAP CORONA (INCANDESCENT BLOOM)
    // ==========================================
    Canvas {
        id: coronaCanvas
        anchors.fill: parent

        Connections {
            target: AudioVisualizer
            function onFrameUpdated() {
                if (root.isTargetVisible && AudioVisualizer.active) {
                    coronaCanvas.requestPaint();
                }
            }
            function onBandsChanged() {
                if (root.isTargetVisible && AudioVisualizer.active) {
                    coronaCanvas.requestPaint();
                }
            }
            function onActiveChanged() {
                coronaCanvas.requestPaint();
            }
        }

        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();

            var cx = root.centerX;
            var cy = root.centerY;
            var r = root.speakerRadius;
            var energy = root.audioEnergy;
            var treble = root.audioTreble;

            // Soft radial thermal ambient glow
            var glowRadius = r * (1.22 + energy * 0.22);
            var glowGrad = ctx.createRadialGradient(cx, cy, r * 0.82, cx, cy, glowRadius);
            glowGrad.addColorStop(0.0, "rgba(255, 140, 0, 0.28)");
            glowGrad.addColorStop(0.4, "rgba(230, 81, 0, 0.16)");
            glowGrad.addColorStop(0.7, "rgba(106, 27, 154, 0.09)");
            glowGrad.addColorStop(1.0, "rgba(0, 0, 0, 0.0)");

            ctx.fillStyle = glowGrad;
            ctx.beginPath();
            ctx.arc(cx, cy, glowRadius, 0, Math.PI * 2);
            ctx.fill();

            // Multi-Color Radiant Heatmap Corona Ring (Pass 1: Outer Bloom)
            var segCount = 48;
            var rimW = root.rimThickness + energy * 5.0;

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
                ctx.lineWidth = rimW * 1.6;
                ctx.beginPath();
                ctx.arc(cx, cy, r, ba1, ba2);
                ctx.stroke();
            }

            // Multi-Color Radiant Heatmap Corona Ring (Pass 2: Core Spectrum)
            for (var s = 0; s < segCount; s++) {
                var a1 = (s / segCount) * Math.PI * 2;
                var a2 = ((s + 1.08) / segCount) * Math.PI * 2;
                var normA = s / segCount;

                var hColor;
                if (normA < 0.16) hColor = "rgb(0, 229, 255)"; // Cyan
                else if (normA < 0.33) hColor = "rgb(41, 121, 255)"; // Electric Blue
                else if (normA < 0.50) hColor = "rgb(213, 0, 249)"; // Purple / Magenta
                else if (normA < 0.66) hColor = "rgb(255, 23, 68)";  // Crimson
                else if (normA < 0.83) hColor = "rgb(255, 145, 0)"; // Fiery Orange
                else hColor = "rgb(255, 214, 0)"; // Golden Yellow

                ctx.strokeStyle = hColor;
                ctx.lineWidth = rimW;
                ctx.beginPath();
                ctx.arc(cx, cy, r, a1, a2);
                ctx.stroke();
            }

            // Specular champagne-white highlight sheen
            ctx.strokeStyle = "rgba(255, 255, 255, 0.80)";
            ctx.lineWidth = 2.4;
            ctx.beginPath();
            ctx.arc(cx, cy, r - rimW * 0.30, -Math.PI * 0.28, Math.PI * 0.42);
            ctx.stroke();

            ctx.strokeStyle = "rgba(255, 245, 200, 0.60)";
            ctx.lineWidth = 2.0;
            ctx.beginPath();
            ctx.arc(cx, cy, r - rimW * 0.30, Math.PI * 0.72, Math.PI * 1.38);
            ctx.stroke();
        }
    }

    // ==========================================
    // 3. SEAMLESS SPEAKER CHASSIS & CENTER COVER (NO BLACK GAP)
    // ==========================================
    // The circular artwork fills the entire inner space of the speaker rim directly!
    Item {
        id: centerArtworkContainer
        anchors.centerIn: parent
        width: root.innerSpeakerRadius * 2
        height: width

        // Dynamic audio-reactive bass & beat bounce
        scale: 1.0 + Math.min(0.12, (root.audioBeat * 0.08) + (root.audioBass * 0.05))
        Behavior on scale {
            NumberAnimation { duration: 60; easing.type: Easing.OutQuad }
        }

        // Circular mask geometry (strictly masks album art to circle)
        Rectangle {
            id: artMask
            anchors.fill: parent
            radius: width / 2
            color: "white"
            visible: false
            layer.enabled: true
        }

        // Fallback: Metallic Deep Indigo/Purple Speaker Cone when no album art
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            visible: !(root.artUrl.length > 0 && coverImg.status === Image.Ready)
            color: "#1E1233"
            border.color: "#8E24AA"
            border.width: 2.5

            // Inner dome
            Rectangle {
                anchors.centerIn: parent
                width: parent.width * 0.50
                height: width
                radius: width / 2
                color: "#4A148C"
                border.color: "#E040FB"
                border.width: 1.5

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "music_note"
                    size: 32
                    color: "#EA80FC"
                }
            }
        }

        // Album Artwork (Rotates smoothly like vinyl, 1.45x size prevents corner clipping)
        Item {
            anchors.fill: parent
            visible: root.artUrl.length > 0 && coverImg.status === Image.Ready

            Item {
                anchors.centerIn: parent
                width: parent.width * 1.45
                height: width

                NumberAnimation on rotation {
                    from: 0
                    to: 360
                    duration: 22000
                    loops: Animation.Infinite
                    running: true
                    paused: !root.isPlaying
                }

                Image {
                    id: coverImg
                    anchors.fill: parent
                    source: root.artUrl || ""
                    fillMode: Image.PreserveAspectCrop
                }
            }

            layer.enabled: true
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: artMask
            }
        }

        // Concentric Metallic Bevel Rim directly framing the album artwork
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "transparent"
            border.color: Qt.rgba(1, 1, 1, 0.40)
            border.width: 2.5

            // Inner neon accent border line
            Rectangle {
                anchors.fill: parent
                anchors.margins: 2
                radius: width / 2
                color: "transparent"
                border.color: Qt.rgba(0.9, 0.4, 1.0, 0.55 + root.audioEnergy * 0.45)
                border.width: 1.5
            }
        }

        // 4 Metallic Studs / Screws at 0°, 90°, 180°, 270° along the chassis rim
        Repeater {
            model: [0, 90, 180, 270]
            delegate: Rectangle {
                required property int modelData
                readonly property real rad: modelData * Math.PI / 180
                readonly property real screwDist: (centerArtworkContainer.width / 2) - 3.0

                x: (centerArtworkContainer.width / 2) + Math.cos(rad) * screwDist - 3
                y: (centerArtworkContainer.height / 2) + Math.sin(rad) * screwDist - 3
                width: 6
                height: 6
                radius: 3
                color: "#FFFFFF"
                border.color: "#333333"
                border.width: 1
            }
        }
    }
}
