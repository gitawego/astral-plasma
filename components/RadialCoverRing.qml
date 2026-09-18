import QtQuick
import "../theme"
import "../services"
import "../config"

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
            let bandIdx = Math.floor((idx / root.barsCount) * 16);
            let raw = AudioVisualizer.bands[bandIdx] || 0.0;
            let boosted = raw * (0.8 + root.audioEnergy * 0.5 + root.audioBeat * 0.3);
            return Math.max(0.0, Math.min(1.0, boosted));
        }

        // Idle wave animation
        let wave = Math.sin(root.idlePhase + idx * 0.45) * 0.3 + 0.3;
        return Math.max(0.0, Math.min(0.7, wave));
    }

    Item {
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
                    anchors.bottomMargin: root.innerRadius + root.barSpacing
                    width: 2.5
                    height: root.baseBarHeight + barHolder.barVal * root.maxBarHeight
                    radius: 1.25
                    color: Colors.primary
                    opacity: root.isPlaying ? (0.7 + barHolder.barVal * 0.3) : 0.25

                    Behavior on height {
                        NumberAnimation {
                            duration: 75
                            easing.type: Easing.OutQuad
                        }
                    }

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 200
                        }
                    }
                }
            }
        }
    }
}
