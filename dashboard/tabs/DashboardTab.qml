import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../components"
import "../../services"

Item {
    id: root

    implicitWidth: 680
    implicitHeight: 320

    GridLayout {
        anchors.fill: parent
        columns: 3
        columnSpacing: Theme.spaceMedium
        rowSpacing: Theme.spaceMedium

        // Card 1: Weather Widget
        Card {
            Layout.fillWidth: true
            Layout.preferredHeight: 110
            radius: Theme.radiusLarge

            RowLayout {
                anchors.fill: parent
                anchors.margins: Theme.padLarge
                spacing: Theme.spaceMedium

                MaterialIcon {
                    text: WeatherService.weatherIcon
                    size: 42
                    color: Colors.primary
                }

                Column {
                    Layout.fillWidth: true
                    Text {
                        text: WeatherService.temp
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontTitleLarge
                        font.weight: Font.Bold
                        color: Colors.m3onSurface
                    }
                    Text {
                        text: WeatherService.condition
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontBodyMedium
                        color: Colors.m3onSurfaceVariant
                    }
                }
            }
        }

        // Card 2: User Profile & System Card
        Card {
            Layout.columnSpan: 2
            Layout.fillWidth: true
            Layout.preferredHeight: 110
            radius: Theme.radiusLarge

            RowLayout {
                anchors.fill: parent
                anchors.margins: Theme.padLarge
                spacing: Theme.spaceLarge

                // Avatar
                Rectangle {
                    width: 56
                    height: 56
                    radius: Theme.radiusFull
                    color: Colors.primaryContainer
                    clip: true

                    Image {
                        anchors.fill: parent
                        source: "../../theme/assets/dino.png"
                        fillMode: Image.PreserveAspectCrop
                    }
                }

                // System info details
                Column {
                    Layout.fillWidth: true
                    spacing: 3

                    Row {
                        spacing: Theme.spaceSmall
                        Text { text: "󰣇"; font.family: "JetBrainsMono Nerd Font"; color: Colors.primary; font.pixelSize: 14 }
                        Text { text: SystemService.distroName; font.family: Theme.fontFamily; font.pixelSize: Theme.fontBodyMedium; font.weight: Font.DemiBold; color: Colors.m3onSurface }
                    }
                    Row {
                        spacing: Theme.spaceSmall
                        Text { text: "󰨇"; font.family: "JetBrainsMono Nerd Font"; color: Colors.primary; font.pixelSize: 14 }
                        Text { text: SystemService.compositor; font.family: Theme.fontFamily; font.pixelSize: Theme.fontBodySmall; color: Colors.m3onSurfaceVariant }
                    }
                    Row {
                        spacing: Theme.spaceSmall
                        Text { text: "󰥔"; font.family: "JetBrainsMono Nerd Font"; color: Colors.primary; font.pixelSize: 14 }
                        Text { text: SystemService.uptime; font.family: Theme.fontFamily; font.pixelSize: Theme.fontBodySmall; color: Colors.m3onSurfaceVariant }
                    }
                }
            }
        }

        // Card 3: Clock + Mini Calendar (Spans 2 columns)
        Card {
            Layout.columnSpan: 2
            Layout.fillWidth: true
            Layout.preferredHeight: 190
            radius: Theme.radiusLarge

            RowLayout {
                anchors.fill: parent
                anchors.margins: Theme.padLarge
                spacing: Theme.spaceLarge

                // Left: Vertical Date/Clock
                Column {
                    spacing: 2
                    Text {
                        text: Qt.formatDateTime(new Date(), "HH")
                        font.family: Theme.fontFamily
                        font.pixelSize: 26
                        font.weight: Font.Bold
                        color: Colors.m3onSurface
                    }
                    Text {
                        text: "•••"
                        font.pixelSize: 10
                        color: Colors.primary
                    }
                    Text {
                        text: Qt.formatDateTime(new Date(), "mm")
                        font.family: Theme.fontFamily
                        font.pixelSize: 26
                        font.weight: Font.Bold
                        color: Colors.m3onSurface
                    }
                    Item { width: 1; height: 4 }
                    Text {
                        text: Qt.formatDateTime(new Date(), "ddd, d")
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontBodySmall
                        color: Colors.m3onSurfaceVariant
                    }
                }

                Rectangle { width: 1; Layout.fillHeight: true; color: Theme.borderSubtle }

                // Center: Mini Month Calendar Grid
                Column {
                    Layout.fillWidth: true
                    spacing: 6

                    // Weekday headers
                    Row {
                        spacing: 12
                        Repeater {
                            model: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
                            Text {
                                width: 24
                                text: modelData
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontLabelSmall
                                color: Colors.m3onSurfaceVariant
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }
                    }

                    // Calendar numbers grid
                    Grid {
                        columns: 7
                        spacing: 6

                        Repeater {
                            model: 28 // 4 weeks representation

                            delegate: Rectangle {
                                width: 24
                                height: 24
                                radius: Theme.radiusFull

                                readonly property int dayNum: index + 1
                                readonly property bool isToday: dayNum === (new Date().getDate())

                                color: isToday ? Colors.primary : "transparent"

                                Text {
                                    anchors.centerIn: parent
                                    text: dayNum
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontLabelSmall
                                    font.weight: isToday ? Font.Bold : Font.Normal
                                    color: isToday ? Colors.m3onPrimary : Colors.m3onSurface
                                }
                            }
                        }
                    }
                }

                Rectangle { width: 1; Layout.fillHeight: true; color: Theme.borderSubtle }

                // Right: 4 Vertical Resource Level Bars
                Row {
                    spacing: Theme.spaceMedium
                    Layout.alignment: Qt.AlignVCenter

                    LevelBar {
                        value: PipewireAudio.volume
                        iconText: "volume_up"
                        interactive: true
                        onValueModified: val => PipewireAudio.setVolume(val)
                    }
                    LevelBar {
                        value: BrightnessService.normalized
                        iconText: "brightness"
                        interactive: true
                        onValueModified: val => BrightnessService.setBrightness(val)
                    }
                    LevelBar {
                        value: PowerService.percentage
                        iconText: "battery"
                    }
                    LevelBar {
                        value: SystemService.ramUsage
                        iconText: "performance"
                        fillColor: Colors.secondary
                    }
                }
            }
        }

        // Card 4: Mini Media Player + Boba Cat (Spans 1 column)
        Card {
            Layout.fillWidth: true
            Layout.preferredHeight: 190
            radius: Theme.radiusLarge

            Column {
                anchors.fill: parent
                anchors.margins: Theme.padMedium
                spacing: 6

                // Circular album artwork
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 54
                    height: 54
                    radius: Theme.radiusFull
                    color: Colors.primaryContainer
                    clip: true

                    Image {
                        anchors.fill: parent
                        source: MprisMedia.artUrl || "../../theme/assets/dino.png"
                        fillMode: Image.PreserveAspectCrop
                    }
                }

                // Track title & artist
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width - Theme.padSmall * 2
                    text: MprisMedia.title
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontBodySmall
                    font.weight: Font.DemiBold
                    color: Colors.m3onSurface
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width - Theme.padSmall * 2
                    text: MprisMedia.artist
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontLabelSmall
                    color: Colors.m3onSurfaceVariant
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }

                // Playback controls
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Theme.spaceSmall

                    PillButton {
                        iconText: "prev"
                        iconSize: 14
                        implicitWidth: 28
                        implicitHeight: 28
                        onClicked: MprisMedia.previous()
                    }
                    PillButton {
                        iconText: MprisMedia.isPlaying ? "pause" : "play"
                        iconSize: 14
                        active: true
                        implicitWidth: 32
                        implicitHeight: 32
                        onClicked: MprisMedia.togglePlay()
                    }
                    PillButton {
                        iconText: "next"
                        iconSize: 14
                        implicitWidth: 28
                        implicitHeight: 28
                        onClicked: MprisMedia.next()
                    }
                }

                // Animated Boba Cat
                AnimatedImage {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 48
                    height: 28
                    source: "../../theme/assets/bongocat.gif"
                    playing: MprisMedia.isPlaying
                    fillMode: Image.PreserveAspectFit
                }
            }
        }
    }
}
