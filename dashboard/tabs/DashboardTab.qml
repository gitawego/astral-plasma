import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../components"
import "../../services"

Item {
    id: root

    implicitWidth: 940
    implicitHeight: 360

    RowLayout {
        anchors.fill: parent
        spacing: Theme.spaceMedium

        // ========================================================
        // LEFT SECTION (2 rows: Row 0 has Weather + Host Card; Row 1 has Clock + Calendar + Sliders)
        // ========================================================
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Theme.spaceMedium

            // ROW 0: Weather + Host Profile
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 110
                Layout.minimumHeight: 110
                Layout.maximumHeight: 110
                Layout.fillHeight: false
                spacing: Theme.spaceMedium

                // Card 1: Weather Widget (~280px)
                Card {
                    Layout.preferredWidth: 280
                    Layout.fillHeight: true
                    radius: 20

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 18
                        spacing: 16

                        MaterialIcon {
                            text: WeatherService.weatherIcon || "wb_sunny"
                            size: 46
                            color: Colors.primary
                        }

                        Column {
                            Layout.fillWidth: true
                            spacing: 3

                            Text {
                                text: WeatherService.temp || "18°C"
                                font.family: Theme.fontFamily
                                font.pixelSize: 26
                                font.weight: Font.DemiBold
                                color: Colors.primary
                            }

                            Text {
                                text: WeatherService.condition || "Clear"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontBodyMedium
                                color: Colors.onSurfaceVariant
                            }
                        }
                    }
                }

                // Card 2: User Profile & System Host Card (~430px)
                Card {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 20

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 18
                        spacing: 18

                        // Avatar
                        Rectangle {
                            width: 64
                            height: 64
                            radius: 32
                            color: Colors.primaryContainer
                            clip: true
                            border.color: Theme.borderSubtle
                            border.width: 1

                            Image {
                                anchors.fill: parent
                                source: "../../theme/assets/dino.png"
                                fillMode: Image.PreserveAspectCrop
                            }
                        }

                        // System info details
                        Column {
                            Layout.fillWidth: true
                            spacing: 4

                            Row {
                                spacing: 8
                                Text { text: "󰣇"; font.family: "JetBrainsMono Nerd Font"; color: Colors.primary; font.pixelSize: 14 }
                                Text { text: ": " + (SystemService.distroName || "CachyOS Linux"); font.family: Theme.fontFamily; font.pixelSize: 13; font.weight: Font.Medium; color: Colors.textOnSurface }
                            }
                            Row {
                                spacing: 8
                                Text { text: "󰨇"; font.family: "JetBrainsMono Nerd Font"; color: Colors.primary; font.pixelSize: 14 }
                                Text { text: ": " + (SystemService.compositor || "KDE Plasma 6 (KWin)"); font.family: Theme.fontFamily; font.pixelSize: 12; color: Colors.textOnSurfaceVariant }
                            }
                            Row {
                                spacing: 8
                                Text { text: "󰥔"; font.family: "JetBrainsMono Nerd Font"; color: Colors.primary; font.pixelSize: 14 }
                                Text { text: ": " + (SystemService.uptime || "up 2 hours, 15 minutes"); font.family: Theme.fontFamily; font.pixelSize: 12; color: Colors.textOnSurfaceVariant }
                            }
                        }
                    }
                }
            }

            // ROW 1: DateTime Clock + Monthly Calendar + Resource Sliders
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Theme.spaceMedium

                // Card 3: DateTime Clock (~110px)
                Card {
                    Layout.preferredWidth: 110
                    Layout.fillHeight: true
                    radius: 20

                    Column {
                        anchors.centerIn: parent
                        spacing: 1

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: Qt.formatDateTime(new Date(), "HH")
                            font.family: Theme.fontFamily
                            font.pixelSize: 26
                            font.weight: Font.DemiBold
                            color: Colors.primary
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "•••"
                            font.pixelSize: 10
                            color: Colors.primary
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: Qt.formatDateTime(new Date(), "mm")
                            font.family: Theme.fontFamily
                            font.pixelSize: 26
                            font.weight: Font.DemiBold
                            color: Colors.primary
                        }
                        Item { width: 1; height: 6 }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: Qt.formatDateTime(new Date(), "ddd, d")
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.weight: Font.Medium
                            color: Colors.onSurfaceVariant
                        }
                    }
                }

                // Card 4: Month Calendar Grid (exact layout matching upstream Caelestia)
                Card {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 20

                    Item {
                        id: calWidget
                        anchors.fill: parent
                        anchors.margins: 12

                        readonly property var today: new Date()
                        readonly property int currYear: today.getFullYear()
                        readonly property int currMonth: today.getMonth()
                        readonly property int currDay: today.getDate()

                        readonly property int daysInMonth: new Date(currYear, currMonth + 1, 0).getDate()
                        readonly property int daysInPrevMonth: new Date(currYear, currMonth, 0).getDate()
                        readonly property int startOffset: (new Date(currYear, currMonth, 1).getDay() + 6) % 7

                        Column {
                            anchors.centerIn: parent
                            spacing: 4

                            // Weekday headers
                            Row {
                                spacing: 12
                                Repeater {
                                    model: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
                                    Text {
                                        width: 28
                                        text: modelData
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        font.weight: Font.Medium
                                        color: Colors.onSurfaceVariant
                                        horizontalAlignment: Text.AlignHCenter
                                    }
                                }
                            }

                            // Calendar Days Grid (5 rows of 7 = 35 items)
                            Grid {
                                columns: 7
                                spacing: 4

                                Repeater {
                                    model: 35

                                    delegate: Rectangle {
                                        width: 28
                                        height: 23
                                        radius: Theme.radiusFull

                                        readonly property bool isPrevMonth: index < calWidget.startOffset
                                        readonly property bool isNextMonth: index >= (calWidget.startOffset + calWidget.daysInMonth)
                                        readonly property bool isCurrMonth: !isPrevMonth && !isNextMonth

                                        readonly property int dayNum: {
                                            if (isPrevMonth) {
                                                return calWidget.daysInPrevMonth - calWidget.startOffset + index + 1;
                                            } else if (isCurrMonth) {
                                                return index - calWidget.startOffset + 1;
                                            } else {
                                                return index - calWidget.startOffset - calWidget.daysInMonth + 1;
                                            }
                                        }

                                        readonly property bool isToday: isCurrMonth && (dayNum === calWidget.currDay)

                                        color: isToday ? Colors.primary : "transparent"

                                        Text {
                                            anchors.centerIn: parent
                                            text: dayNum
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 11
                                            font.weight: isToday ? Font.Bold : Font.Normal
                                            color: isToday ? Colors.textOnPrimary : (isCurrMonth ? Colors.textOnSurface : Qt.alpha(Colors.textOnSurfaceVariant, 0.35))
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Card 5: Resource Level Bars (~150px)
                Card {
                    Layout.preferredWidth: 150
                    Layout.fillHeight: true
                    radius: 20

                    Row {
                        anchors.centerIn: parent
                        spacing: 12

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
                            iconText: "memory"
                            fillColor: Colors.secondary
                        }
                    }
                }
            }
        }

        // ========================================================
        // RIGHT SECTION: Card 6 Tall Media Player (Spanning full height ~315px, width ~215px)
        // ========================================================
        Card {
            Layout.preferredWidth: 215
            Layout.fillHeight: true
            radius: 24

            Column {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 6

                // Circular album artwork with progress arc
                Item {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 104
                    height: 104

                    // Progress ring
                    Canvas {
                        id: mediaProgRing
                        anchors.fill: parent
                        property real prog: MprisMedia.progress

                        onProgChanged: requestPaint()
                        onPaint: {
                            var ctx = getContext("2d");
                            ctx.reset();
                            var cx = width / 2;
                            var cy = height / 2;
                            var r = (width - 8) / 2;

                            // Background arc track
                            ctx.beginPath();
                            ctx.arc(cx, cy, r, 0, 2 * Math.PI);
                            ctx.strokeStyle = Qt.alpha(Colors.outline, 0.25);
                            ctx.lineWidth = 4;
                            ctx.stroke();

                            // Active progress arc
                            if (prog > 0) {
                                ctx.beginPath();
                                ctx.arc(cx, cy, r, -0.5 * Math.PI, -0.5 * Math.PI + Math.min(1.0, prog) * 2 * Math.PI);
                                ctx.strokeStyle = Colors.primary;
                                ctx.lineWidth = 4;
                                ctx.lineCap = "round";
                                ctx.stroke();
                            }
                        }
                    }

                    // Album artwork in center
                    Rectangle {
                        anchors.centerIn: parent
                        width: 82
                        height: 82
                        radius: 41
                        color: Colors.primaryContainer
                        clip: true

                        Image {
                            anchors.fill: parent
                            source: MprisMedia.artUrl || "../../theme/assets/dino.png"
                            fillMode: Image.PreserveAspectCrop
                        }
                    }
                }

                // Track Title
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width - 12
                    text: MprisMedia.title || "No Media Playing"
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    color: Colors.onSurface
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }

                // Artist
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width - 12
                    text: MprisMedia.artist || "Unknown Artist"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Colors.onSurfaceVariant
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }

                // Playback Controls
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 8

                    PillButton {
                        iconText: "skip_previous"
                        iconSize: 14
                        implicitWidth: 32
                        implicitHeight: 32
                        onClicked: MprisMedia.previous()
                    }
                    PillButton {
                        iconText: MprisMedia.isPlaying ? "pause" : "play_arrow"
                        iconSize: 16
                        active: true
                        implicitWidth: 36
                        implicitHeight: 36
                        onClicked: MprisMedia.togglePlay()
                    }
                    PillButton {
                        iconText: "skip_next"
                        iconSize: 14
                        implicitWidth: 32
                        implicitHeight: 32
                        onClicked: MprisMedia.next()
                    }
                }

                Item { Layout.fillHeight: true }

                // Animated Bongo Cat
                AnimatedImage {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 68
                    height: 38
                    source: "../../theme/assets/bongocat.gif"
                    playing: MprisMedia.isPlaying
                    fillMode: Image.PreserveAspectFit
                }
            }
        }
    }
}
