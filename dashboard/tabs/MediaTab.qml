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
    implicitHeight: 320
    clip: true

    Item {
        anchors.fill: parent
        clip: true

        RowLayout {
            anchors.fill: parent
            anchors.margins: Theme.padLarge
            spacing: Theme.spaceLarge

            // Left: Dynamic Audio Heatmap Speaker Player (Target Visual Design)
            HeatmapSpeakerPlayer {
                Layout.preferredWidth: 260
                Layout.preferredHeight: 260
                Layout.alignment: Qt.AlignVCenter
                isPlaying: MprisMedia.isPlaying
                artUrl: MprisMedia.artUrl
                title: MprisMedia.title
                artist: MprisMedia.artist
                isTargetVisible: Config.dashboardVisible && Config.activeDashboardTab === "media"
            }

            // Center: Track Details & Controls
            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: Theme.spaceSmall

                Text {
                    text: MprisMedia.title || "No Media Playing"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontTitleMedium
                    font.weight: Font.Bold
                    color: Colors.m3onSurface
                    horizontalAlignment: Text.AlignHCenter
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }

                Text {
                    text: MprisMedia.artist || "Unknown Artist"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontBodySmall
                    color: Colors.m3onSurfaceVariant
                    horizontalAlignment: Text.AlignHCenter
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }

                Item { height: 4 }

                // Playback Controls Row (|<<  [ > ]  >>|)
                Row {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: Theme.spaceMedium

                    PillButton {
                        iconText: "skip_previous"
                        iconSize: 20
                        implicitWidth: 38
                        implicitHeight: 38
                        onClicked: MprisMedia.previous()
                    }

                    PillButton {
                        iconText: MprisMedia.isPlaying ? "pause" : "play_arrow"
                        iconSize: 22
                        active: true
                        implicitWidth: 48
                        implicitHeight: 48
                        onClicked: MprisMedia.playPause()
                    }

                    PillButton {
                        iconText: "skip_next"
                        iconSize: 20
                        implicitWidth: 38
                        implicitHeight: 38
                        onClicked: MprisMedia.next()
                    }
                }

                Item { height: 4 }

                // Progress Bar with Timestamps & Interactive Seeking
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

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

                    Rectangle {
                        Layout.fillWidth: true
                        height: 6
                        radius: 3
                        color: Colors.surfaceContainerHigh

                        Rectangle {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: parent.width * Math.min(1.0, Math.max(0.0, MprisMedia.progress))
                            radius: 3
                            color: Colors.primary
                        }

                        // Interactive seeking
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: mouse => {
                                let frac = Math.max(0.0, Math.min(1.0, mouse.x / width));
                                MprisMedia.seekTo(frac);
                            }
                        }
                    }

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

                Item { height: 2 }

                // Active Player Pill Badge (Interactive player switch/dropdown)
                Rectangle {
                    id: playerBadge
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: playerRow.implicitWidth + 28
                    implicitHeight: 28
                    Layout.preferredWidth: implicitWidth
                    Layout.preferredHeight: implicitHeight
                    radius: height / 2
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
            }

            // Right: Media Avatar (Supports gif, svg, png, jpg, and video; defaults to boba cat)
            Item {
                Layout.preferredWidth: 220
                Layout.preferredHeight: 240
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
