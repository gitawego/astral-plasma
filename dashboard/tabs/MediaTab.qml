import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../components"
import "../../services"
import "../../menus"
import "../../config"

Item {
    id: root

    implicitWidth: 680
    implicitHeight: 260
    clip: true

    Item {
        anchors.fill: parent
        clip: true

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.padLarge
            anchors.rightMargin: Theme.padLarge
            anchors.topMargin: Theme.padSmall
            anchors.bottomMargin: Theme.padSmall
            spacing: Theme.spaceLarge

            // Left: Audio Spectrum Visualizer (User-selectable: Radial Caelestia Halo vs Heatmap Speaker)
            Item {
                id: visualizerSlot
                Layout.preferredWidth: 240
                Layout.preferredHeight: 240
                Layout.alignment: Qt.AlignVCenter

                readonly property bool isSpeakerStyle: (typeof Config !== "undefined") &&
                    (Config.mediaVisualizerStyle === "speaker" || Config.mediaVisualizerStyle === "heatmap")

                // Caelestia Radial Visualizer (Spectrum halo around circular album art)
                RadialCoverVisualiser {
                    id: radialViz
                    anchors.centerIn: parent
                    width: 240
                    height: 240
                    visible: !visualizerSlot.isSpeakerStyle
                    isPlaying: MprisMedia.isPlaying
                    artUrl: MprisMedia.artUrl
                    title: MprisMedia.title
                    artist: MprisMedia.artist
                    isTargetVisible: (typeof Config !== "undefined") ? (Config.dashboardVisible && Config.activeDashboardTab === "media" && visible) : false
                }

                // Original Heatmap Speaker Player (Pulsing speaker cone with orbiting rainbow notes & beads)
                HeatmapSpeakerPlayer {
                    id: speakerViz
                    anchors.centerIn: parent
                    width: 240
                    height: 240
                    visible: visualizerSlot.isSpeakerStyle
                    isPlaying: MprisMedia.isPlaying
                    artUrl: MprisMedia.artUrl
                    title: MprisMedia.title
                    artist: MprisMedia.artist
                    isTargetVisible: (typeof Config !== "undefined") ? (Config.dashboardVisible && Config.activeDashboardTab === "media" && visible) : false
                }

                // Visualizer Switcher Pill Button (Floating subtle toggle)
                LiquidGlassButton {
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.topMargin: 4
                    anchors.rightMargin: 4
                    z: 50
                    implicitWidth: 28
                    implicitHeight: 28
                    paddingHorizontal: 6
                    paddingVertical: 6
                    iconText: visualizerSlot.isSpeakerStyle ? "album" : "speaker"
                    iconSize: 16
                    elevation: 4
                    onClicked: {
                        if (typeof Config !== "undefined" && Config.setMediaVisualizerStyle) {
                            Config.setMediaVisualizerStyle(visualizerSlot.isSpeakerStyle ? "radial" : "speaker");
                        }
                    }
                }
            }

            // Center: Track Details & Controls (Caelestia layout)
            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 2

                // Track Title
                Text {
                    text: MprisMedia.title || "No Media Playing"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontTitleLarge
                    font.weight: Font.DemiBold
                    color: Colors.m3onSurface
                    horizontalAlignment: Text.AlignHCenter
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }

                // Track Album (if present)
                Text {
                    text: MprisMedia.album || ""
                    visible: text.length > 0
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontBodySmall
                    color: Colors.primary
                    horizontalAlignment: Text.AlignHCenter
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }

                // Track Artist
                Text {
                    text: MprisMedia.artist || "Unknown Artist"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontBodyMedium
                    color: Colors.m3onSurfaceVariant
                    horizontalAlignment: Text.AlignHCenter
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }

                Item { Layout.preferredHeight: 4; Layout.fillWidth: true }

                // Playback Controls Row (|<<  [ > ]  >>|)
                Row {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: Theme.spaceMedium

                    // Skip Previous
                    LiquidGlassButton {
                        implicitWidth: 38
                        implicitHeight: 38
                        paddingHorizontal: 8
                        paddingVertical: 8
                        iconText: "skip_previous"
                        iconSize: 20
                        elevation: 4
                        interactive: (typeof MprisMedia !== "undefined") ? MprisMedia.canGoPrevious : true
                        opacity: ((typeof MprisMedia !== "undefined") ? MprisMedia.canGoPrevious : true) ? 1.0 : 0.45
                        onClicked: MprisMedia.previous()
                    }

                    // Play / Pause (Prominent Circular Primary Liquid Glass)
                    LiquidGlassButton {
                        implicitWidth: 48
                        implicitHeight: 48
                        paddingHorizontal: 10
                        paddingVertical: 10
                        isPrimary: true
                        iconText: (typeof MprisMedia !== "undefined" && MprisMedia.isPlaying) ? "pause" : "play_arrow"
                        iconSize: 26
                        elevation: 8
                        onClicked: MprisMedia.playPause()
                    }

                    // Skip Next
                    LiquidGlassButton {
                        implicitWidth: 38
                        implicitHeight: 38
                        paddingHorizontal: 8
                        paddingVertical: 8
                        iconText: "skip_next"
                        iconSize: 20
                        elevation: 4
                        interactive: (typeof MprisMedia !== "undefined") ? MprisMedia.canGoNext : true
                        opacity: ((typeof MprisMedia !== "undefined") ? MprisMedia.canGoNext : true) ? 1.0 : 0.45
                        onClicked: MprisMedia.next()
                    }
                }

                Item { Layout.preferredHeight: 4; Layout.fillWidth: true }

                // Progress Bar with Vertical Pill Thumb & Interactive Seeking
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 16

                    Rectangle {
                        id: sliderTrack
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        height: 5
                        radius: 2.5
                        color: Colors.surfaceContainerHigh

                        Rectangle {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: parent.width * Math.min(1.0, Math.max(0.0, MprisMedia.progress))
                            radius: 2.5
                            color: Colors.primary
                        }

                        // Bespoke Caelestia Vertical Pill Thumb
                        Rectangle {
                            id: sliderThumb
                            width: 5
                            height: 15
                            radius: 2.5
                            anchors.verticalCenter: parent.verticalCenter
                            x: Math.max(0, Math.min(parent.width - width, parent.width * Math.min(1.0, Math.max(0.0, MprisMedia.progress)) - width / 2))
                            color: Colors.primary
                            visible: MprisMedia.length > 0

                            scale: sliderMouse.pressed ? 1.25 : (sliderMouse.containsMouse ? 1.12 : 1.0)
                            Behavior on scale { NumberAnimation { duration: 100 } }
                        }
                    }

                    // Interactive seeking MouseArea
                    MouseArea {
                        id: sliderMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: MprisMedia.canSeek ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: mouse => {
                            let frac = Math.max(0.0, Math.min(1.0, mouse.x / width));
                            MprisMedia.seekTo(frac);
                        }
                        onPositionChanged: mouse => {
                            if (pressed && MprisMedia.canSeek) {
                                let frac = Math.max(0.0, Math.min(1.0, mouse.x / width));
                                MprisMedia.seekTo(frac);
                            }
                        }
                    }
                }

                // Timestamps Row below progress slider
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: -2

                    Text {
                        text: {
                            const secs = Math.floor(MprisMedia.position);
                            const m = Math.floor(secs / 60);
                            const s = secs % 60;
                            return m + ":" + (s < 10 ? "0" : "") + s;
                        }
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontLabelSmall
                        color: Colors.m3onSurfaceVariant
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        text: {
                            const secs = Math.floor(MprisMedia.length);
                            const m = Math.floor(secs / 60);
                            const s = secs % 60;
                            return m + ":" + (s < 10 ? "0" : "") + s;
                        }
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontLabelSmall
                        color: Colors.m3onSurfaceVariant
                    }
                }

                Item { Layout.preferredHeight: 4; Layout.fillWidth: true }

                // Bottom Utility Row (Shuffle + Active Player Pill Badge + Loop)
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 12

                    // Shuffle Button
                    Rectangle {
                        width: 30
                        height: 30
                        radius: 15
                        color: MprisMedia.shuffle ? Qt.alpha(Colors.primary, 0.22) : (shufHover.containsMouse ? Qt.alpha(Colors.textMain, 0.12) : Colors.surfaceContainerHigh)
                        border.color: MprisMedia.shuffle ? Colors.primary : Theme.borderSubtle
                        border.width: 1

                        Behavior on color { ColorAnimation { duration: 150 } }
                        Behavior on border.color { ColorAnimation { duration: 150 } }

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: "shuffle"
                            size: 16
                            color: MprisMedia.shuffle ? Colors.primary : Colors.m3onSurfaceVariant
                        }

                        MouseArea {
                            id: shufHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: MprisMedia.toggleShuffle()
                        }
                    }

                    // Active Player Pill Badge (Interactive player switch/dropdown)
                    Rectangle {
                        id: playerBadge
                        implicitWidth: playerRow.implicitWidth + 28
                        implicitHeight: 28
                        Layout.preferredWidth: implicitWidth
                        Layout.preferredHeight: implicitHeight
                        radius: 14
                        color: (playerBadgeMouse.containsMouse || playerDropdownOverlay.visible) ? Colors.primaryContainer : Colors.surfaceContainerHigh
                        border.color: (playerBadgeMouse.containsMouse || playerDropdownOverlay.visible) ? Colors.primary : Theme.borderSubtle
                        border.width: 1

                        Behavior on color { ColorAnimation { duration: 150 } }
                        Behavior on border.color { ColorAnimation { duration: 150 } }

                        RowLayout {
                            id: playerRow
                            anchors.centerIn: parent
                            spacing: 6

                            MaterialIcon {
                                text: (MprisMedia.players && MprisMedia.players.length > 1) ? "graphic_eq" : "music_note"
                                size: 14
                                color: Colors.primary
                                Layout.alignment: Qt.AlignVCenter
                            }

                            Text {
                                text: MprisMedia.identity || "Media Player"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontLabelSmall
                                font.weight: Font.Medium
                                color: (playerBadgeMouse.containsMouse || playerDropdownOverlay.visible) ? Colors.onPrimaryContainer : Colors.m3onSurface
                                Layout.alignment: Qt.AlignVCenter
                            }

                            MaterialIcon {
                                visible: MprisMedia.players && MprisMedia.players.length > 1
                                text: "expand_more"
                                size: 15
                                color: Colors.onSurfaceVariant
                                Layout.alignment: Qt.AlignVCenter
                                rotation: playerDropdownOverlay.visible ? 180 : 0
                                Behavior on rotation { NumberAnimation { duration: 150 } }
                            }
                        }

                        MouseArea {
                            id: playerBadgeMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: (MprisMedia.players && MprisMedia.players.length > 1) ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: {
                                if (MprisMedia.players && MprisMedia.players.length > 1) {
                                    if (!playerDropdownOverlay.visible) {
                                        playerDropdownOverlay.open();
                                    } else {
                                        playerDropdownOverlay.visible = false;
                                    }
                                } else {
                                    MprisMedia.cyclePlayer();
                                }
                            }
                        }
                    }

                    // Loop Mode Button
                    Rectangle {
                        width: 30
                        height: 30
                        radius: 15
                        color: MprisMedia.loopState !== 0 ? Qt.alpha(Colors.primary, 0.22) : (loopHover.containsMouse ? Qt.alpha(Colors.textMain, 0.12) : Colors.surfaceContainerHigh)
                        border.color: MprisMedia.loopState !== 0 ? Colors.primary : Theme.borderSubtle
                        border.width: 1

                        Behavior on color { ColorAnimation { duration: 150 } }
                        Behavior on border.color { ColorAnimation { duration: 150 } }

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: MprisMedia.loopState === 1 ? "repeat_one" : "repeat"
                            size: 16
                            color: MprisMedia.loopState !== 0 ? Colors.primary : Colors.m3onSurfaceVariant
                        }

                        MouseArea {
                            id: loopHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: MprisMedia.cycleLoop()
                        }
                    }
                }
            }

            // Right: Media Avatar (Supports gif, svg, png, jpg, and video; defaults to bongo cat)
            Item {
                Layout.preferredWidth: 200
                Layout.preferredHeight: 200
                Layout.alignment: Qt.AlignVCenter

                MediaAvatar {
                    id: mediaAvatar
                    anchors.fill: parent
                    source: Config.mediaAvatar
                    isPlaying: MprisMedia.isPlaying
                }
            }
        }

        // Dropdown Overlay (Floating above RowLayout)
        Item {
            id: playerDropdownOverlay
            anchors.fill: parent
            z: 999
            visible: false

            function open() {
                let pos = playerBadge.mapToItem(playerDropdownOverlay, 0, 0);
                let count = (MprisMedia.players && MprisMedia.players.length > 0) ? MprisMedia.players.length : 1;
                let menuH = 52 + count * 42;
                let targetX = Math.round(pos.x + (playerBadge.width - playerDropdownMenu.width) / 2);
                let targetY = Math.round(pos.y - menuH - 8);
                playerDropdownMenu.x = Math.max(8, Math.min(playerDropdownOverlay.width - playerDropdownMenu.width - 8, targetX));
                playerDropdownMenu.y = Math.max(8, Math.min(playerDropdownOverlay.height - menuH - 8, targetY));
                playerDropdownOverlay.visible = true;
            }

            // Backdrop dismiss: clicks outside the menu close it
            MouseArea {
                anchors.fill: parent
                onClicked: playerDropdownOverlay.visible = false
            }

            MenuCard {
                id: playerDropdownMenu
                z: 1000
                width: 230

                MenuHeader {
                    title: "Media Sources"
                    materialIcon: "queue_music"
                }

                Repeater {
                    model: MprisMedia.players

                    MenuItem {
                        required property var modelData
                        width: parent.width
                        text: MprisMedia.playerIdentity(modelData)
                        subtext: modelData.playbackState === 1 ? "Playing" : (modelData.playbackState === 2 ? "Paused" : "Stopped")
                        materialIcon: modelData.playbackState === 1 ? "play_arrow" : "pause"
                        checked: MprisMedia.isPlayerActive(modelData)
                        onClicked: {
                            MprisMedia.selectPlayer(modelData);
                            playerDropdownOverlay.visible = false;
                        }
                    }
                }
            }
        }
    }
}
