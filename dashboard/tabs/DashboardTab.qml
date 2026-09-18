import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import "../../theme"
import "../../components"
import "../../services"
import "../../config"

Item {
    id: root

    implicitWidth: 940
    implicitHeight: 360

    property var currentDate: new Date()
    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.currentDate = new Date()
    }

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
                    radius: Theme.radiusGlassCard

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
                                color: "#FFFFFF"
                            }

                            Text {
                                text: WeatherService.condition || "Clear"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontBodyMedium
                                color: Qt.alpha("#FFFFFF", 0.70)
                            }
                        }
                    }
                }

                // Card 2: User Profile & System Host Card (~430px)
                Card {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Theme.radiusGlassCard

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
                    radius: Theme.radiusGlassCard

                    Column {
                        anchors.centerIn: parent
                        spacing: 1

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: Qt.formatDateTime(root.currentDate, "HH")
                            font.family: Theme.fontFamily
                            font.pixelSize: 26
                            font.weight: Font.DemiBold
                            color: "#FFFFFF"
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "•••"
                            font.pixelSize: 10
                            color: Colors.primary
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: Qt.formatDateTime(root.currentDate, "mm")
                            font.family: Theme.fontFamily
                            font.pixelSize: 26
                            font.weight: Font.DemiBold
                            color: "#FFFFFF"
                        }
                        Item { width: 1; height: 6 }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: Qt.formatDateTime(root.currentDate, "ddd, d MMM")
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.weight: Font.Medium
                            color: Qt.alpha("#FFFFFF", 0.70)
                        }
                    }
                }

                // Card 4: Month Calendar Grid (exact layout matching upstream Caelestia)
                Card {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Theme.radiusGlassCard

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
                    radius: Theme.radiusGlassCard

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
            id: mediaCard
            Layout.preferredWidth: 215
            Layout.fillHeight: true
            radius: Theme.radiusGlassCard
            color: Colors.glassCardVibrant
            clip: true

            readonly property bool isSpeakerStyle: (typeof Config !== "undefined") &&
                (Config.mediaVisualizerStyle === "speaker" || Config.mediaVisualizerStyle === "heatmap")

            // Visualizer Switcher Pill Button (Top-Right of Media Card)
            Rectangle {
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.topMargin: 8
                anchors.rightMargin: 8
                z: 50
                width: 24
                height: 24
                radius: 12
                color: dashVizHover.containsMouse ? Qt.alpha(Colors.primary, 0.28) : Qt.alpha(Colors.surfaceContainerHigh, 0.85)
                border.color: dashVizHover.containsMouse ? Colors.primary : Qt.alpha(Colors.outlineVariant, 0.4)
                border.width: 1

                Behavior on color { ColorAnimation { duration: 150 } }
                Behavior on border.color { ColorAnimation { duration: 150 } }

                MaterialIcon {
                    anchors.centerIn: parent
                    text: mediaCard.isSpeakerStyle ? "album" : "speaker"
                    size: 14
                    color: dashVizHover.containsMouse ? Colors.primary : Colors.m3onSurfaceVariant
                }

                MouseArea {
                    id: dashVizHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (typeof Config !== "undefined" && Config.setMediaVisualizerStyle) {
                            Config.setMediaVisualizerStyle(mediaCard.isSpeakerStyle ? "radial" : "speaker");
                        }
                    }
                }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.topMargin: 20
                anchors.bottomMargin: 16
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 0

                // Top spacer: gently pushes down the circular cover and notes
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 12
                }

                // Circular album artwork with progress arc
                Item {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: 120
                    Layout.preferredHeight: 120

                    // 1. Dynamic Audio Heatmap Wave Ring & Thermal Aura (Speaker / Heatmap Style)
                    HeatmapCoverRing {
                        anchors.centerIn: parent
                        innerRadius: 44
                        outerRadius: 53
                        visible: mediaCard.isSpeakerStyle
                        isTargetVisible: (typeof Config !== "undefined") ? (Config.dashboardVisible && Config.activeDashboardTab === "dashboard" && visible) : false
                    }

                    // 2. Radial Audio Spectrum Halo Ring (Radial Style)
                    RadialCoverRing {
                        anchors.centerIn: parent
                        innerRadius: 58
                        visible: !mediaCard.isSpeakerStyle
                        isTargetVisible: (typeof Config !== "undefined") ? (Config.dashboardVisible && Config.activeDashboardTab === "dashboard" && visible) : false
                    }

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
                            ctx.strokeStyle = Qt.alpha(Colors.outline, 0.22);
                            ctx.lineWidth = 3.5;
                            ctx.stroke();

                            // Active progress arc
                            if (prog > 0) {
                                ctx.beginPath();
                                ctx.arc(cx, cy, r, -0.5 * Math.PI, -0.5 * Math.PI + Math.min(1.0, prog) * 2 * Math.PI);
                                ctx.strokeStyle = Colors.primary;
                                ctx.lineWidth = 3.5;
                                ctx.lineCap = "round";
                                ctx.stroke();
                            }
                        }
                    }

                    // Circular album artwork container in center with audio beat bounce
                    Item {
                        id: albumCenterCircle
                        anchors.centerIn: parent
                        width: 86
                        height: 86
                        scale: (AudioVisualizer.active && Config.dashboardVisible && Config.activeDashboardTab === "dashboard")
                               ? (1.0 + Math.min(0.12, AudioVisualizer.beat * 0.08 + AudioVisualizer.bass * 0.06))
                               : 1.0

                        Behavior on scale {
                            NumberAnimation { duration: 60; easing.type: Easing.OutQuad }
                        }

                        // Round mask geometry (always a perfect circle)
                        Rectangle {
                            id: dashCircleMask
                            anchors.fill: parent
                            radius: width / 2
                            color: "white"
                            visible: false
                            layer.enabled: true
                        }

                        // Circular fallback placeholder (drawn underneath)
                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: Colors.primaryContainer

                            MaterialIcon {
                                anchors.centerIn: parent
                                text: "music_note"
                                size: 32
                                color: Colors.onPrimaryContainer
                            }
                        }

                        // Rotating Cover Image masked strictly to the circular boundary (1.45x size prevents corner clipping)
                        Item {
                            anchors.fill: parent
                            visible: MprisMedia.artUrl.length > 0 && dashCoverImg.status === Image.Ready

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
                                    paused: !MprisMedia.isPlaying
                                }

                                Image {
                                    id: dashCoverImg
                                    anchors.fill: parent
                                    source: MprisMedia.artUrl || ""
                                    fillMode: Image.PreserveAspectCrop
                                }
                            }

                            layer.enabled: true
                            layer.effect: MultiEffect {
                                maskEnabled: true
                                maskSource: dashCircleMask
                            }
                        }

                        // Inner border for crisp circle definition
                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: "transparent"
                            border.color: Qt.rgba(1, 1, 1, 0.15)
                            border.width: 1
                        }
                    }
                }

                // Spacer between Cover and Title
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 26
                }

                // Track Title
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: parent.width - 16
                    text: MprisMedia.title || "No Media Playing"
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    color: Colors.onSurface
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }

                Item { Layout.preferredHeight: 4 }

                // Artist
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: parent.width - 16
                    text: MprisMedia.artist || "Unknown Artist"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Colors.onSurfaceVariant
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }

                // Spacer between Text and Controls
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 12
                }

                // Playback Controls Row
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 8

                    PillButton {
                        iconText: "skip_previous"
                        iconSize: 15
                        implicitWidth: 34
                        implicitHeight: 34
                        onClicked: MprisMedia.previous()
                    }
                    PillButton {
                        iconText: MprisMedia.isPlaying ? "pause" : "play_arrow"
                        iconSize: 18
                        active: true
                        implicitWidth: 40
                        implicitHeight: 40
                        onClicked: MprisMedia.togglePlay()
                    }
                    PillButton {
                        iconText: "skip_next"
                        iconSize: 15
                        implicitWidth: 34
                        implicitHeight: 34
                        onClicked: MprisMedia.next()
                    }
                }

                // Flexible spacer absorbing remaining height
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 8
                }

                // Animated Bongo Cat
                AnimatedImage {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: 68
                    Layout.preferredHeight: 38
                    source: "../../theme/assets/bongocat.gif"
                    playing: MprisMedia.isPlaying
                    fillMode: Image.PreserveAspectFit
                }
            }
        }
    }
}
