import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../components"
import "../../services"
import "../../config"

// Downloads manager tab (D1): hero header (aggregate state + add action),
// Material 3 segmented control (active / queued / finished), a designed empty
// state per segment, and a bounded task list with per-row progress and D5
// actions. The add-URL sheet carries the per-add split override (D6/D7).
//
// Liquid glass throughout: Card + LiquidGlassButton + Theme motion tokens.
// No timers: rows bind to DownloadService properties, which update only on
// daemon change events (the tab itself is a pure projection).
//
// Height is content-driven: the empty state is compact, the list clamps at
// `maxListHeight` (4 rows) and scrolls, so the dropdown never grows unbounded.
Item {
    id: root

    implicitWidth: 680
    implicitHeight: contentColumn.implicitHeight + root.padMedium * 2

    property bool testMode: false
    property var testTasks: null

    // Segment filter: "active" | "queued" | "finished" (AriaNg list routes).
    property string segment: "active"
    property bool addDialogOpen: false

    // Connections per file for the next add (1..16, clamped by setSplitValue).
    property int splitValue: 4

    // Keyboard contract: the shell's layer surface runs with
    // WlrKeyboardFocus.None by default (pointer-only drawers). Any surface
    // that captures text raises this so UnifiedShell requests keyboard focus
    // for as long as the sheet is open.
    readonly property bool wantsKeyboard: root.addDialogOpen

    // Clipboard paste: TextEdit.paste() under the hood; testMode can inject
    // text so the append/trim contract is verifiable offscreen.
    property var testClipboardText: null
    property bool inputMenuOpen: false

    // ---- Token resolution ----------------
    // The offscreen QML runner does not register the pragma-Singleton modules
    // (Theme/Colors resolve to empty objects there), so every token used in
    // arithmetic or assignment is resolved once with the production value as
    // the fallback. In the shell these bind to Theme/Colors unchanged.
    readonly property int padSmall: (typeof Theme !== "undefined" && Theme.padSmall !== undefined) ? Theme.padSmall : 8
    readonly property int padMedium: (typeof Theme !== "undefined" && Theme.padMedium !== undefined) ? Theme.padMedium : 12
    readonly property int padLarge: (typeof Theme !== "undefined" && Theme.padLarge !== undefined) ? Theme.padLarge : 16
    readonly property int spaceSmall: (typeof Theme !== "undefined" && Theme.spaceSmall !== undefined) ? Theme.spaceSmall : 8
    readonly property int spaceMedium: (typeof Theme !== "undefined" && Theme.spaceMedium !== undefined) ? Theme.spaceMedium : 12
    readonly property int radiusFull: (typeof Theme !== "undefined" && Theme.radiusFull !== undefined) ? Theme.radiusFull : 9999
    readonly property int radiusCard: (typeof Theme !== "undefined" && Theme.radiusGlassCard !== undefined) ? Theme.radiusGlassCard : 18
    readonly property int radiusItem: (typeof Theme !== "undefined" && Theme.radiusGlassItem !== undefined) ? Theme.radiusGlassItem : 12

    readonly property string fontFamily: (typeof Theme !== "undefined" && Theme.fontFamily !== undefined) ? Theme.fontFamily : "sans-serif"
    readonly property string fontMonospace: (typeof Theme !== "undefined" && Theme.fontMonospace !== undefined) ? Theme.fontMonospace : "monospace"
    readonly property int fontTitleSmall: (typeof Theme !== "undefined" && Theme.fontTitleSmall !== undefined) ? Theme.fontTitleSmall : 16
    readonly property int fontBodyMedium: (typeof Theme !== "undefined" && Theme.fontBodyMedium !== undefined) ? Theme.fontBodyMedium : 15
    readonly property int fontBodySmall: (typeof Theme !== "undefined" && Theme.fontBodySmall !== undefined) ? Theme.fontBodySmall : 13
    readonly property int fontLabelSmall: (typeof Theme !== "undefined" && Theme.fontLabelSmall !== undefined) ? Theme.fontLabelSmall : 12

    readonly property int animSpatial: (typeof Theme !== "undefined" && Theme.animExpressiveDefaultSpatial !== undefined) ? Theme.animExpressiveDefaultSpatial : 500
    readonly property int animEffects: (typeof Theme !== "undefined" && Theme.animExpressiveDefaultEffects !== undefined) ? Theme.animExpressiveDefaultEffects : 200
    readonly property var curveSpatial: (typeof Theme !== "undefined" && Theme.curveExpressiveDefaultSpatial !== undefined) ? Theme.curveExpressiveDefaultSpatial : [0.38, 1.21, 0.22, 1.0, 1.0, 1.0]
    readonly property var curveEffects: (typeof Theme !== "undefined" && Theme.curveExpressiveDefaultEffects !== undefined) ? Theme.curveExpressiveDefaultEffects : [0.34, 0.80, 0.34, 1.0, 1.0, 1.0]

    readonly property color accent: (typeof Colors !== "undefined" && Colors.primary !== undefined) ? Colors.primary : "#9bcbfb"
    readonly property color textMain: (typeof Colors !== "undefined" && Colors.m3onSurface !== undefined) ? Colors.m3onSurface : "#e6e1e6"
    readonly property color textMuted: (typeof Colors !== "undefined" && Colors.m3onSurfaceVariant !== undefined) ? Colors.m3onSurfaceVariant : "#cac4d0"
    readonly property color trackColor: (typeof Colors !== "undefined" && Colors.surfaceContainerHigh !== undefined) ? Colors.surfaceContainerHigh : "#333333"
    readonly property color haloColor: (typeof Colors !== "undefined" && Colors.glassTextHalo !== undefined) ? Colors.glassTextHalo : Qt.rgba(0, 0, 0, 0.62)
    readonly property color specularColor: (typeof Colors !== "undefined" && Colors.glassBorderSpecular !== undefined) ? Colors.glassBorderSpecular : Qt.rgba(1, 1, 1, 0.20)
    readonly property color borderSubtle: (typeof Theme !== "undefined" && Theme.borderSubtle !== undefined) ? Theme.borderSubtle : Qt.rgba(1, 1, 1, 0.12)
    readonly property bool darkMode: (typeof Colors !== "undefined" && Colors.isDarkMode !== undefined) ? Boolean(Colors.isDarkMode) : true

    // ---- Test hooks / structural aliases ----
    readonly property alias headerItem: headerRow
    readonly property alias addButtonItem: addButton
    readonly property alias aggregateProgressItem: aggregateProgress
    readonly property alias segmentBarItem: segmentBar
    readonly property alias segmentIndicatorItem: segmentIndicator
    readonly property alias segmentRepeaterItem: segmentRepeater
    readonly property alias segmentRowItem: segmentRow
    readonly property alias emptyStateItem: emptyState
    readonly property alias emptyStateTitleItem: emptyTitle
    readonly property alias emptyStateHintItem: emptyHint
    readonly property alias taskListFlickableItem: taskList
    readonly property alias taskListColumnItem: listColumn
    readonly property alias taskRowRepeaterItem: taskRowRepeater
    readonly property alias addDialogItem: addDialog
    readonly property alias urlInputItem: urlInput
    readonly property alias splitValueTextItem: splitValueText
    readonly property alias splitMinusButtonItem: minusMouse
    readonly property alias splitPlusButtonItem: plusMouse
    readonly property alias pasteButtonItem: pasteButton
    readonly property alias pasteButtonMouseItem: pasteMouse
    readonly property alias inputRightClickItem: inputRightClick
    readonly property alias inputMenuCardItem: inputMenu
    readonly property alias submitButtonItem: submitButton
    readonly property alias cancelButtonItem: cancelButton
    readonly property alias closeDialogButtonItem: closeDialogButton

    // Bounded list: 4 rows visible, the rest scrolls (AGENTS.md §7.2).
    readonly property int rowHeight: 58
    readonly property int maxListHeight: 4 * rowHeight + 3 * root.spaceSmall
    readonly property int emptyStateHeight: 150

    readonly property bool isTargetVisible: testMode || (
        visible && ((typeof Config !== "undefined" && Config)
            ? (Boolean(Config.dashboardVisible) && Config.activeDashboardTab === "downloads")
            : true)
    )

    // =====================================================================
    // Helpers (pure; unit-tested in tst_downloads_tab.qml)
    // =====================================================================
    function formatBytes(bytes) {
        if (typeof DownloadService !== "undefined" && DownloadService
                && typeof DownloadService.formatBytes === "function") {
            return DownloadService.formatBytes(bytes);
        }
        if (!bytes || bytes <= 0) return "0 B";
        const units = ["B", "KiB", "MiB", "GiB", "TiB"];
        const i = Math.floor(Math.log(bytes) / Math.log(1024));
        const p = Math.min(Math.max(0, i), units.length - 1);
        return (bytes / Math.pow(1024, p)).toFixed(1) + " " + units[p];
    }

    function formatSpeed(bytesPerSec) {
        if (typeof DownloadService !== "undefined" && DownloadService
                && typeof DownloadService.formatSpeed === "function") {
            return DownloadService.formatSpeed(bytesPerSec);
        }
        return root.formatBytes(bytesPerSec) + "/s";
    }

    function taskProgress(t) {
        if (!t || !t.total_length || t.total_length <= 0) return 0.0;
        return Math.min(1.0, Math.max(0.0, (t.completed_length || 0) / t.total_length));
    }

    function taskEta(t) {
        if (!t || !t.download_speed || t.download_speed <= 0) return "--";
        const remain = Math.max(0, (t.total_length || 0) - (t.completed_length || 0));
        if (remain <= 0) return "done";
        const s = Math.floor(remain / t.download_speed);
        if (s < 60) return s + "s";
        if (s < 3600) return Math.floor(s / 60) + "m";
        return Math.floor(s / 3600) + "h";
    }

    // Verbs per status (D5). Pure function: unit-tested in tst_downloads_tab.
    function actionsFor(status) {
        const st = (status || "").toLowerCase();
        if (st === "active") return ["pause", "cancel"];
        if (st === "waiting" || st === "paused") return ["resume", "cancel"];
        if (st === "error") return ["retry", "remove"];
        return ["remove"];
    }

    function actionIcon(verb) {
        if (verb === "pause") return "pause";
        if (verb === "resume") return "play_arrow";
        if (verb === "cancel") return "close";
        if (verb === "retry") return "refresh";
        return "delete";
    }

    function statusIcon(status) {
        const st = (status || "").toLowerCase();
        if (st === "complete") return "check_circle";
        if (st === "error") return "error";
        if (st === "paused") return "pause";
        return "download";
    }

    function taskStatus(t) {
        return (((t && (t.status || t.state)) || "") + "").toLowerCase();
    }

    // Status tint: one place, no per-row hardcoding.
    function statusColor(status) {
        const st = (status || "").toLowerCase();
        if (st === "complete") return "#34d399";
        if (st === "error") return "#f87171";
        if (st === "paused") return root.textMuted;
        return root.accent;
    }

    function setSplitValue(v) {
        // 0 is a valid step value (1 − 1), so `|| 4` would wrongly reset it.
        const n = Number(v);
        const safe = isNaN(n) ? root.splitValue : n;
        root.splitValue = Math.max(1, Math.min(16, Math.round(safe)));
    }

    function pasteFromClipboard() {
        if (root.testMode && root.testClipboardText !== null) {
            root.appendPastedText(root.testClipboardText);
            return;
        }
        // TextEdit.paste() reads the system clipboard at the cursor. No
        // subprocess or Quickshell clipboard binding is needed.
        urlInput.paste();
    }

    function appendPastedText(txt) {
        const clean = (txt || "").replace(/\s+$/, "");
        if (clean.length === 0) return;
        const current = (urlInput.text || "").replace(/\s+$/, "");
        urlInput.text = current.length > 0 ? (current + "\n" + clean) : clean;
        urlInput.cursorPosition = urlInput.text.length;
    }

    function handleMenuAction(actionId) {
        root.inputMenuOpen = false;
        if (actionId === "paste") root.pasteFromClipboard();
        else if (actionId === "select_all") urlInput.selectAll();
        else if (actionId === "clear") urlInput.text = "";
    }

    function submitDownload() {
        const urls = (urlInput.text || "").trim();
        if (urls.length > 0 && typeof DownloadService !== "undefined" && DownloadService
                && typeof DownloadService.addUrls === "function") {
            DownloadService.addUrls(urls, { split: root.splitValue });
        }
        urlInput.text = "";
        root.addDialogOpen = false;
    }

    // ---- Task data: daemon stream (or injected tasks under testMode) ----
    function isFinishedStatus(task) {
        const st = root.taskStatus(task);
        return st !== "active" && st !== "waiting" && st !== "paused";
    }

    function matchesSegment(task) {
        const st = root.taskStatus(task);
        if (root.segment === "active") return st === "active";
        if (root.segment === "queued") return st === "waiting" || st === "paused";
        return root.isFinishedStatus(task);
    }

    readonly property var segmentTasks: {
        if (root.testMode && root.testTasks !== null) {
            return (root.testTasks || []).filter(function(t) { return root.matchesSegment(t); });
        }
        if (typeof DownloadService === "undefined" || !DownloadService) return [];
        if (root.segment === "active") return DownloadService.activeTasks || [];
        if (root.segment === "queued") return DownloadService.waitingTasks || [];
        return DownloadService.stoppedTasks || [];
    }

    function countWhere(pred) {
        if (root.testMode && root.testTasks !== null) {
            return (root.testTasks || []).filter(pred).length;
        }
        return -1;
    }

    readonly property int activeCount: {
        const injected = root.countWhere(function(t) { return root.taskStatus(t) === "active"; });
        if (injected >= 0) return injected;
        return (typeof DownloadService !== "undefined" && DownloadService && DownloadService.activeCount) || 0;
    }
    readonly property int queuedCount: {
        const injected = root.countWhere(function(t) {
            const st = root.taskStatus(t);
            return st === "waiting" || st === "paused";
        });
        if (injected >= 0) return injected;
        return (typeof DownloadService !== "undefined" && DownloadService && (DownloadService.waitingTasks || []).length) || 0;
    }
    readonly property int finishedCount: {
        const injected = root.countWhere(function(t) { return root.isFinishedStatus(t); });
        if (injected >= 0) return injected;
        return (typeof DownloadService !== "undefined" && DownloadService && (DownloadService.stoppedTasks || []).length) || 0;
    }

    readonly property real aggregateProgress: (typeof DownloadService !== "undefined" && DownloadService && DownloadService.totalProgress) || 0
    readonly property real aggregateSpeed: (typeof DownloadService !== "undefined" && DownloadService && DownloadService.totalSpeed) || 0

    // Explicit composition state: what the tab is showing, independent of the
    // parent's effective visibility (Qt forces child `visible` off under an
    // invisible parent, so tests and logic read these, not `.visible`).
    readonly property bool showEmptyState: root.segmentTasks.length === 0 && !root.addDialogOpen
    readonly property bool showTaskList: root.segmentTasks.length > 0 && !root.addDialogOpen
    readonly property bool showSegments: !root.addDialogOpen
    readonly property bool showAggregateProgress: root.activeCount > 0 && !root.addDialogOpen

    readonly property string destinationLabel: {
        if (typeof Config !== "undefined" && Config && Config.downloadsDir && Config.downloadsDir.length > 0)
            return Config.downloadsDir;
        return "~/Downloads";
    }

    Component.onCompleted: {
        if (typeof Config !== "undefined" && Config && Config.downloadsSplit)
            root.setSplitValue(Config.downloadsSplit);
    }

    onAddDialogOpenChanged: {
        root.inputMenuOpen = false;
        if (root.addDialogOpen) {
            urlInput.forceActiveFocus();
            if (urlInput.text.length > 0) urlInput.selectAll();
        }
    }

    // Closing the dashboard must release the keyboard capture even when the
    // sheet was never explicitly dismissed.
    Connections {
        target: (typeof Config !== "undefined" && Config && Config.dashboardVisible !== undefined) ? Config : null
        function onDashboardVisibleChanged() {
            if (typeof Config !== "undefined" && Config && Config.dashboardVisible === false) {
                root.addDialogOpen = false;
                root.inputMenuOpen = false;
            }
        }
    }

    // =====================================================================
    // Layout
    // =====================================================================
    ColumnLayout {
        id: contentColumn
        anchors.fill: parent
        anchors.leftMargin: root.padLarge
        anchors.rightMargin: root.padLarge
        anchors.topMargin: root.padMedium
        anchors.bottomMargin: root.padMedium
        spacing: root.spaceMedium

        // ---- Header: state at a glance + the primary add action ----
        RowLayout {
            id: headerRow
            Layout.fillWidth: true
            spacing: root.spaceMedium

            Rectangle {
                implicitWidth: 38
                implicitHeight: 38
                radius: root.radiusItem
                color: Qt.alpha(root.accent, 0.14)
                border.width: 1
                border.color: Qt.alpha(root.accent, 0.25)

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "download"
                    size: 20
                    color: root.accent
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Text {
                    Layout.fillWidth: true
                    text: root.activeCount > 0
                        ? "Downloading " + root.activeCount + (root.activeCount > 1 ? " files" : " file")
                        : "Downloads"
                    font.family: root.fontFamily
                    font.pixelSize: root.fontTitleSmall
                    font.weight: Font.DemiBold
                    color: root.textMain
                    style: Text.Outline
                    styleColor: root.haloColor
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    text: {
                        if (root.activeCount > 0) {
                            const pct = Math.round(root.aggregateProgress * 100);
                            return pct + "% · " + root.formatSpeed(root.aggregateSpeed)
                                + " · ETA " + root.taskEta({
                                    total_length: (typeof DownloadService !== "undefined" && DownloadService ? DownloadService.totalBytes : 0) || 0,
                                    completed_length: (typeof DownloadService !== "undefined" && DownloadService ? DownloadService.totalCompletedBytes : 0) || 0,
                                    download_speed: root.aggregateSpeed
                                });
                        }
                        if (root.finishedCount > 0) return root.finishedCount + " finished";
                        return "No downloads yet";
                    }
                    font.family: root.fontFamily
                    font.pixelSize: root.fontLabelSmall
                    color: root.textMuted
                    style: Text.Outline
                    styleColor: root.haloColor
                    elide: Text.ElideRight
                }
            }

            // Segments share the header line: title | Active/Queued/Finished | Add.
            Rectangle {
                id: segmentBar
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: segmentRow.implicitWidth + 8
                implicitHeight: 34
                radius: root.radiusFull
                visible: root.showSegments
                color: root.darkMode ? Qt.rgba(0, 0, 0, 0.45) : Qt.rgba(255, 255, 255, 0.65)
                border.width: 1
                border.color: root.specularColor ? Qt.alpha(root.specularColor, 0.35) : Qt.rgba(1, 1, 1, 0.20)

                readonly property int activeIdx: root.segment === "active" ? 0 : (root.segment === "queued" ? 1 : 2)

                Rectangle {
                    id: segmentIndicator
                    readonly property Item activeChip: (segmentRepeater.count > segmentBar.activeIdx)
                        ? segmentRepeater.itemAt(segmentBar.activeIdx)
                        : null
                    y: 4
                    x: activeChip ? (segmentRow.x + activeChip.x) : 4
                    width: activeChip ? activeChip.width : 0
                    height: 26
                    radius: root.radiusFull
                    color: Qt.alpha(root.accent, 0.28)
                    border.width: 1
                    border.color: root.accent

                    Behavior on x {
                        NumberAnimation {
                            duration: root.animSpatial
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: root.curveSpatial
                        }
                    }
                    Behavior on width {
                        NumberAnimation {
                            duration: root.animSpatial
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: root.curveSpatial
                        }
                    }
                }

                Row {
                    id: segmentRow
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 4
                    spacing: 4

                    Repeater {
                        id: segmentRepeater
                        model: [
                            { id: "active", label: "Active", count: root.activeCount },
                            { id: "queued", label: "Queued", count: root.queuedCount },
                            { id: "finished", label: "Finished", count: root.finishedCount }
                        ]

                        delegate: Item {
                            id: segmentChip
                            required property var modelData
                            required property int index
                            readonly property bool isSelected: root.segment === modelData.id
                            width: chipContent.implicitWidth + 24
                            height: 26

                            Row {
                                id: chipContent
                                anchors.centerIn: parent
                                spacing: 6

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: segmentChip.modelData.label
                                    font.family: root.fontFamily
                                    font.pixelSize: root.fontLabelSmall
                                    font.weight: segmentChip.isSelected ? Font.Bold : Font.DemiBold
                                    color: segmentChip.isSelected ? root.accent : root.textMain
                                    style: Text.Outline
                                    styleColor: root.haloColor
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: String(segmentChip.modelData.count)
                                    font.family: root.fontMonospace
                                    font.pixelSize: 11
                                    color: segmentChip.isSelected ? root.accent : root.textMuted
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.segment = segmentChip.modelData.id
                            }
                        }
                    }
                }
            }

            LiquidGlassButton {
                id: addButton
                implicitWidth: 92
                implicitHeight: 34
                paddingHorizontal: 14
                paddingVertical: 6
                text: "Add"
                iconText: root.addDialogOpen ? "close" : "add"
                iconSize: 16
                isPrimary: !root.addDialogOpen
                elevation: 4
                onClicked: root.addDialogOpen = !root.addDialogOpen
            }
        }

        // ---- Aggregate progress (Σ done / Σ total), only while downloading ----
        Rectangle {
            id: aggregateProgress
            Layout.fillWidth: true
            Layout.preferredHeight: 5
            radius: root.radiusFull
            visible: root.showAggregateProgress
            color: root.trackColor ? root.trackColor : "#333333"

            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: parent.width * Math.min(1.0, Math.max(0.0, root.aggregateProgress))
                radius: root.radiusFull
                color: root.accent

                Behavior on width {
                    NumberAnimation {
                        duration: root.animEffects
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: root.curveEffects
                    }
                }
            }
        }

        // ---- Add sheet: focused composition, replaces the list while open ----
        Card {
            id: addDialog
            Layout.fillWidth: true
            visible: root.addDialogOpen
            radius: root.radiusCard
            implicitHeight: dialogColumn.implicitHeight + root.padMedium * 2

            ColumnLayout {
                id: dialogColumn
                anchors.fill: parent
                anchors.margins: root.padMedium
                spacing: root.spaceSmall

                RowLayout {
                    Layout.fillWidth: true
                    spacing: root.spaceSmall

                    MaterialIcon {
                        text: "link"
                        size: 18
                        color: root.accent
                    }

                    Text {
                        Layout.fillWidth: true
                        text: "New download"
                        font.family: root.fontFamily
                        font.pixelSize: root.fontBodySmall
                        font.weight: Font.DemiBold
                        color: root.textMain
                    }

                    LiquidGlassButton {
                        id: closeDialogButton
                        implicitWidth: 28
                        implicitHeight: 28
                        paddingHorizontal: 6
                        paddingVertical: 6
                        iconText: "close"
                        iconSize: 15
                        elevation: 3
                        onClicked: root.addDialogOpen = false
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 64
                    radius: root.radiusItem
                    color: root.darkMode ? Qt.rgba(0, 0, 0, 0.35) : Qt.rgba(255, 255, 255, 0.55)
                    border.width: 1
                    border.color: root.borderSubtle
                    clip: true

                    TextEdit {
                        id: urlInput
                        anchors.fill: parent
                        anchors.margins: 8
                        anchors.rightMargin: 44
                        wrapMode: TextEdit.WrapAnywhere
                        font.family: root.fontFamily
                        font.pixelSize: root.fontBodySmall
                        color: root.textMain
                        selectByMouse: true
                        focus: root.addDialogOpen

                        Keys.onEscapePressed: (event) => {
                            if (root.inputMenuOpen) {
                                root.inputMenuOpen = false;
                            } else if (root.addDialogOpen) {
                                root.addDialogOpen = false;
                            }
                            event.accepted = true;
                        }
                    }

                    Text {
                        anchors.fill: parent
                        anchors.margins: 8
                        anchors.rightMargin: 44
                        text: "https://… (one URL per line)"
                        font.family: root.fontFamily
                        font.pixelSize: root.fontBodySmall
                        color: root.textMuted
                        opacity: 0.6
                        visible: urlInput.text.length === 0
                    }

                    // Right-click opens the paste menu. Left/middle clicks are
                    // not accepted, so editing and selection still reach the
                    // TextEdit underneath.
                    MouseArea {
                        id: inputRightClick
                        anchors.fill: parent
                        acceptedButtons: Qt.RightButton
                        onClicked: root.inputMenuOpen = !root.inputMenuOpen
                    }

                    Rectangle {
                        id: pasteButton
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        width: 30
                        height: 30
                        radius: root.radiusFull
                        color: pasteMouse.containsMouse ? Qt.alpha(root.accent, 0.20) : "transparent"

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: "content_paste"
                            size: 16
                            color: pasteMouse.containsMouse ? root.accent : root.textMuted
                        }

                        MouseArea {
                            id: pasteMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.pasteFromClipboard()
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: root.spaceSmall

                    Text {
                        text: "Connections"
                        font.family: root.fontFamily
                        font.pixelSize: root.fontLabelSmall
                        color: root.textMuted
                    }

                    // Stepper: minus / value / plus (clamped 1..16).
                    Rectangle {
                        implicitWidth: 92
                        implicitHeight: 28
                        radius: root.radiusFull
                        color: root.darkMode ? Qt.rgba(0, 0, 0, 0.35) : Qt.rgba(255, 255, 255, 0.55)
                        border.width: 1
                        border.color: root.borderSubtle

                        Row {
                            anchors.centerIn: parent
                            spacing: 2

                            Rectangle {
                                id: splitMinus
                                width: 26
                                height: 26
                                radius: root.radiusFull
                                color: minusMouse.containsMouse ? Qt.alpha(root.accent, 0.18) : "transparent"

                                MaterialIcon {
                                    anchors.centerIn: parent
                                    text: "remove"
                                    size: 14
                                    color: root.textMain
                                }

                                MouseArea {
                                    id: minusMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.setSplitValue(root.splitValue - 1)
                                }
                            }

                            Text {
                                id: splitValueText
                                width: 28
                                horizontalAlignment: Text.AlignHCenter
                                anchors.verticalCenter: parent.verticalCenter
                                text: String(root.splitValue)
                                font.family: root.fontMonospace
                                font.pixelSize: root.fontBodySmall
                                color: root.textMain
                            }

                            Rectangle {
                                id: splitPlus
                                width: 26
                                height: 26
                                radius: root.radiusFull
                                color: plusMouse.containsMouse ? Qt.alpha(root.accent, 0.18) : "transparent"

                                MaterialIcon {
                                    anchors.centerIn: parent
                                    text: "add"
                                    size: 14
                                    color: root.textMain
                                }

                                MouseArea {
                                    id: plusMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.setSplitValue(root.splitValue + 1)
                                }
                            }
                        }
                    }

                    Text {
                        text: "parts per file"
                        font.family: root.fontFamily
                        font.pixelSize: root.fontLabelSmall
                        color: root.textMuted
                        opacity: 0.7
                    }

                    Item { Layout.fillWidth: true }

                    MaterialIcon {
                        text: "folder"
                        size: 14
                        color: root.textMuted
                    }

                    Text {
                        Layout.maximumWidth: 260
                        text: root.destinationLabel
                        font.family: root.fontMonospace
                        font.pixelSize: 11
                        color: root.textMuted
                        elide: Text.ElideMiddle
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: root.spaceSmall

                    Item { Layout.fillWidth: true }

                    LiquidGlassButton {
                        id: cancelButton
                        implicitWidth: 86
                        implicitHeight: 32
                        paddingHorizontal: 14
                        paddingVertical: 6
                        text: "Cancel"
                        elevation: 3
                        onClicked: root.addDialogOpen = false
                    }

                    LiquidGlassButton {
                        id: submitButton
                        implicitWidth: 116
                        implicitHeight: 32
                        paddingHorizontal: 14
                        paddingVertical: 6
                        text: "Download"
                        iconText: "download"
                        iconSize: 15
                        isPrimary: true
                        elevation: 4
                        onClicked: root.submitDownload()
                    }
                }
            }
        }

        // ---- Empty state: a composed moment, not a void ----
        Item {
            id: emptyState
            Layout.fillWidth: true
            Layout.preferredHeight: root.emptyStateHeight
            visible: root.showEmptyState

            Column {
                anchors.centerIn: parent
                width: Math.min(parent.width, 420)
                spacing: root.spaceSmall

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 64
                    height: 64
                    radius: root.radiusFull
                    color: Qt.alpha(root.accent, 0.12)
                    border.width: 1
                    border.color: Qt.alpha(root.accent, 0.22)

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: root.segment === "finished" ? "task_alt" : "cloud_download"
                        size: 30
                        color: root.accent
                    }
                }

                Text {
                    id: emptyTitle
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.segment === "active"
                        ? "No active downloads"
                        : (root.segment === "queued" ? "Queue is empty" : "Nothing finished yet")
                    font.family: root.fontFamily
                    font.pixelSize: root.fontBodyMedium
                    font.weight: Font.DemiBold
                    color: root.textMain
                    style: Text.Outline
                    styleColor: root.haloColor
                }

                Text {
                    id: emptyHint
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: root.segment === "active"
                        ? "Paste a link with Add — it starts downloading right away."
                        : (root.segment === "queued"
                            ? "Paused and waiting downloads wait here until a slot frees up."
                            : "Completed and failed downloads land here with their actions.")
                    font.family: root.fontFamily
                    font.pixelSize: root.fontLabelSmall
                    color: root.textMuted
                    style: Text.Outline
                    styleColor: root.haloColor
                }
            }
        }

        // ---- Task list: bounded, glass rows, per-row progress + D5 actions ----
        Flickable {
            id: taskList
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(contentHeight, root.maxListHeight)
            visible: root.showTaskList
            clip: true
            contentHeight: listColumn.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: listColumn
                width: parent.width
                spacing: root.spaceSmall

                Repeater {
                    id: taskRowRepeater
                    model: root.segmentTasks

                    delegate: Card {
                        id: taskCard
                        required property var modelData

                        // Capture the task: nested repeaters shadow modelData.
                        readonly property var task: modelData
                        readonly property string status: root.taskStatus(task)

                        width: listColumn.width
                        implicitHeight: rowColumn.implicitHeight + root.padSmall * 2
                        radius: root.radiusCard

                        ColumnLayout {
                            id: rowColumn
                            anchors.fill: parent
                            anchors.margins: root.padSmall
                            spacing: 6

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: root.spaceSmall

                                Rectangle {
                                    implicitWidth: 32
                                    implicitHeight: 32
                                    radius: root.radiusFull
                                    color: Qt.alpha(root.statusColor(taskCard.status), 0.16)
                                    border.width: 1
                                    border.color: Qt.alpha(root.statusColor(taskCard.status), 0.30)

                                    MaterialIcon {
                                        anchors.centerIn: parent
                                        text: root.statusIcon(taskCard.status)
                                        size: 17
                                        color: root.statusColor(taskCard.status)
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0

                                    Text {
                                        Layout.fillWidth: true
                                        text: (taskCard.task && (taskCard.task.name || taskCard.task.gid)) || "Unknown"
                                        font.family: root.fontFamily
                                        font.pixelSize: root.fontBodySmall
                                        font.weight: Font.DemiBold
                                        color: root.textMain
                                        style: Text.Outline
                                        styleColor: root.haloColor
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: {
                                            const t = taskCard.task;
                                            if (!t) return "";
                                            const done = root.formatBytes(t.completed_length || 0);
                                            const total = root.formatBytes(t.total_length || 0);
                                            if (taskCard.status === "active")
                                                return done + " / " + total + " · " + root.formatSpeed(t.download_speed || 0) + " · ETA " + root.taskEta(t);
                                            if (taskCard.status === "complete")
                                                return done + " · completed";
                                            if (taskCard.status === "error")
                                                return done + " / " + total + " · failed" + ((t.error_code) ? " (" + t.error_code + ")" : "");
                                            if (taskCard.status === "paused")
                                                return done + " / " + total + " · paused";
                                            return done + " / " + total;
                                        }
                                        font.family: root.fontMonospace
                                        font.pixelSize: 11
                                        color: root.textMuted
                                        elide: Text.ElideRight
                                    }
                                }

                                Text {
                                    text: Math.round(root.taskProgress(taskCard.task) * 100) + "%"
                                    font.family: root.fontMonospace
                                    font.pixelSize: root.fontLabelSmall
                                    color: root.textMain
                                }

                                Row {
                                    spacing: 2

                                    Repeater {
                                        model: root.actionsFor(taskCard.status)

                                        delegate: Rectangle {
                                            id: actionButton
                                            required property var modelData
                                            width: 28
                                            height: 28
                                            radius: root.radiusFull
                                            color: actMouse.containsMouse ? Qt.alpha(root.accent, 0.22) : "transparent"

                                            MaterialIcon {
                                                anchors.centerIn: parent
                                                text: root.actionIcon(actionButton.modelData)
                                                size: 16
                                                color: root.textMain
                                            }

                                            MouseArea {
                                                id: actMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    if (typeof DownloadService === "undefined" || !DownloadService) return;
                                                    const gid = (taskCard.task && taskCard.task.gid) || "";
                                                    if (!gid) return;
                                                    if (actionButton.modelData === "pause") DownloadService.pause(gid);
                                                    else if (actionButton.modelData === "resume") DownloadService.resume(gid);
                                                    else if (actionButton.modelData === "cancel") DownloadService.cancel(gid, false);
                                                    else if (actionButton.modelData === "retry") DownloadService.retry(gid);
                                                    else DownloadService.removeResult(gid);
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // Per-row progress track.
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 4
                                radius: root.radiusFull
                                color: root.trackColor ? root.trackColor : "#333333"

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    width: parent.width * root.taskProgress(taskCard.task)
                                    radius: root.radiusFull
                                    color: root.statusColor(taskCard.status)

                                    Behavior on width {
                                        NumberAnimation {
                                            duration: root.animEffects
                                            easing.type: Easing.BezierSpline
                                            easing.bezierCurve: root.curveEffects
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ---- URL field context menu (glass, dismissed by outside click) ----
    MouseArea {
        anchors.fill: parent
        visible: root.inputMenuOpen
        z: 80
        onClicked: root.inputMenuOpen = false
    }

    Rectangle {
        id: inputMenu
        z: 81
        visible: root.inputMenuOpen
        width: 176
        implicitHeight: menuColumn.implicitHeight + 8
        radius: root.radiusItem
        color: root.darkMode ? Qt.rgba(0.05, 0.06, 0.09, 0.92) : Qt.rgba(0.97, 0.97, 1.0, 0.94)
        border.width: 1
        border.color: root.specularColor ? Qt.alpha(root.specularColor, 0.35) : Qt.rgba(1, 1, 1, 0.2)

        x: Math.max(4, Math.min(root.width - width - 4, urlInput.mapToItem(root, 0, 0).x))
        y: urlInput.mapToItem(root, 0, urlInput.height).y + 4

        Column {
            id: menuColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: 4
            spacing: 2

            Repeater {
                model: [
                    { id: "paste", label: "Paste", icon: "content_paste" },
                    { id: "select_all", label: "Select all", icon: "select_all" },
                    { id: "clear", label: "Clear", icon: "delete_sweep" }
                ]

                delegate: Rectangle {
                    id: menuRow
                    required property var modelData
                    width: parent.width
                    height: 30
                    radius: 8
                    color: rowMouse.containsMouse ? Qt.alpha(root.accent, 0.18) : "transparent"

                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8

                        MaterialIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            text: menuRow.modelData.icon
                            size: 15
                            color: root.textMuted
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: menuRow.modelData.label
                            font.family: root.fontFamily
                            font.pixelSize: root.fontLabelSmall
                            color: root.textMain
                        }
                    }

                    MouseArea {
                        id: rowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.handleMenuAction(menuRow.modelData.id)
                    }
                }
            }
        }
    }
}
