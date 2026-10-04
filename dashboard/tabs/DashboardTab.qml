import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import "../../components/motion"
import "../../theme"
import "../../components"
import "../../services"
import "../../config"

Item {
    id: root

    implicitWidth: 940
    implicitHeight: 312

    readonly property alias mediaCardItem: mediaCard
    readonly property alias vizSwitcherItem: vizSwitchBtn
    readonly property alias mediaPrevBtnItem: mediaPrevBtn
    readonly property alias mediaPlayBtnItem: mediaPlayBtn
    readonly property alias mediaNextBtnItem: mediaNextBtn
    readonly property alias calendarCardItem: calendarCard
    readonly property alias calWidgetItem: calWidget
    readonly property alias telemetryCardItem: telemetryCard
    readonly property alias cpuBarItem: cpuMeter
    readonly property alias ramBarItem: ramMeter
    readonly property alias diskBarItem: diskMeter

    /// Configurable mascot / companion for the media card ("" = default bongocat.gif).
    readonly property string mascotSource: root.resolveMascotSource((typeof Config !== "undefined") ? Config.bongoCatAvatar : "")
    property alias mascotItem: mascotImg

    function resolveMascotSource(configured) {
        const p = (configured || "").trim();
        if (p === "") return "../../theme/assets/bongocat.gif";
        if (p.startsWith("file://")) return p;
        return "file://" + p;
    }

    /// Durable avatar for the system-host card ("" = bundled default art).
    readonly property string hostAvatarSource: root.resolveAvatarSource((typeof Config !== "undefined") ? Config.hostAvatar : "")
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

    readonly property bool isTargetVisible: testMode || ((typeof Config !== "undefined" ? Config.dashboardVisible : true) && visible)

    property var currentDate: new Date()
    Timer {
        interval: 1000
        running: root.isTargetVisible
        repeat: true
        triggeredOnStart: true
        onRunningChanged: {
            if (running) {
                root.currentDate = new Date();
            }
        }
        onTriggered: root.currentDate = new Date()
    }

    Component.onCompleted: {
        if (!testMode && typeof SystemService !== "undefined" && SystemService.registerClient) {
            SystemService.registerClient(root, root.isTargetVisible);
        }
    }
    Component.onDestruction: {
        if (!testMode && typeof SystemService !== "undefined" && SystemService.unregisterClient) {
            SystemService.unregisterClient(root);
        }
    }
    onIsTargetVisibleChanged: {
        if (!testMode && typeof SystemService !== "undefined" && SystemService.registerClient) {
            SystemService.registerClient(root, root.isTargetVisible);
        }
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
                Layout.preferredHeight: 104
                Layout.minimumHeight: 104
                Layout.maximumHeight: 104
                Layout.fillHeight: false
                spacing: Theme.spaceMedium

                // Card 1: Weather Widget (~260px)
                Card {
                    Layout.preferredWidth: 260
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
                            radius: (typeof Theme !== "undefined" && Theme.material && Theme.material.surfaceStyle === "neon_cyber") ? 0 : 32
                            color: root.hostAvatarBackgroundColor
                            clip: true

                            // True-circle mask (repo album-cover pattern):
                            // Rectangle.clip only clips children to the bounding
                            // box, which let square image corners leak over the
                            // card - the mask clips the artwork to the radius.
                            Rectangle {
                                id: avatarMask
                                anchors.fill: parent
                                radius: (typeof Theme !== "undefined" && Theme.material && Theme.material.surfaceStyle === "neon_cyber") ? 0 : width / 2
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
                                radius: (typeof Theme !== "undefined" && Theme.material && Theme.material.surfaceStyle === "neon_cyber") ? 0 : width / 2
                                color: "transparent"
                                border.color: (typeof Theme !== "undefined" && Theme.material && Theme.material.surfaceStyle === "neon_cyber") ? Colors.primary : Theme.borderSubtle
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

            // ROW 1: DateTime Clock + Monthly Calendar + Hardware Telemetry
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 196
                Layout.minimumHeight: 196
                Layout.maximumHeight: 196
                Layout.fillHeight: false
                spacing: Theme.spaceMedium

                // Card 3: DateTime Clock (~104px)
                Card {
                    Layout.preferredWidth: 104
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
                                            radius: (typeof Theme !== "undefined" && Theme.material && Theme.material.surfaceStyle === "neon_cyber") ? 0 : 13
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
                                            radius: (typeof Theme !== "undefined" && Theme.material && Theme.material.surfaceStyle === "neon_cyber") ? 0 : 13
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

                // Card 5: Hardware Resource Telemetry Meters (~100px)
                Card {
                    id: telemetryCard
                    Layout.preferredWidth: 100
                    Layout.fillHeight: true
                    radius: Theme.radiusGlassCard
                    interactive: true
                    hovered: teleHover.containsMouse

                    MouseArea {
                        id: teleHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (typeof Config !== "undefined") {
                                Config.activeDashboardTab = "performance";
                            }
                        }
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.topMargin: 12
                        anchors.bottomMargin: 14
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 0

                        // Hover stat badge
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: teleHover.containsMouse
                                ? (Math.round(SystemService.cpuUsage * 100) + "% · " + Math.round(SystemService.ramUsage * 100) + "% · " + Math.round(SystemService.diskUsage * 100) + "%")
                                : ""
                            opacity: teleHover.containsMouse ? 1.0 : 0.0
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            font.weight: Font.Medium
                            color: Colors.primary
                            style: Text.Outline
                            styleColor: Colors.glassTextHalo
                            horizontalAlignment: Text.AlignHCenter

                            Behavior on opacity {
                                NumberAnimation { duration: Theme.animExpressiveFastEffects }
                            }
                        }

                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                        }

                        // 3 Telemetry Pill Gauges (CPU, RAM, Disk)
                        Row {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: 8

                            TelemetryBar {
                                id: cpuMeter
                                value: SystemService.cpuUsage
                                barWidth: 12
                                nerdGlyph: "󰻠"
                                iconText: "cpu"
                                fillColor: SystemService.cpuUsage > 0.85 ? Colors.error : Colors.primary
                                tooltipText: "CPU: " + Math.round(SystemService.cpuUsage * 100) + "%"
                                height: 130
                            }

                            TelemetryBar {
                                id: ramMeter
                                value: SystemService.ramUsage
                                barWidth: 12
                                nerdGlyph: "󰍛"
                                iconText: "memory"
                                fillColor: SystemService.ramUsage > 0.85 ? Colors.error : Colors.secondary
                                tooltipText: "RAM: " + Math.round(SystemService.ramUsage * 100) + "%"
                                height: 130
                            }

                            TelemetryBar {
                                id: diskMeter
                                value: SystemService.diskUsage
                                barWidth: 12
                                nerdGlyph: "󰋊"
                                iconText: "hard_drive"
                                fillColor: SystemService.diskUsage > 0.85 ? Colors.error : (typeof Colors.tertiary !== "undefined" ? Colors.tertiary : Colors.primary)
                                tooltipText: "Disk: " + Math.round(SystemService.diskUsage * 100) + "%"
                                height: 130
                            }
                        }

                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
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
            Layout.preferredWidth: 220
            Layout.fillHeight: true
            radius: Theme.radiusGlassCard
            clip: true

            readonly property bool isSpeakerStyle: (typeof Config !== "undefined") &&
                (Config.mediaVisualizerStyle === "speaker" || Config.mediaVisualizerStyle === "heatmap")
            readonly property bool isCyberpunk: (typeof Theme !== "undefined" && Theme.isCyberpunk)
            readonly property bool showOrbitalRing: (typeof Theme !== "undefined" ? Theme.mediaOrbitalRing : true)
            readonly property bool isCircularCover: (typeof Theme !== "undefined" ? Theme.mediaCircularCover : true)

            // Visualizer Switcher Pill Button (Top-Right of Media Card - Hidden in Cyberpunk)
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
                iconText: "equalizer"
                iconSize: 14
                elevation: 4
                visible: mediaCard.showOrbitalRing && !mediaCard.isCyberpunk
                onClicked: {
                    if (typeof Config !== "undefined" && Config.setMediaVisualizerStyle) {
                        Config.setMediaVisualizerStyle(mediaCard.isSpeakerStyle ? "radial" : "speaker");
                    }
                }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.topMargin: 12
                anchors.bottomMargin: 8
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 0

                // Album artwork container with dynamic visualizer / progress
                Item {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: mediaCard.isCircularCover ? 104 : 96
                    Layout.preferredHeight: mediaCard.isCircularCover ? 104 : 96

                    // 1. Dynamic Audio Heatmap Wave Ring & Thermal Aura (Speaker / Heatmap Style - Non-Cyberpunk)
                    HeatmapCoverRing {
                        anchors.centerIn: parent
                        innerRadius: 38
                        outerRadius: 46
                        visible: mediaCard.showOrbitalRing && mediaCard.isSpeakerStyle && !mediaCard.isCyberpunk
                        isTargetVisible: (typeof Config !== "undefined") ? (Config.dashboardVisible && Config.activeDashboardTab === "dashboard" && visible) : false
                    }

                    // 2. Radial Audio Spectrum Halo Ring (Radial Style or Cyberpunk)
                    RadialCoverRing {
                        anchors.centerIn: parent
                        innerRadius: 42
                        visible: mediaCard.showOrbitalRing && (!mediaCard.isSpeakerStyle || mediaCard.isCyberpunk)
                        isTargetVisible: (typeof Config !== "undefined") ? (Config.dashboardVisible && Config.activeDashboardTab === "dashboard" && visible) : false
                    }

                    // Circular Progress ring (Only in non-cyberpunk orbital ring mode)
                    Canvas {
                        id: mediaProgRing
                        anchors.fill: parent
                        visible: mediaCard.showOrbitalRing && !mediaCard.isCyberpunk
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

                    // Cyber HUD Corner Brackets framing the artwork container
                    Item {
                        anchors.fill: parent
                        visible: mediaCard.isCyberpunk

                        // Top-Left Bracket
                        Item {
                            anchors.top: parent.top; anchors.left: parent.left
                            width: 8; height: 8
                            Rectangle { anchors.top: parent.top; anchors.left: parent.left; width: 8; height: 1; color: Colors.primary }
                            Rectangle { anchors.top: parent.top; anchors.left: parent.left; width: 1; height: 8; color: Colors.primary }
                        }
                        // Top-Right Bracket
                        Item {
                            anchors.top: parent.top; anchors.right: parent.right
                            width: 8; height: 8
                            Rectangle { anchors.top: parent.top; anchors.right: parent.right; width: 8; height: 1; color: Colors.primary }
                            Rectangle { anchors.top: parent.top; anchors.right: parent.right; width: 1; height: 8; color: Colors.primary }
                        }
                        // Bottom-Left Bracket
                        Item {
                            anchors.bottom: parent.bottom; anchors.left: parent.left
                            width: 8; height: 8
                            Rectangle { anchors.bottom: parent.bottom; anchors.left: parent.left; width: 8; height: 1; color: Colors.primary }
                            Rectangle { anchors.bottom: parent.bottom; anchors.left: parent.left; width: 1; height: 8; color: Colors.primary }
                        }
                        // Bottom-Right Bracket
                        Item {
                            anchors.bottom: parent.bottom; anchors.right: parent.right
                            width: 8; height: 8
                            Rectangle { anchors.bottom: parent.bottom; anchors.right: parent.right; width: 8; height: 1; color: Colors.primary }
                            Rectangle { anchors.bottom: parent.bottom; anchors.right: parent.right; width: 1; height: 8; color: Colors.primary }
                        }
                    }

                    // Album artwork tile in center with audio beat bounce
                    Item {
                        id: albumCenterCircle
                        anchors.centerIn: parent
                        width: mediaCard.isCircularCover ? 74 : 88
                        height: width
                        scale: beatBounce.value

                        MotionValue {
                            id: beatBounce
                            animated: root.isTargetVisible && (typeof AudioVisualizer !== "undefined" && AudioVisualizer.active)
                            duration: 80
                            bezier: Theme.curveExpressiveFastEffects
                            target: (typeof AudioVisualizer !== "undefined" && AudioVisualizer.active
                                     && Config.dashboardVisible && Config.activeDashboardTab === "dashboard"
                                     && AudioVisualizer.displayBeat > 0.05)
                                    ? (1.0 + Math.min(mediaCard.isCyberpunk ? 0.04 : 0.12, AudioVisualizer.displayBeat * (mediaCard.isCyberpunk ? 0.04 : 0.10)))
                                    : 1.0
                        }

                        // Mask geometry (circle in liquid/nordic, square in cyberpunk)
                        Rectangle {
                            id: dashCircleMask
                            anchors.fill: parent
                            radius: mediaCard.isCircularCover ? width / 2 : 0
                            color: "white"
                            visible: false
                            layer.enabled: true
                        }

                        // Fallback placeholder (drawn underneath)
                        Rectangle {
                            anchors.fill: parent
                            radius: mediaCard.isCircularCover ? width / 2 : 0
                            color: mediaCard.isCyberpunk ? Qt.rgba(0.04, 0.04, 0.08, 0.95) : Colors.primaryContainer

                            MaterialIcon {
                                anchors.centerIn: parent
                                text: "music_note"
                                size: mediaCard.isCircularCover ? 32 : 36
                                color: mediaCard.isCyberpunk ? Colors.primary : Colors.onPrimaryContainer
                            }
                        }

                        // Cover Image masked strictly to the boundary
                        Item {
                            anchors.fill: parent
                            visible: MprisMedia.artUrl.length > 0 && dashCoverImg.status === Image.Ready
                            rotation: (typeof Theme !== "undefined" && !Theme.mediaVinylSpin) ? 0 : (coverPacer.phase * 360)

                            Item {
                                anchors.centerIn: parent
                                width: mediaCard.isCircularCover ? (parent.width * 1.45) : parent.width
                                height: width

                                MotionPacer {
                                    id: coverPacer
                                    running: (typeof Theme !== "undefined" ? Theme.mediaVinylSpin : true) && root.isTargetVisible && MprisMedia.isPlaying
                                    period: 22000
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

                        // Inner border for crisp definition
                        Rectangle {
                            anchors.fill: parent
                            radius: mediaCard.isCircularCover ? width / 2 : 0
                            color: "transparent"
                            border.color: mediaCard.isCyberpunk ? Colors.primary : Qt.rgba(1, 1, 1, 0.15)
                            border.width: 1
                        }
                    }


                }


                // Spacer between Cover and Title
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 10
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

                Item { Layout.preferredHeight: 2 }

                // Album
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: parent.width - 16
                    visible: (typeof MprisMedia !== "undefined") && MprisMedia.album && MprisMedia.album.length > 0
                    text: (typeof MprisMedia !== "undefined") ? (MprisMedia.album || "") : ""
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    font.weight: Font.Medium
                    color: Colors.onSurfaceVariant
                    style: Text.Outline
                    styleColor: Colors.glassTextHalo
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }

                Item {
                    visible: (typeof MprisMedia !== "undefined") && MprisMedia.album && MprisMedia.album.length > 0
                    Layout.preferredHeight: 2
                }

                // Artist
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: parent.width - 16
                    text: MprisMedia.artist || "Unknown Artist"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Qt.alpha(Colors.onSurfaceVariant, 0.75)
                    style: Text.Outline
                    styleColor: Colors.glassTextHalo
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }

                // Spacer between Text and Controls
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: mediaCard.isCyberpunk ? 4 : 8
                }

                // Cyberpunk Linear Progress Bar with HUD Seek Track
                Item {
                    id: cyberProgressBar
                    visible: mediaCard.isCyberpunk
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: parent.width - 24
                    Layout.preferredHeight: 12

                    // Progress Track Background
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        height: 3
                        color: Qt.alpha(Colors.primary, 0.15)
                        border.color: Qt.alpha(Colors.primary, 0.30)
                        border.width: 1
                    }

                    // Progress Fill (Laser Cyan)
                    Rectangle {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        height: 3
                        width: Math.max(0, Math.min(parent.width, parent.width * (MprisMedia.progress || 0.0)))
                        color: Colors.primary
                    }

                    // Playhead Indicator (Magenta tick)
                    Rectangle {
                        visible: (MprisMedia.progress || 0.0) > 0.0
                        x: Math.max(0, Math.min(parent.width - 3, parent.width * (MprisMedia.progress || 0.0) - 1.5))
                        anchors.verticalCenter: parent.verticalCenter
                        width: 3
                        height: 9
                        color: Colors.secondary
                    }

                    // Interactive Seek MouseArea
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -4
                        cursorShape: Qt.PointingHandCursor
                        onClicked: function(mouse) {
                            if (typeof MprisMedia !== "undefined" && MprisMedia.canSeek && MprisMedia.length > 0) {
                                var ratio = Math.max(0.0, Math.min(1.0, mouse.x / width));
                                MprisMedia.position = ratio * MprisMedia.length;
                            }
                        }
                    }
                }


                // Spacer before Controls
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: mediaCard.isCyberpunk ? 6 : 8
                }


                // Playback Controls Row
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 8

                    LiquidGlassButton {
                        id: mediaPrevBtn
                        iconText: "skip_previous"
                        iconSize: 15
                        implicitWidth: 32
                        implicitHeight: 32
                        paddingHorizontal: 6
                        paddingVertical: 6
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
                        implicitWidth: 38
                        implicitHeight: 38
                        paddingHorizontal: 8
                        paddingVertical: 8
                        elevation: 6
                        onClicked: MprisMedia.togglePlay()
                    }
                    LiquidGlassButton {
                        id: mediaNextBtn
                        iconText: "skip_next"
                        iconSize: 15
                        implicitWidth: 32
                        implicitHeight: 32
                        paddingHorizontal: 6
                        paddingVertical: 6
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
                    Layout.minimumHeight: 4
                }

                // Animated Mascot / Companion (Configurable Bongo Cat)
                AnimatedImage {
                    id: mascotImg
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: 76
                    Layout.preferredHeight: 44
                    source: root.mascotSource
                    playing: (typeof MprisMedia !== "undefined") ? MprisMedia.isPlaying : false
                    fillMode: Image.PreserveAspectFit
                }
            }
        }
    }
}
