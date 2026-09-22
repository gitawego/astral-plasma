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

    readonly property alias mediaCardItem: mediaCard
    readonly property alias vizSwitcherItem: vizSwitchBtn
    readonly property alias mediaPrevBtnItem: mediaPrevBtn
    readonly property alias mediaPlayBtnItem: mediaPlayBtn
    readonly property alias mediaNextBtnItem: mediaNextBtn
    readonly property alias calendarCardItem: calendarCard
    readonly property alias calWidgetItem: calWidget

    /// Durable avatar for the system-host card ("" = bundled default art).
    readonly property string hostAvatarSource: root.resolveAvatarSource(Config.hostAvatar)
    property alias hostAvatarImageItem: hostAvatarImg
    property alias hostAvatarCircle: avatarCircle
    property alias hostAvatarMaskItem: avatarMask
    property alias hostAvatarArtItem: avatarArt
    property alias hostAvatarBorderItem: avatarBorder

    // Circle background: configurable color + transparency (Config defaults
    // are white @ 0.2; literals keep the inert-harness case identical).
    readonly property string hostAvatarBgColor: (typeof Config !== "undefined" && Config.hostAvatarBg) ? Config.hostAvatarBg : "#ffffff"
    readonly property real hostAvatarBgOpacity: (typeof Config !== "undefined" && Config.hostAvatarBgOpacity !== undefined && !isNaN(Config.hostAvatarBgOpacity)) ? Number(Config.hostAvatarBgOpacity) : 0.2
    readonly property color hostAvatarBackgroundColor: root.resolveAvatarBg(hostAvatarBgColor, hostAvatarBgOpacity)

    /// "" -> bundled default art (relative to this file, so it resolves in
    /// the shell and in the offscreen test harness alike); absolute path ->
    /// file:// URL; an existing file:// URL passes through unchanged.
    function resolveAvatarSource(configured) {
        const p = (configured || "").trim();
        if (p === "") return "../../theme/assets/dino.png";
        if (p.startsWith("file://")) return p;
        return "file://" + p;
    }

    /// Avatar-circle background from a configurable hex color + transparency.
    /// Invalid colors fall back to white; opacity clamps to 0..1 and falls
    /// back to the shipped default 0.2 (white @ 20%).
    function resolveAvatarBg(colorStr, opacity) {
        let a = Number(opacity);
        if (isNaN(a)) a = 0.2;
        a = Math.max(0, Math.min(1, a));
        const digits = String(colorStr === undefined || colorStr === null ? "" : colorStr)
            .trim().toLowerCase().replace(/^#/, "");
        if (!/^[0-9a-f]{6}$/.test(digits)) {
            return Qt.rgba(1, 1, 1, a);
        }
        const n = parseInt(digits, 16);
        return Qt.rgba(((n >> 16) & 255) / 255, ((n >> 8) & 255) / 255, (n & 255) / 255, a);
    }

    // Suppresses the real calendar launch in offscreen tests; the pure date
    // computation and the dateClicked signal remain fully testable.
    property bool testMode: false

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
                                color: Colors.textMain
                                style: Text.Outline
                                styleColor: Colors.glassTextHalo
                            }

                            Text {
                                text: WeatherService.condition || "Clear"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontBodyMedium
                                color: Colors.textMuted
                                style: Text.Outline
                                styleColor: Colors.glassTextHalo
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

                        // Avatar (durable, configurable via Settings > Dashboard)
                        Rectangle {
                            id: avatarCircle
                            width: 64
                            height: 64
                            radius: 32
                            color: root.hostAvatarBackgroundColor
                            clip: true

                            // True-circle mask (repo album-cover pattern):
                            // Rectangle.clip only clips children to the bounding
                            // box, which let square image corners leak over the
                            // card - the mask clips the artwork to the radius.
                            Rectangle {
                                id: avatarMask
                                anchors.fill: parent
                                radius: width / 2
                                color: "white"
                                visible: false
                                layer.enabled: true
                            }

                            Item {
                                id: avatarArt
                                anchors.fill: parent
                                layer.enabled: true
                                layer.effect: MultiEffect {
                                    maskEnabled: true
                                    maskSource: avatarMask
                                }

                                Image {
                                    id: hostAvatarImg
                                    anchors.fill: parent
                                    source: root.hostAvatarSource
                                    // CONTAIN + CENTER: the full image is always
                                    // visible, letterboxed and centered inside the
                                    // circle - the shell never crops or reframes;
                                    // choosing a correctly sized image is the
                                    // user's call. Transparent art shows the circle
                                    // tint underneath.
                                    fillMode: Image.PreserveAspectFit
                                }
                            }

                            // Inner border for crisp circle definition (stacked
                            // above the artwork, matching the album cover).
                            Rectangle {
                                id: avatarBorder
                                anchors.fill: parent
                                radius: width / 2
                                color: "transparent"
                                border.color: Theme.borderSubtle
                                border.width: 1
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
                            color: Colors.textMain
                            style: Text.Outline
                            styleColor: Colors.glassTextHalo
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "•••"
                            font.pixelSize: 10
                            color: Colors.primary
                            style: Text.Outline
                            styleColor: Colors.glassTextHalo
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: Qt.formatDateTime(root.currentDate, "mm")
                            font.family: Theme.fontFamily
                            font.pixelSize: 26
                            font.weight: Font.DemiBold
                            color: Colors.textMain
                            style: Text.Outline
                            styleColor: Colors.glassTextHalo
                        }
                        Item { width: 1; height: 6 }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: Qt.formatDateTime(root.currentDate, "ddd, d MMM")
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.weight: Font.Medium
                            color: Colors.textMuted
                            style: Text.Outline
                            styleColor: Colors.glassTextHalo
                        }
                    }
                }

                // Card 4: Month Calendar Grid (Enlarged, Aligned, Uncropped)
                Card {
                    id: calendarCard
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Theme.radiusGlassCard

                    Item {
                        id: calWidget
                        anchors.fill: parent
                        anchors.margins: 10

                        signal dateClicked(string isoDate)
                        property string lastClickedDate: ""

                        readonly property var today: new Date()
                        readonly property int currYear: today.getFullYear()
                        readonly property int currMonth: today.getMonth()
                        readonly property int currDay: today.getDate()

                        readonly property int daysInMonth: new Date(currYear, currMonth + 1, 0).getDate()
                        readonly property int daysInPrevMonth: new Date(currYear, currMonth, 0).getDate()
                        readonly property int startOffset: (new Date(currYear, currMonth, 1).getDay() + 6) % 7
                        readonly property int totalCells: (startOffset + daysInMonth > 35) ? 42 : 35

                        readonly property real cellWidth: 42
                        readonly property real cellHeight: 26
                        readonly property real colSpacing: 6
                        readonly property real headerColSpacing: colSpacing
                        readonly property real rowSpacing: 4
                        readonly property int fontSize: 13

                        /// Calendar date for a grid cell, accounting for the
                        /// leading/trailing overflow days with year rollover.
                        /// Returns { year, month (1-12), day }.
                        function dateForCell(cellIndex) {
                            var y = calWidget.currYear;
                            var m = calWidget.currMonth;
                            var d;
                            if (cellIndex < calWidget.startOffset) {
                                d = calWidget.daysInPrevMonth - calWidget.startOffset + cellIndex + 1;
                                m -= 1;
                                if (m < 0) {
                                    m = 11;
                                    y -= 1;
                                }
                            } else if (cellIndex >= calWidget.startOffset + calWidget.daysInMonth) {
                                d = cellIndex - calWidget.startOffset - calWidget.daysInMonth + 1;
                                m += 1;
                                if (m > 11) {
                                    m = 0;
                                    y += 1;
                                }
                            } else {
                                d = cellIndex - calWidget.startOffset + 1;
                            }
                            return { "year": y, "month": m + 1, "day": d };
                        }

                        /// Clicked day in YYYY-MM-DD form for the daemon's
                        /// `calendar open` command.
                        function isoForCell(cellIndex) {
                            var p = calWidget.dateForCell(cellIndex);
                            function pad(n) {
                                return (n < 10 ? "0" : "") + n;
                            }
                            return p.year + "-" + pad(p.month) + "-" + pad(p.day);
                        }

                        /// Open the system's default calendar application for
                        /// the clicked cell (data-driven via XDG MIME).
                        function openDateForCell(cellIndex) {
                            var iso = calWidget.isoForCell(cellIndex);
                            calWidget.lastClickedDate = iso;
                            calWidget.dateClicked(iso);
                            if (!root.testMode && typeof WindowService !== "undefined" && WindowService.openCalendar) {
                                WindowService.openCalendar(iso);
                            }
                        }

                        Column {
                            anchors.centerIn: parent
                            spacing: 6

                            // Weekday headers - identical colSpacing & cellWidth
                            Row {
                                spacing: calWidget.colSpacing
                                Repeater {
                                    model: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
                                    Text {
                                        width: calWidget.cellWidth
                                        text: modelData
                                        font.family: Theme.fontFamily
                                        font.pixelSize: calWidget.fontSize
                                        font.weight: Font.DemiBold
                                        color: Colors.onSurfaceVariant
                                        style: Text.Outline
                                        styleColor: Colors.glassTextHalo
                                        horizontalAlignment: Text.AlignHCenter
                                    }
                                }
                            }

                            // Calendar Days Grid (columns: 7, identical cellWidth & colSpacing)
                            Grid {
                                columns: 7
                                columnSpacing: calWidget.colSpacing
                                rowSpacing: calWidget.rowSpacing

                                Repeater {
                                    model: calWidget.totalCells

                                    delegate: Item {
                                        width: calWidget.cellWidth
                                        height: calWidget.cellHeight

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

                                        // Today highlight pill/circle
                                        Rectangle {
                                            anchors.centerIn: parent
                                            width: 32
                                            height: 26
                                            radius: 13
                                            visible: isToday
                                            color: Colors.primary
                                        }

                                        // Hover halo for the interactive date cell.
                                        // Hidden on today's pill (zero-overlap partitioning:
                                        // two translucent fills would leave a dark seam).
                                        Rectangle {
                                            anchors.centerIn: parent
                                            width: 32
                                            height: 26
                                            radius: 13
                                            visible: dayHover.containsMouse && !isToday
                                            color: dayHover.pressed ? Qt.alpha(Colors.primary, 0.32)
                                                                   : Qt.alpha(Colors.primary, 0.18)
                                            opacity: dayHover.containsMouse ? 1.0 : 0.0
                                            Behavior on opacity {
                                                NumberAnimation {
                                                    duration: Theme.animExpressiveFastEffects
                                                    easing.type: Easing.BezierSpline
                                                    easing.bezierCurve: Theme.curveExpressiveFastEffects
                                                }
                                            }
                                        }

                                        Text {
                                            anchors.centerIn: parent
                                            text: dayNum
                                            font.family: Theme.fontFamily
                                            font.pixelSize: calWidget.fontSize
                                            font.weight: isToday ? Font.Bold : (isCurrMonth ? Font.DemiBold : Font.Normal)
                                            color: isToday ? Colors.textOnPrimary : (isCurrMonth ? Colors.textOnSurface : Qt.alpha(Colors.textOnSurfaceVariant, 0.45))
                                        }

                                        MouseArea {
                                            id: dayHover
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            Accessible.role: Accessible.Button
                                            Accessible.name: "Open calendar for " + calWidget.isoForCell(index)
                                            onClicked: calWidget.openDateForCell(index)
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
            clip: true

            readonly property bool isSpeakerStyle: (typeof Config !== "undefined") &&
                (Config.mediaVisualizerStyle === "speaker" || Config.mediaVisualizerStyle === "heatmap")

            // Visualizer Switcher Pill Button (Top-Right of Media Card)
            LiquidGlassButton {
                id: vizSwitchBtn
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.topMargin: 8
                anchors.rightMargin: 8
                z: 50
                implicitWidth: 28
                implicitHeight: 28
                paddingHorizontal: 6
                paddingVertical: 6
                iconText: mediaCard.isSpeakerStyle ? "album" : "speaker"
                iconSize: 14
                elevation: 4
                onClicked: {
                    if (typeof Config !== "undefined" && Config.setMediaVisualizerStyle) {
                        Config.setMediaVisualizerStyle(mediaCard.isSpeakerStyle ? "radial" : "speaker");
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
                    style: Text.Outline
                    styleColor: Colors.glassTextHalo
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
                    style: Text.Outline
                    styleColor: Colors.glassTextHalo
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

                    LiquidGlassButton {
                        id: mediaPrevBtn
                        iconText: "skip_previous"
                        iconSize: 15
                        implicitWidth: 34
                        implicitHeight: 34
                        paddingHorizontal: 8
                        paddingVertical: 8
                        elevation: 4
                        interactive: (typeof MprisMedia !== "undefined") ? MprisMedia.canGoPrevious : true
                        opacity: ((typeof MprisMedia !== "undefined") ? MprisMedia.canGoPrevious : true) ? 1.0 : 0.45
                        onClicked: MprisMedia.previous()
                    }
                    LiquidGlassButton {
                        id: mediaPlayBtn
                        iconText: (typeof MprisMedia !== "undefined" && MprisMedia.isPlaying) ? "pause" : "play_arrow"
                        iconSize: 18
                        isPrimary: true
                        implicitWidth: 42
                        implicitHeight: 42
                        paddingHorizontal: 10
                        paddingVertical: 10
                        elevation: 6
                        onClicked: MprisMedia.togglePlay()
                    }
                    LiquidGlassButton {
                        id: mediaNextBtn
                        iconText: "skip_next"
                        iconSize: 15
                        implicitWidth: 34
                        implicitHeight: 34
                        paddingHorizontal: 8
                        paddingVertical: 8
                        elevation: 4
                        interactive: (typeof MprisMedia !== "undefined") ? MprisMedia.canGoNext : true
                        opacity: ((typeof MprisMedia !== "undefined") ? MprisMedia.canGoNext : true) ? 1.0 : 0.45
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
