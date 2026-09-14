import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../components"
import "../../services"

Item {
    id: root

    implicitWidth: 680
    implicitHeight: 320

    Card {
        anchors.fill: parent
        radius: Theme.radiusLarge

        RowLayout {
            anchors.fill: parent
            anchors.margins: Theme.padLarge
            spacing: Theme.spaceMedium

            // Left: Circular Vinyl / Radial Visualizer Artwork
            Item {
                Layout.preferredWidth: 200
                Layout.preferredHeight: 200
                Layout.alignment: Qt.AlignVCenter

                // Radial visualizer bars ring
                Repeater {
                    model: 36

                    delegate: Rectangle {
                        id: visBar
                        readonly property real angle: (index / 36.0) * 360.0
                        readonly property real rad: angle * Math.PI / 180.0
                        readonly property real centerX: 100
                        readonly property real centerY: 100
                        readonly property real ringRadius: 72
                        readonly property real barHeight: 8 + (Math.sin(index * 1.5 + (MprisMedia.isPlaying ? Date.now() / 300 : 0)) * 6 + 6)

                        width: 3
                        height: barHeight
                        radius: 1.5
                        color: Colors.primary

                        x: centerX + Math.cos(rad) * ringRadius - width / 2
                        y: centerY + Math.sin(rad) * ringRadius - height / 2
                        rotation: angle + 90
                        transformOrigin: Item.Center
                    }
                }

                // Center Album Art Circular Disc
                Rectangle {
                    anchors.centerIn: parent
                    width: 110
                    height: 110
                    radius: 55
                    color: Colors.surfaceContainerHigh
                    border.color: Colors.primary
                    border.width: 2
                    clip: true

                    Image {
                        anchors.fill: parent
                        source: MprisMedia.artUrl || "../../theme/assets/wallpaper.webp"
                        fillMode: Image.PreserveAspectCrop
                    }

                    // Center spindle hole
                    Rectangle {
                        anchors.centerIn: parent
                        width: 18
                        height: 18
                        radius: 9
                        color: Colors.surface
                        border.color: Theme.borderSubtle
                        border.width: 1
                    }
                }
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

                // Progress Bar with Timestamps
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

                // Active Player Pill Badge (e.g. ▲ Feishin or NetEase Music)
                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    height: 24
                    width: playerRow.implicitWidth + 20
                    radius: Theme.radiusFull
                    color: Colors.surfaceContainerHigh
                    border.color: Theme.borderSubtle
                    border.width: 1

                    Row {
                        id: playerRow
                        anchors.centerIn: parent
                        spacing: 4

                        MaterialIcon {
                            text: "arrow_drop_up"
                            size: 14
                            color: Colors.primary
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            text: MprisMedia.identity || "Media Player"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontLabelSmall
                            font.weight: Font.Medium
                            color: Colors.m3onSurface
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }
            }

            // Right: Animated Boba Cat Tapping to the Beat
            Item {
                Layout.preferredWidth: 160
                Layout.preferredHeight: 160
                Layout.alignment: Qt.AlignVCenter

                AnimatedImage {
                    id: bobaCat
                    anchors.centerIn: parent
                    width: 140
                    height: 140
                    fillMode: Image.PreserveAspectFit
                    source: "../../theme/assets/bongocat.gif"
                    playing: true
                    speed: MprisMedia.isPlaying ? 1.0 : 0.4
                }
            }
        }
    }
}
