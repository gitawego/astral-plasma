import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../theme"
import "../../components"
import "../../config"
import "../../services"

ColumnLayout {
    id: root
    spacing: Theme.spaceLarge
    width: parent ? parent.width : 600

    property bool testMode: false
    property real testVolume: 0.5
    property bool testMuted: false
    property var testAppStreams: []

    readonly property real masterVolume: testMode ? testVolume : ((typeof PipewireAudio !== "undefined") ? PipewireAudio.volume : 0.5)
    readonly property bool isMuted: testMode ? testMuted : ((typeof PipewireAudio !== "undefined") ? PipewireAudio.muted : false)
    readonly property string sinkName: (typeof PipewireAudio !== "undefined" && PipewireAudio.sinkName) ? PipewireAudio.sinkName : "Default Audio Sink"

    property var appStreams: []

    readonly property var currentAppStreams: {
        if (testMode && testAppStreams.length > 0) return testAppStreams;
        return appStreams;
    }

    // Title & Header
    ColumnLayout {
        spacing: 4
        Text {
            text: "Sound & Audio"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontTitleMedium
            font.weight: Font.Bold
            color: Colors.m3onSurface
        }
        Text {
            text: "PipeWire output devices, master volume & per-application audio streams"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontLabelSmall
            color: Colors.m3onSurfaceVariant
        }
    }

    // Master Volume Card
    Rectangle {
        Layout.fillWidth: true
        height: 110
        radius: Theme.radiusMedium
        color: Colors.surfaceContainer
        border.color: Theme.borderSubtle
        border.width: 1

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.padLarge
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spaceMedium

                MaterialIcon {
                    text: root.isMuted ? "volume_off" : (root.masterVolume < 0.5 ? "volume_down" : "volume_up")
                    size: 24
                    color: root.isMuted ? Colors.m3onSurfaceVariant : Colors.primary
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    Text {
                        text: "Master Output Volume"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontTitleSmall
                        font.weight: Font.DemiBold
                        color: Colors.m3onSurface
                    }
                    Text {
                        text: root.sinkName
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontLabelSmall
                        color: Colors.m3onSurfaceVariant
                        elide: Text.ElideRight
                    }
                }

                Text {
                    text: Math.round(root.masterVolume * 100) + "%"
                    font.family: Theme.fontMonospace
                    font.pixelSize: 14
                    font.weight: Font.Bold
                    color: root.isMuted ? Colors.m3onSurfaceVariant : Colors.primary
                }

                // Mute toggle button
                Rectangle {
                    width: 32
                    height: 32
                    radius: 16
                    color: muteHover.containsMouse ? Colors.pillHover : "transparent"

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: root.isMuted ? "volume_off" : "volume_up"
                        size: 18
                        color: root.isMuted ? Colors.error : Colors.m3onSurfaceVariant
                    }

                    MouseArea {
                        id: muteHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (!root.testMode && typeof PipewireAudio !== "undefined") {
                                PipewireAudio.toggleMute();
                            } else {
                                root.testMuted = !root.testMuted;
                            }
                        }
                    }
                }
            }

            // Interactive Volume Track
            Item {
                Layout.fillWidth: true
                height: 20

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: 6
                    radius: 3
                    color: Colors.surfaceContainerHighest

                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: Math.min(parent.width, parent.width * (root.masterVolume / 1.5))
                        radius: 3
                        color: root.isMuted ? Colors.m3onSurfaceVariant : Colors.primary
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    preventStealing: true
                    onPressed: (mouse) => setMasterByPos(mouse.x)
                    onPositionChanged: (mouse) => {
                        if (pressed) setMasterByPos(mouse.x);
                    }

                    function setMasterByPos(x) {
                        const ratio = Math.max(0.0, Math.min(1.5, (x / width) * 1.5));
                        if (!root.testMode && typeof PipewireAudio !== "undefined") {
                            PipewireAudio.setVolume(ratio);
                        } else {
                            root.testVolume = ratio;
                            root.testMuted = false;
                        }
                    }
                }
            }
        }
    }

    // Media Visualizer Style Card
    Rectangle {
        Layout.fillWidth: true
        radius: Theme.radiusMedium
        color: Colors.surfaceContainer
        border.color: Theme.borderSubtle
        border.width: 1
        implicitHeight: vizAudioCol.implicitHeight + Theme.padLarge * 2

        ColumnLayout {
            id: vizAudioCol
            anchors.fill: parent
            anchors.margins: Theme.padLarge
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spaceMedium

                Column {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        text: "Media Visualizer Style"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontBodyMedium
                        font.weight: Font.DemiBold
                        color: Colors.m3onSurface
                    }

                    Text {
                        text: "Applies to both Dashboard and Media tabs"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontLabelSmall
                        color: Colors.m3onSurfaceVariant
                    }
                }

                // Material 3 Segmented Pill
                Rectangle {
                    id: audioVizPill
                    implicitHeight: 38
                    implicitWidth: 260
                    radius: Theme.radiusFull
                    color: Colors.surfaceContainerHigh
                    border.color: Theme.borderSubtle
                    border.width: 1

                    readonly property bool isSpeaker: (typeof Config !== "undefined") &&
                        (Config.mediaVisualizerStyle === "speaker" || Config.mediaVisualizerStyle === "heatmap")

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 2
                        spacing: 2

                        // Radial Halo Segment
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: Theme.radiusFull
                            color: !audioVizPill.isSpeaker ? Colors.primaryContainer : (radialAudioHover.containsMouse ? Colors.pillHover : "transparent")
                            border.color: !audioVizPill.isSpeaker ? Qt.alpha(Colors.primary, 0.4) : "transparent"
                            border.width: !audioVizPill.isSpeaker ? 1 : 0

                            Behavior on color { ColorAnimation { duration: Theme.animDurationFast } }

                            Row {
                                anchors.centerIn: parent
                                spacing: 6

                                MaterialIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "album"
                                    size: 16
                                    color: !audioVizPill.isSpeaker ? Colors.m3onPrimaryContainer : Colors.m3onSurfaceVariant
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Radial Halo"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontBodySmall
                                    font.weight: !audioVizPill.isSpeaker ? Font.Bold : Font.Normal
                                    color: !audioVizPill.isSpeaker ? Colors.m3onPrimaryContainer : Colors.m3onSurfaceVariant
                                }
                            }

                            MouseArea {
                                id: radialAudioHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (typeof Config !== "undefined" && Config.setMediaVisualizerStyle) {
                                        Config.setMediaVisualizerStyle("radial");
                                    }
                                }
                            }
                        }

                        // Speaker Segment
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: Theme.radiusFull
                            color: audioVizPill.isSpeaker ? Colors.primaryContainer : (speakerAudioHover.containsMouse ? Colors.pillHover : "transparent")
                            border.color: audioVizPill.isSpeaker ? Qt.alpha(Colors.primary, 0.4) : "transparent"
                            border.width: audioVizPill.isSpeaker ? 1 : 0

                            Behavior on color { ColorAnimation { duration: Theme.animDurationFast } }

                            Row {
                                anchors.centerIn: parent
                                spacing: 6

                                MaterialIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "speaker"
                                    size: 16
                                    color: audioVizPill.isSpeaker ? Colors.m3onPrimaryContainer : Colors.m3onSurfaceVariant
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Speaker"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontBodySmall
                                    font.weight: audioVizPill.isSpeaker ? Font.Bold : Font.Normal
                                    color: audioVizPill.isSpeaker ? Colors.m3onPrimaryContainer : Colors.m3onSurfaceVariant
                                }
                            }

                            MouseArea {
                                id: speakerAudioHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (typeof Config !== "undefined" && Config.setMediaVisualizerStyle) {
                                        Config.setMediaVisualizerStyle("speaker");
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Per-Application Audio Streams
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 8
        visible: root.currentAppStreams.length > 0

        Text {
            text: "Application Volume"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontTitleSmall
            font.weight: Font.DemiBold
            color: Colors.m3onSurface
        }

        Column {
            Layout.fillWidth: true
            spacing: 6

            Repeater {
                model: root.currentAppStreams
                delegate: Rectangle {
                    required property var modelData
                    required property int index

                    width: parent.width
                    height: 60
                    radius: Theme.radiusSmall
                    color: Colors.surfaceContainer
                    border.color: Theme.borderSubtle
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.padLarge
                        anchors.rightMargin: Theme.padLarge
                        spacing: Theme.spaceMedium

                        MaterialIcon {
                            text: {
                                const a = (modelData.app_name || "").toLowerCase();
                                if (a.includes("music") || a.includes("elisa") || a.includes("strawberry")) return "music_note";
                                if (a.includes("browser") || a.includes("firefox") || a.includes("chrome")) return "public";
                                if (a.includes("game")) return "sports_esports";
                                return "audiotrack";
                            }
                            size: 20
                            color: Colors.primary
                        }

                        Text {
                            text: modelData.app_name || "Application"
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            color: Colors.m3onSurface
                            Layout.preferredWidth: 140
                            elide: Text.ElideRight
                        }

                        // App Volume Slider Track
                        Item {
                            Layout.fillWidth: true
                            height: 20

                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                height: 6
                                radius: 3
                                color: Colors.surfaceContainerHighest

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    width: Math.min(parent.width, parent.width * (modelData.volume || 1.0))
                                    radius: 3
                                    color: modelData.is_muted ? Colors.m3onSurfaceVariant : Colors.primary
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onPressed: (mouse) => setAppVolumeByPos(mouse.x)
                                onPositionChanged: (mouse) => {
                                    if (pressed) setAppVolumeByPos(mouse.x);
                                }

                                function setAppVolumeByPos(x) {
                                    const val = Math.max(0.0, Math.min(1.0, x / width));
                                    if (!root.testMode && typeof Config !== "undefined") {
                                        Quickshell.execDetached([Config.daemonBin, "settings", "audio", "app-volume", "" + modelData.id, val.toFixed(2)]);
                                        root.refreshStreams();
                                    }
                                }
                            }
                        }

                        Text {
                            text: Math.round((modelData.volume || 1.0) * 100) + "%"
                            font.family: Theme.fontMonospace
                            font.pixelSize: 11
                            color: Colors.m3onSurfaceVariant
                            Layout.preferredWidth: 40
                            horizontalAlignment: Text.AlignRight
                        }
                    }
                }
            }
        }
    }

    // Process to poll audio app streams from daemon
    Process {
        id: audioStatusProc
        command: [(typeof Config !== "undefined" && Config.daemonBin) ? Config.daemonBin : "./bin/astral-plasma", "settings", "audio", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(this.text.trim());
                    if (parsed && Array.isArray(parsed.apps)) {
                        root.appStreams = parsed.apps;
                    }
                } catch (e) {}
            }
        }
    }

    function refreshStreams() {
        if (!root.testMode && audioStatusProc.command && !audioStatusProc.running) {
            audioStatusProc.running = true;
        }
    }

    Component.onCompleted: {
        root.refreshStreams();
    }
}
