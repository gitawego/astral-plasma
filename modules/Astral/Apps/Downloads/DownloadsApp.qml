import QtQuick
import QtQuick.Layouts
import "../../Kernel/theme"
import "../../Kernel/components"

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
// Downloads app (`manifest.entry.dashboardTab` = "downloads").
//
// Declared as a Component in `shell.qml` (one kernel registration, spec C.18). `downloads` is
// the shell's live download service; settings and navigation go through shellState/intents.
Item {
    id: root

    property var downloads: null
    property var shellState: null
    property var intents: null

    implicitWidth: 680
    implicitHeight: contentColumn.implicitHeight + root.padMedium * 2

    property bool testMode: false
    property var testTasks: null

    // Segment filter: "active" | "queued" | "finished" (AriaNg list routes).
    property string segment: (root.shellState !== null && Config && (root.shellState ? root.shellState.downloadsSegment : "active"))
        ? (root.shellState ? root.shellState.downloadsSegment : "active") : "active"
    onSegmentChanged: {
        if (root.shellState !== null && Config && (root.shellState ? root.shellState.downloadsSegment : "active") !== root.segment) {
            if (root.intents) root.intents.request("downloads.segment", { segment: root.segment });
        }
    }
    property bool addDialogOpen: false

    /// Hosted in the dedicated window (shell/DownloadsWindow.qml) instead of the
    /// dropdown drawer. The header then shows a close control and starts a
    /// compositor-native move; the task list fills the taller surface.
    property bool windowMode: false
    property var windowHandle: null
    signal closeRequested()

    /// Engine-wide settings panel, hosted in the dedicated window only. The
    /// drawer stays a quick view; the window is where the manager lives.
    property bool settingsOpen: false

    // Connections per file for the next add (1..16, clamped by setSplitValue).
    property int splitValue: 4
    // Global default, used only when the engine did not report a task's split.
    readonly property int defaultSplit: (root.shellState !== null && Config && (root.shellState ? root.shellState.downloadsSplit : false))
        ? (root.shellState ? root.shellState.downloadsSplit : false) : 4

    // Keyboard contract: the shell's layer surface runs with
    // WlrKeyboardFocus.None by default (pointer-only drawers). Any surface
    // that captures text raises this so UnifiedShell requests keyboard focus
    // for as long as the sheet is open.
    readonly property bool wantsKeyboard: root.addDialogOpen

    // Aria2 availability: live from DownloadService, or test injection
    property var testAriaAvailable: null
    readonly property bool isAriaAvailable: root.testAriaAvailable !== null
        ? Boolean(root.testAriaAvailable)
        : ((root.downloads !== null && root.downloads && root.downloads.ariaAvailable !== undefined)
            ? Boolean(root.downloads.ariaAvailable)
            : true)

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
    readonly property int spaceLarge: (typeof Theme !== "undefined" && Theme.spaceLarge !== undefined) ? Theme.spaceLarge : 16
    readonly property int spaceExtraLarge: (typeof Theme !== "undefined" && Theme.spaceExtraLarge !== undefined) ? Theme.spaceExtraLarge : 24
    readonly property int spaceExtraSmall: (typeof Theme !== "undefined" && Theme.spaceExtraSmall !== undefined) ? Theme.spaceExtraSmall : 4
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
    readonly property alias clearButtonItem: clearButton
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
    readonly property alias ledgerItem: ledger
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
    readonly property alias ariaInstallBannerItem: ariaInstallBanner

    // Bounded list: 4 rows visible, the rest scrolls (AGENTS.md §7.2).
    readonly property int rowHeight: 66
    readonly property int maxListHeight: 4 * rowHeight + 3 * root.spaceMedium
    readonly property int emptyStateHeight: 150

    readonly property bool isTargetVisible: testMode || (
        visible && ((root.shellState !== null && Config)
            ? (Boolean((root.shellState ? root.shellState.dashboardVisible : false)) && (root.shellState && root.shellState.activeDashboardTab === "downloads"))
            : true)
    )

    // =====================================================================
    // Helpers (pure; unit-tested in tst_downloads_tab.qml)
    // =====================================================================
    function formatBytes(bytes) {
        if (root.downloads !== null && root.downloads
                && typeof root.downloads.formatBytes === "function") {
            return root.downloads.formatBytes(bytes);
        }
        if (!bytes || bytes <= 0) return "0 B";
        const units = ["B", "KiB", "MiB", "GiB", "TiB"];
        const i = Math.floor(Math.log(bytes) / Math.log(1024));
        const p = Math.min(Math.max(0, i), units.length - 1);
        return (bytes / Math.pow(1024, p)).toFixed(1) + " " + units[p];
    }

    function formatSpeed(bytesPerSec) {
        if (root.downloads !== null && root.downloads
                && typeof root.downloads.formatSpeed === "function") {
            return root.downloads.formatSpeed(bytesPerSec);
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
        return ["open", "folder", "remove"];
    }

    function actionIcon(verb) {
        if (verb === "pause") return "pause";
        if (verb === "resume") return "play_arrow";
        if (verb === "cancel") return "close";
        if (verb === "retry") return "refresh";
        if (verb === "open") return "open_in_new";
        if (verb === "folder") return "folder";
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
        if (st === "complete") {
            return (typeof Colors !== "undefined" && Colors.success) ? Colors.success : "#34d399";
        }
        if (st === "error") {
            return (typeof Colors !== "undefined" && Colors.error) ? Colors.error : "#f87171";
        }
        if (st === "paused") return root.textMuted;
        return root.accent;
    }

    function setSplitValue(v) {
        // 0 is a valid step value (1 − 1), so `|| 4` would wrongly reset it.
        const n = Number(v);
        const safe = isNaN(n) ? root.splitValue : n;
        root.splitValue = Math.max(1, Math.min(16, Math.round(safe)));
    }

    /// The connection count a row should show: the engine's own `split` when it
    /// answered, otherwise the configured default - never a fabricated number.
    function taskParts(t) {
        const n = Number(t && t.split);
        if (isFinite(n) && n > 0) return Math.max(1, Math.min(16, Math.round(n)));
        return Math.max(1, Math.min(16, Math.round(Number(root.defaultSplit) || 4)));
    }

    function nextParts(t, delta) {
        return Math.max(1, Math.min(16, root.taskParts(t) + (Number(delta) || 0)));
    }

    /// One click on a row's parts stepper. aria2 restarts the active task and
    /// resumes from the control file, so this is safe while downloading.
    function stepParts(t, delta) {
        if (!t || !t.gid) return;
        const next = root.nextParts(t, delta);
        if (next === root.taskParts(t)) return;
        if (root.downloads !== null && root.downloads
                && typeof root.downloads.setParts === "function") {
            root.downloads.setParts(t.gid, next);
        }
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
        if (urls.length > 0 && root.downloads !== null && root.downloads
                && typeof root.downloads.addUrls === "function") {
            root.downloads.addUrls(urls, { split: root.splitValue });
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
        if (root.downloads === null) return [];
        if (root.segment === "active") return root.downloads.activeTasks || [];
        if (root.segment === "queued") return root.downloads.waitingTasks || [];
        return root.downloads.stoppedTasks || [];
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
        return (root.downloads !== null && root.downloads && root.downloads.activeCount) || 0;
    }
    readonly property int queuedCount: {
        const injected = root.countWhere(function(t) {
            const st = root.taskStatus(t);
            return st === "waiting" || st === "paused";
        });
        if (injected >= 0) return injected;
        return (root.downloads !== null && root.downloads && (root.downloads.waitingTasks || []).length) || 0;
    }
    readonly property int finishedCount: {
        const injected = root.countWhere(function(t) { return root.isFinishedStatus(t); });
        if (injected >= 0) return injected;
        return (root.downloads !== null && root.downloads && (root.downloads.stoppedTasks || []).length) || 0;
    }

    readonly property real aggregateProgress: (root.downloads !== null && root.downloads && root.downloads.totalProgress) || 0
    readonly property real aggregateSpeed: (root.downloads !== null && root.downloads && root.downloads.totalSpeed) || 0

    // Explicit composition state: what the tab is showing, independent of the
    // parent's effective visibility (Qt forces child `visible` off under an
    // invisible parent, so tests and logic read these, not `.visible`).
    readonly property bool showEmptyState: root.segmentTasks.length === 0 && !root.addDialogOpen && !root.settingsOpen
    readonly property bool showTaskList: root.segmentTasks.length > 0 && !root.addDialogOpen && !root.settingsOpen
    readonly property bool showSegments: !root.addDialogOpen && !root.settingsOpen
    readonly property bool showAggregateProgress: root.activeCount > 0 && !root.addDialogOpen && !root.settingsOpen
    readonly property bool showClearButton: root.segment === "finished" && root.finishedCount > 0 && !root.addDialogOpen && !root.settingsOpen

    /// Bytes represented by the current segment (finished rows show their size).
    readonly property real segmentBytes: {
        let sum = 0;
        const list = root.segmentTasks || [];
        for (let i = 0; i < list.length; ++i) {
            const t = list[i];
            if (t) sum += Number(t.completed_length) || 0;
        }
        return sum;
    }

    /// The window's bottom ledger: one monospace line of live state. Empty
    /// segments still say something true ("IDLE"), never a decorative dash.
    readonly property string ledgerText: {
        if (!root.isAriaAvailable) return "ENGINE OFFLINE";
        if (root.segment === "active") {
            if (root.activeCount === 0) return "IDLE";
            return root.activeCount + " ACTIVE · "
                + Math.round(root.aggregateProgress * 100) + "% · "
                + root.formatSpeed(root.aggregateSpeed);
        }
        if (root.segment === "queued") return root.queuedCount + " QUEUED";
        return root.finishedCount + " FINISHED"
            + (root.segmentBytes > 0 ? " · " + root.formatBytes(root.segmentBytes) : "");
    }

    readonly property string destinationLabel: {
        if (root.shellState !== null && Config && (root.shellState ? root.shellState.downloadsDir : "") && (root.shellState ? root.shellState.downloadsDir : "").length > 0)
            return (root.shellState ? root.shellState.downloadsDir : "");
        return "~/Downloads";
    }

    Component.onCompleted: {
        if (root.shellState !== null && Config && (root.shellState ? root.shellState.downloadsSplit : false))
            root.setSplitValue((root.shellState ? root.shellState.downloadsSplit : false));
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
        target: (root.shellState !== null && Config && (root.shellState ? root.shellState.dashboardVisible : false) !== undefined) ? Config : null
        function onDashboardVisibleChanged() {
            if (root.shellState !== null && Config && (root.shellState ? root.shellState.dashboardVisible : false) === false) {
                root.addDialogOpen = false;
                root.inputMenuOpen = false;
            }
        }
    }

    // =====================================================================
    // Layout
    // =====================================================================
    // Header drag: the window is frameless (KWin rule), so empty header space
    // starts a compositor-native move exactly like a titlebar. z:-1 keeps every
    // control (segments, Clear, Add, window button) above it.
    MouseArea {
        id: windowDragArea
        visible: root.windowMode
        enabled: root.windowMode
        anchors.left: contentColumn.left
        anchors.right: contentColumn.right
        anchors.top: contentColumn.top
        height: headerRow.height
        z: -1
        cursorShape: Qt.OpenHandCursor
        onPressed: {
            if (root.windowHandle && typeof root.windowHandle.startSystemMove === "function") {
                root.windowHandle.startSystemMove();
            }
        }
    }

    ColumnLayout {
        id: contentColumn
        anchors.fill: parent
        // Token-derived inset: the theme's XL step collapses to 16 in some
        // archetypes, which read as no padding beside the glass rim. 28px is
        // padLarge + spaceMedium; 20px vertical is padLarge + spaceExtraSmall.
        anchors.leftMargin: root.padLarge + root.spaceMedium
        anchors.rightMargin: root.padLarge + root.spaceMedium
        anchors.topMargin: root.padLarge + root.spaceExtraSmall
        anchors.bottomMargin: root.padLarge + root.spaceExtraSmall
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
                                    total_length: (root.downloads !== null && root.downloads ? root.downloads.totalBytes : 0) || 0,
                                    completed_length: (root.downloads !== null && root.downloads ? root.downloads.totalCompletedBytes : 0) || 0,
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
                onClicked: {
                    root.settingsOpen = false;
                    root.addDialogOpen = !root.addDialogOpen;
                }
            }

            // Settings live in the window, next to the close control. The
            // drawer stays a quick view; the window is the manager.
            Rectangle {
                id: settingsButton
                visible: root.windowMode
                implicitWidth: 34
                implicitHeight: 34
                radius: root.radiusItem
                color: root.settingsOpen
                    ? Qt.alpha(root.accent, 0.22)
                    : (settingsHover.hovered ? Qt.alpha(root.accent, 0.14) : "transparent")
                border.width: 1
                border.color: root.settingsOpen
                    ? Qt.alpha(root.accent, 0.55)
                    : (settingsHover.hovered ? Qt.alpha(root.accent, 0.35) : root.borderSubtle)

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "tune"
                    size: 17
                    color: root.settingsOpen ? root.accent : root.textMain
                }

                HoverHandler { id: settingsHover }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.addDialogOpen = false;
                        root.settingsOpen = !root.settingsOpen;
                    }
                }
            }

            // One download UI, two hosts: the drawer opens the dedicated window,
            // the window closes itself. Same control, opposite verbs.
            Rectangle {
                id: windowButton
                implicitWidth: 34
                implicitHeight: 34
                radius: root.radiusItem
                color: windowHover.hovered ? Qt.alpha(root.accent, 0.20) : "transparent"
                border.width: 1
                border.color: windowHover.hovered ? Qt.alpha(root.accent, 0.45) : root.borderSubtle

                MaterialIcon {
                    anchors.centerIn: parent
                    text: root.windowMode ? "close" : "open_in_new"
                    size: 17
                    color: root.windowMode ? root.textMain : root.accent
                }

                HoverHandler { id: windowHover }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (root.windowMode) {
                            root.closeRequested();
                        } else if (root.shellState !== null && Config
                                && root.intents !== null) {
                            root.intents && root.intents.request("downloads.window");
                        }
                    }
                }
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

        // ---- Missing aria2 install banner / guide ----
        Card {
            id: ariaInstallBanner
            Layout.fillWidth: true
            visible: (root.downloads !== null && root.downloads && !root.downloads.ariaAvailable)
            radius: root.radiusCard
            implicitHeight: bannerColumn.implicitHeight + root.padMedium * 2

            ColumnLayout {
                id: bannerColumn
                anchors.fill: parent
                anchors.margins: root.padMedium
                spacing: root.spaceSmall

                RowLayout {
                    Layout.fillWidth: true
                    spacing: root.spaceSmall

                    Rectangle {
                        implicitWidth: 32
                        implicitHeight: 32
                        radius: root.radiusFull
                        color: Qt.alpha(root.accent, 0.16)
                        border.width: 1
                        border.color: Qt.alpha(root.accent, 0.30)

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: "warning"
                            size: 18
                            color: root.accent
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Text {
                            text: "Aria2 download engine not found"
                            font.family: root.fontFamily
                            font.pixelSize: root.fontBodySmall
                            font.weight: Font.DemiBold
                            color: root.textMain
                        }

                        Text {
                            Layout.fillWidth: true
                            text: "Astral Plasma uses aria2 for fast multi-connection downloading. Install it to enable downloading:"
                            font.family: root.fontFamily
                            font.pixelSize: root.fontLabelSmall
                            color: root.textMuted
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: root.spaceSmall

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 32
                        radius: root.radiusItem
                        color: root.darkMode ? Qt.rgba(0, 0, 0, 0.45) : Qt.rgba(255, 255, 255, 0.55)
                        border.width: 1
                        border.color: root.borderSubtle

                        Text {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            verticalAlignment: Text.AlignVCenter
                            text: (root.downloads !== null && root.downloads && root.downloads.ariaInstallCommand)
                                ? root.downloads.ariaInstallCommand
                                : "sudo pacman -S aria2"
                            font.family: root.fontMonospace
                            font.pixelSize: root.fontLabelSmall
                            color: root.accent
                            elide: Text.ElideRight
                        }
                    }

                    LiquidGlassButton {
                        id: copyCmdButton
                        implicitWidth: 84
                        implicitHeight: 32
                        paddingHorizontal: 12
                        paddingVertical: 6
                        text: copyTimer.running ? "Copied!" : "Copy"
                        iconText: copyTimer.running ? "check" : "content_copy"
                        iconSize: 14
                        elevation: 3
                        onClicked: {
                            const cmd = (root.downloads !== null && root.downloads && root.downloads.ariaInstallCommand)
                                ? root.downloads.ariaInstallCommand
                                : "sudo pacman -S aria2";
                            if (root.downloads !== null && root.downloads && typeof root.downloads.copyToClipboard === "function") {
                                root.downloads.copyToClipboard(cmd);
                            }
                            copyTimer.restart();
                        }

                        Timer {
                            id: copyTimer
                            interval: 2000
                            repeat: false
                        }
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

                // Warning hint if aria2 is missing
                RowLayout {
                    Layout.fillWidth: true
                    visible: !root.isAriaAvailable
                    spacing: 6

                    MaterialIcon {
                        text: "warning"
                        size: 14
                        color: root.accent
                    }

                    Text {
                        Layout.fillWidth: true
                        text: "Aria2 is not installed. Install it with your package manager or click below to copy the command."
                        font.family: root.fontFamily
                        font.pixelSize: root.fontLabelSmall
                        color: root.textMuted
                        wrapMode: Text.WordWrap
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
                        implicitWidth: !root.isAriaAvailable ? 130 : 116
                        implicitHeight: 32
                        paddingHorizontal: 14
                        paddingVertical: 6
                        text: !root.isAriaAvailable
                            ? (copySubmitTimer.running ? "Copied!" : "Install Aria2")
                            : "Download"
                        iconText: !root.isAriaAvailable
                            ? (copySubmitTimer.running ? "check" : "content_copy")
                            : "download"
                        iconSize: 15
                        isPrimary: true
                        elevation: 4
                        onClicked: {
                            if (root.isAriaAvailable) {
                                root.submitDownload();
                            } else {
                                const cmd = (root.downloads !== null && root.downloads && root.downloads.ariaInstallCommand)
                                    ? root.downloads.ariaInstallCommand
                                    : "sudo pacman -S aria2";
                                if (root.downloads !== null && root.downloads && typeof root.downloads.copyToClipboard === "function") {
                                    root.downloads.copyToClipboard(cmd);
                                }
                                copySubmitTimer.restart();
                            }
                        }

                        Timer {
                            id: copySubmitTimer
                            interval: 2000
                            repeat: false
                        }
                    }
                }
            }
        }

        // ---- Engine-wide settings (window host only) ----
        //
        // A modal sheet over the task list, not a second page inside the page:
        // the manager stays visible behind it, the window header keeps its one
        // identity, and the sheet is the same width at any window size.
        Item {
            id: settingsOverlay
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.windowMode && root.settingsOpen
            z: 50
            opacity: visible ? 1.0 : 0.0

            Behavior on opacity {
                NumberAnimation {
                    duration: Theme.animExpressiveDefaultEffects
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Theme.curveExpressiveDefaultEffects
                }
            }

            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.45)

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.settingsOpen = false
                }
            }

            DownloadSettingsPanel {
                downloads: root.downloads
                shellState: root.shellState
                intents: root.intents
                id: settingsPanel
                anchors.centerIn: parent
                width: Math.min(680, parent.width - 48)
                height: Math.min(implicitHeight, parent.height - 32)
                scale: settingsOverlay.visible ? 1.0 : 0.97

                Behavior on scale {
                    NumberAnimation {
                        duration: Theme.animExpressiveFastSpatial
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Theme.curveExpressiveFastSpatial
                    }
                }

                onCloseRequested: root.settingsOpen = false
            }
        }

        // ---- Empty state: a composed moment, not a void ----
        Item {
            id: emptyState
            Layout.fillWidth: true
            // In the window the empty state and the list share one stable stage,
            // so switching segments never shifts the header or the footer. The
            // drawer keeps its compact 150px block.
            Layout.fillHeight: root.windowMode
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
                        text: (!root.isAriaAvailable && root.segment !== "finished")
                            ? "warning"
                            : (root.segment === "finished" ? "task_alt" : "cloud_download")
                        size: 30
                        color: root.accent
                    }
                }

                Text {
                    id: emptyTitle
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: (!root.isAriaAvailable && root.segment !== "finished")
                        ? "Aria2 not installed"
                        : (root.segment === "active"
                            ? "No active downloads"
                            : (root.segment === "queued" ? "Queue is empty" : "Nothing finished yet"))
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
                    text: (!root.isAriaAvailable && root.segment !== "finished")
                        ? "Install aria2 with your package manager to start downloading files directly in Astral Plasma."
                        : (root.segment === "active"
                            ? "Paste a link with Add — it starts downloading right away."
                            : (root.segment === "queued"
                                ? "Paused and waiting downloads wait here until a slot frees up."
                                : "Completed and failed downloads land here with their actions."))
                    font.family: root.fontFamily
                    font.pixelSize: root.fontLabelSmall
                    color: root.textMuted
                    style: Text.Outline
                    styleColor: root.haloColor
                }

                Item { width: 1; height: 2 }

                PillButton {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: root.isAriaAvailable
                    label: root.segment === "finished" ? "Open downloads folder" : "Add a download"
                    variant: "filled"
                    active: true
                    onClicked: {
                        if (root.segment === "finished") {
                            if (root.downloads !== null && root.downloads) {
                                root.downloads.openFolder("");
                            }
                        } else {
                            root.addDialogOpen = true;
                        }
                    }
                }
            }
        }

        // ---- Task list: bounded, glass rows, per-row progress + D5 actions ----
        Flickable {
            id: taskList
            Layout.fillWidth: true
            // Drawer: content-driven (capped at four rows). Window: the layout
            // has spare height, so the list takes it instead of leaving a gap.
            Layout.fillHeight: true
            Layout.preferredHeight: Math.min(contentHeight, root.maxListHeight)
            // Drawer: a bounded four-row window that scrolls. Window: the
            // stage owns the height, so the list may use all of it.
            Layout.maximumHeight: root.windowMode ? 100000 : root.maxListHeight
            visible: root.showTaskList
            clip: true
            contentHeight: listColumn.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: listColumn
                width: parent.width
                spacing: root.spaceMedium

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
                        implicitHeight: rowColumn.implicitHeight + root.padMedium * 2
                        radius: root.radiusCard

                        MouseArea {
                            anchors.fill: parent
                            z: -1
                            cursorShape: (taskCard.status === "complete") ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: {
                                if (taskCard.status === "complete" && root.downloads !== null && root.downloads) {
                                    const t = taskCard.task;
                                    const name = (t && t.name) || "";
                                    const dir = (t && t.dir) || "";
                                    root.downloads.openFile(dir, name);
                                }
                            }
                        }

                        ColumnLayout {
                            id: rowColumn
                            anchors.fill: parent
                            anchors.margins: root.padMedium
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

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 6

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

                                        // Per-task connections. aria2 restarts the task
                                        // internally when this changes and resumes from
                                        // its control file, so progress is kept.
                                        RowLayout {
                                            id: partsStepper
                                            spacing: 1
                                            Layout.alignment: Qt.AlignVCenter
                                            visible: taskCard.status === "active"
                                                || taskCard.status === "waiting"
                                                || taskCard.status === "paused"

                                            readonly property int parts: root.taskParts(taskCard.task)

                                            Rectangle {
                                                implicitWidth: 18
                                                implicitHeight: 18
                                                radius: root.radiusFull
                                                color: partsMinus.containsMouse && partsStepper.parts > 1
                                                    ? Qt.alpha(root.accent, 0.22) : "transparent"

                                                MaterialIcon {
                                                    anchors.centerIn: parent
                                                    text: "remove"
                                                    size: 13
                                                    color: root.textMuted
                                                    opacity: partsStepper.parts > 1 ? 1.0 : 0.35
                                                }

                                                MouseArea {
                                                    id: partsMinus
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    enabled: partsStepper.parts > 1
                                                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                    onClicked: root.stepParts(taskCard.task, -1)
                                                }
                                            }

                                            Text {
                                                text: partsStepper.parts + " parts"
                                                font.family: root.fontMonospace
                                                font.pixelSize: 10
                                                color: root.textMuted
                                                horizontalAlignment: Text.AlignHCenter
                                            }

                                            Rectangle {
                                                implicitWidth: 18
                                                implicitHeight: 18
                                                radius: root.radiusFull
                                                color: partsPlus.containsMouse && partsStepper.parts < 16
                                                    ? Qt.alpha(root.accent, 0.22) : "transparent"

                                                MaterialIcon {
                                                    anchors.centerIn: parent
                                                    text: "add"
                                                    size: 13
                                                    color: root.textMuted
                                                    opacity: partsStepper.parts < 16 ? 1.0 : 0.35
                                                }

                                                MouseArea {
                                                    id: partsPlus
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    enabled: partsStepper.parts < 16
                                                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                    onClicked: root.stepParts(taskCard.task, 1)
                                                }
                                            }
                                        }
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
                                                    if (root.downloads === null) return;
                                                    const t = taskCard.task;
                                                    const gid = (t && t.gid) || "";
                                                    const name = (t && t.name) || "";
                                                    const dir = (t && t.dir) || "";
                                                    if (actionButton.modelData === "pause") root.downloads.pause(gid);
                                                    else if (actionButton.modelData === "resume") root.downloads.resume(gid);
                                                    else if (actionButton.modelData === "cancel") root.downloads.cancel(gid, false);
                                                    else if (actionButton.modelData === "retry") root.downloads.retry(gid);
                                                    else if (actionButton.modelData === "open") root.downloads.openFile(dir, name);
                                                    else if (actionButton.modelData === "folder") root.downloads.openFolder(dir);
                                                    else root.downloads.removeResult(gid);
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // Per-row progress track.
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 3
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

        // ---- Ledger: the window's bottom edge ---------------------------
        //
        // A tall window with one row otherwise ends in a void. The ledger is
        // the base line: live segment state on the left, destination and the
        // folder action on the right, in the same monospace voice as the
        // settings console. The drawer stays compact (window host only).
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            visible: !root.addDialogOpen && !root.settingsOpen
            color: root.borderSubtle
        }

        RowLayout {
            id: ledger
            Layout.fillWidth: true
            Layout.preferredHeight: 36
            visible: !root.addDialogOpen && !root.settingsOpen
            spacing: 10

            Rectangle {
                implicitWidth: 6
                implicitHeight: 6
                radius: 3
                color: (root.segment === "active" && root.activeCount > 0)
                    ? root.accent
                    : (root.segment === "finished" && root.finishedCount > 0
                        ? ((typeof Colors !== "undefined" && Colors.success) ? Colors.success : "#34d399")
                        : root.textMuted)
            }

            Text {
                text: root.ledgerText
                font.family: root.fontMonospace
                font.pixelSize: 10
                font.letterSpacing: 0.8
                color: root.textMain
            }

            Item { Layout.fillWidth: true }

            Text {
                text: root.destinationLabel
                font.family: root.fontMonospace
                font.pixelSize: 10
                color: root.textMuted
                elide: Text.ElideMiddle
                Layout.maximumWidth: 260
            }

            Rectangle {
                implicitWidth: openFolderRow.implicitWidth + 18
                implicitHeight: 26
                radius: root.radiusFull
                color: folderHover.hovered ? Qt.alpha(root.accent, 0.18) : "transparent"
                border.width: 1
                border.color: folderHover.hovered ? Qt.alpha(root.accent, 0.45) : root.borderSubtle

                RowLayout {
                    id: openFolderRow
                    anchors.centerIn: parent
                    spacing: 5

                    MaterialIcon {
                        text: "folder_open"
                        size: 13
                        color: root.textMain
                    }

                    Text {
                        text: "Open folder"
                        font.family: root.fontFamily
                        font.pixelSize: 10
                        color: root.textMain
                    }
                }

                HoverHandler { id: folderHover }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (root.downloads !== null && root.downloads) {
                            root.downloads.openFolder("");
                        }
                    }
                }
            }

            // Reserved slot: Clear appears only on Finished, but its width is
            // always allocated, so the ledger's actions never jump either.
            Item {
                implicitWidth: 76
                implicitHeight: 26

                LiquidGlassButton {
                    id: clearButton
                    anchors.fill: parent
                    visible: root.showClearButton
                    text: "Clear"
                    iconText: "delete_sweep"
                    iconSize: 13
                    paddingHorizontal: 8
                    paddingVertical: 3
                    elevation: 2
                    onClicked: {
                        if (root.downloads !== null && root.downloads
                                && typeof root.downloads.purge === "function") {
                            root.downloads.purge();
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
