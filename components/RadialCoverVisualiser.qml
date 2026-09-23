import QtQuick
import QtQuick.Effects
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
    readonly property real baseBarHeight: 4
    readonly property real maxBarHeight: 32

    // Audio reactivity
    readonly property bool isVisualizerActive: (typeof AudioVisualizer !== "undefined" && AudioVisualizer && AudioVisualizer.active === true)
    readonly property real audioEnergy: (isVisualizerActive && root.isTargetVisible && root.isPlaying) ? AudioVisualizer.energy : 0.0
    readonly property real audioBeat: (isVisualizerActive && root.isTargetVisible && root.isPlaying) ? AudioVisualizer.beat : 0.0

    // Gentle idle wave phase when playing without audio stream
    property real idlePhase: 0.0
    NumberAnimation on idlePhase {
        from: 0.0
        to: Math.PI * 2
        duration: 3500
        loops: Animation.Infinite
        running: root.isPlaying && root.isTargetVisible
    }

    function getBarValue(idx) {
        if (!root.isPlaying) return 0.0;

        if (root.isVisualizerActive && AudioVisualizer.bands && AudioVisualizer.bands.length > 0) {
            // Map 48 bars into 16 bands symmetrically (bass at sides/bottom, highs across)
            let bandIdx = Math.floor((idx / root.barsCount) * 16);
            let raw = AudioVisualizer.bands[bandIdx] || 0.0;
            let boosted = raw * (0.8 + root.audioEnergy * 0.5 + root.audioBeat * 0.3);
            return Math.max(0.0, Math.min(1.0, boosted));
        }

        // Idle sine wave animation when playing
        let wave = Math.sin(root.idlePhase + idx * 0.38) * 0.3 + 0.3;
        return Math.max(0.0, Math.min(0.7, wave));
    }

    // 1. Radial Audio Visualizer Bars
    Item {
        id: barsContainer
        anchors.fill: parent

        Repeater {
            model: root.barsCount

            Item {
                id: barHolder
                anchors.centerIn: parent
                rotation: index * (360 / root.barsCount)

                readonly property real barVal: root.getBarValue(index)

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.top
                    anchors.bottomMargin: root.coverRadius + root.barSpacing
                    width: 3
                    height: root.baseBarHeight + barHolder.barVal * root.maxBarHeight
                    radius: 1.5
                    color: Colors.primary
                    opacity: root.isPlaying ? (0.65 + barHolder.barVal * 0.35) : 0.3
                }
            }
        }
    }

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

        scale: (root.isPlaying && root.isTargetVisible && root.audioBeat > 0.08)
            ? (1.0 + Math.min(0.04, root.audioBeat * 0.06))
            : 1.0

        Behavior on scale {
            NumberAnimation {
                duration: 90
                easing.type: Easing.OutQuad
            }
        }

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
