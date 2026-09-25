import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../theme"
import "../components"
import "../config"
import "../services"

// Active-apps overview: a fullscreen liquid-glass surface listing every
// running window with a live thumbnail and integrated type-to-search across
// both open windows and installed applications.
// Toggled by the bare Meta key:
//   KWin registerShortcut -> daemon ShellIpc whitelist -> `overview` IPC ->
//   Config.overviewVisible -> this surface drives WindowService's capture
//   cycle while open.
PanelWindow {
    id: root

    property ShellScreen targetScreen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
    screen: targetScreen

    readonly property bool openRequested: Config.overviewVisible

    // A pick already handed activation to its window; dismissing WITHOUT a
    // pick must hand compositor activation back (`focus restore`), because
    // KWin does not reassign it when our Exclusive focus request is withdrawn
    // - which would freeze the dock's active-app display (the power modal and
    // UnifiedShell close over the exact same loop).
    property string pickedWindowId: ""

    // Entrance/exit progress. The window stays mapped while the close
    // animation still has frames (CentralDropdown's proven pattern), driven
    // by the M3 slow-spatial token - DESIGN.md assigns that token to large
    // overlays such as this one.
    property real offsetProgress: openRequested ? 1.0 : 0.0
    Behavior on offsetProgress {
        NumberAnimation {
            duration: Theme.animExpressiveSlowSpatial
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.curveExpressiveSlowSpatial
        }
    }

    visible: offsetProgress > 0.001

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    // Dim scrim, fading with the entrance (never an opaque slab).
    color: Qt.rgba(0, 0, 0, 0.55 * root.offsetProgress)

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: openRequested ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // Compositor backdrop blur across the whole surface. ONE boolean gates
    // every dimension, so the region is always a valid positive-area rect or
    // fully empty - never a degenerate sliver KWin would keep painting. It
    // clears the moment closing starts, while 650ms of animation frames
    // remain to flush the clear (docs/LESSONS.md blur-region teardown rules).
    readonly property bool blurWanted: openRequested
    BackgroundEffect.blurRegion: Region {
        x: 0
        y: 0
        width: root.blurWanted ? root.width : 0
        height: root.blurWanted ? root.height : 0
    }

    // Installed applications source (shared with WindowService)
    property var installedApps: (typeof WindowService !== "undefined" && WindowService.installedApps) ? WindowService.installedApps : []

    // Search query state
    property string queryText: ""
    readonly property string searchQuery: queryText.trim().toLowerCase()

    // Navigation indices
    property int selectedSearchIndex: 0
    property int selectedGridIndex: 0

    // Match scoring helper: exact = 100, prefix = 80, word-start = 60, substring = 40
    function scoreItem(text, q) {
        if (!text) return 0;
        const t = text.toLowerCase();
        if (t === q) return 100;
        if (t.startsWith(q)) return 80;
        const wordIdx = t.indexOf(" " + q);
        if (wordIdx !== -1) return 60;
        if (t.indexOf(q) !== -1) return 40;
        return 0;
    }

    // Filtered & ranked open windows matching search query
    readonly property var matchingWindows: {
        if (!searchQuery) return [];
        const q = searchQuery;
        const wins = WindowService.windows || [];
        const scored = [];
        for (let i = 0; i < wins.length; i++) {
            const w = wins[i];
            const sApp = scoreItem(w.appName, q);
            const sTitle = scoreItem(w.title, q);
            const sId = scoreItem(w.appId, q);
            const best = Math.max(sApp, sTitle, sId);
            if (best > 0) {
                scored.push({ win: w, score: best });
            }
        }
        scored.sort((a, b) => b.score - a.score);
        return scored.map(item => item.win);
    }

    // Filtered & ranked installed applications matching search query
    readonly property var matchingInstalledApps: {
        if (!searchQuery) return [];
        const q = searchQuery;
        const apps = root.installedApps || [];
        const scored = [];
        for (let i = 0; i < apps.length; i++) {
            const a = apps[i];
            const sName = scoreItem(a.name, q);
            const sComment = scoreItem(a.comment, q);
            const sExec = scoreItem(a.exec, q);
            const best = Math.max(sName, sComment > 0 ? sComment - 20 : 0, sExec > 0 ? sExec - 30 : 0);
            if (best > 0) {
                scored.push({ app: a, score: best });
            }
        }
        scored.sort((a, b) => b.score - a.score);
        const maxMatches = 12;
        return scored.slice(0, maxMatches).map(item => item.app);
    }

    // Unified flat list for search navigation & virtualized display
    readonly property var searchResults: {
        if (!searchQuery) return [];
        const res = [];
        for (let i = 0; i < matchingWindows.length; i++) {
            res.push({ type: "window", data: matchingWindows[i] });
        }
        for (let j = 0; j < matchingInstalledApps.length; j++) {
            res.push({ type: "app", data: matchingInstalledApps[j] });
        }
        return res;
    }

    onQueryTextChanged: {
        if (searchInput.text !== root.queryText) {
            searchInput.text = root.queryText;
        }
        selectedSearchIndex = 0;
        if (resultsList && resultsList.visible) {
            resultsList.positionViewAtIndex(0, ListView.Beginning);
        }
    }

    onSelectedSearchIndexChanged: {
        if (resultsList && resultsList.visible && selectedSearchIndex >= 0 && selectedSearchIndex < searchResults.length) {
            resultsList.positionViewAtIndex(selectedSearchIndex, ListView.Contain);
        }
    }

    function selectNextSearchItem() {
        if (searchResults.length > 0) {
            selectedSearchIndex = Math.min(searchResults.length - 1, selectedSearchIndex + 1);
        }
    }

    function selectPreviousSearchItem() {
        if (searchResults.length > 0) {
            selectedSearchIndex = Math.max(0, selectedSearchIndex - 1);
        }
    }

    function executeSearchItem() {
        if (searchResults.length === 0) return;
        const item = searchResults[selectedSearchIndex];
        if (!item) return;
        if (item.type === "window") {
            root.pickedWindowId = String(item.data.id);
            WindowService.activateWindow(item.data.id);
            Config.closeOverview();
        } else if (item.type === "app") {
            WindowService.launchApp(item.data.desktop_file || item.data.exec || item.data.name, item.data);
            Config.closeOverview();
        }
    }

    function selectGridLeft() {
        const count = WindowService.windows ? WindowService.windows.length : 0;
        if (count > 0) {
            selectedGridIndex = Math.max(0, selectedGridIndex - 1);
        }
    }

    function selectGridRight() {
        const count = WindowService.windows ? WindowService.windows.length : 0;
        if (count > 0) {
            selectedGridIndex = Math.min(count - 1, selectedGridIndex + 1);
        }
    }

    function selectGridUp() {
        const count = WindowService.windows ? WindowService.windows.length : 0;
        const cols = root.grid.cols || 1;
        if (count > 0) {
            selectedGridIndex = Math.max(0, selectedGridIndex - cols);
        }
    }

    function selectGridDown() {
        const count = WindowService.windows ? WindowService.windows.length : 0;
        const cols = root.grid.cols || 1;
        if (count > 0) {
            selectedGridIndex = Math.min(count - 1, selectedGridIndex + cols);
        }
    }

    function executeGridItem() {
        const wins = WindowService.windows || [];
        if (selectedGridIndex >= 0 && selectedGridIndex < wins.length) {
            const win = wins[selectedGridIndex];
            root.pickedWindowId = String(win.id);
            WindowService.activateWindow(win.id);
            Config.closeOverview();
        }
    }

    // Escape closes. The scrim handles pointer dismissal; Meta toggles from
    // anywhere through IPC and needs no focus of its own.
    Item {
        id: keySink
        anchors.fill: parent
        focus: root.openRequested && !searchInput.activeFocus
        Keys.onEscapePressed: Config.closeOverview()
    }

    MouseArea {
        anchors.fill: parent
        onClicked: Config.closeOverview()
    }

    Process {
        id: focusRestoreProc
    }

    Connections {
        target: Config
        function onOverviewVisibleChanged() {
            if (Config.overviewVisible) {
                root.pickedWindowId = "";
                root.queryText = "";
                root.selectedSearchIndex = 0;
                root.selectedGridIndex = 0;
                searchInput.text = "";
                searchInput.forceActiveFocus();
                WindowService.startOverviewThumbnails();
                if ((!root.installedApps || root.installedApps.length === 0) && typeof WindowService !== "undefined" && WindowService.reloadInstalledApps) {
                    WindowService.reloadInstalledApps();
                }
            } else {
                WindowService.stopOverviewThumbnails();
                if (root.pickedWindowId === "") {
                    focusRestoreProc.command = [Config.daemonBin, "focus", "restore"];
                    focusRestoreProc.running = true;
                }
                root.pickedWindowId = "";
                root.queryText = "";
            }
        }
    }

    // Windows opening/closing while the overview is visible re-target the
    // rotation without restarting it (PreviewCycle re-reads items at wrap).
    Connections {
        target: WindowService
        function onWindowsChanged() {
            if (Config.overviewVisible) {
                WindowService.refreshOverviewThumbnails();
            }
        }
    }

    // Subtle radial depth gradient behind cards for authentic dark glass depth
    Rectangle {
        anchors.fill: parent
        opacity: root.offsetProgress
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.28) }
            GradientStop { position: 0.45; color: "transparent" }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.38) }
        }
    }

    // Integrated Liquid Glass Search & Status Capsule (macOS & Raycast style)
    LiquidGlassCard {
        id: searchCapsule
        anchors.top: parent.top
        anchors.topMargin: Math.max(16, root.gridMargin * 0.32)
        anchors.horizontalCenter: parent.horizontalCenter
        height: 46
        width: Math.min(root.searchQuery.length > 0 ? 680 : 540, root.width - 48)
        radius: Theme.radiusGlassPill
        elevation: 8
        showShadow: true
        showSpecular: true
        showCaustic: true
        opacity: root.offsetProgress

        Behavior on width {
            NumberAnimation {
                duration: Theme.animExpressiveFastSpatial
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.curveExpressiveDefaultSpatial
            }
        }

        transform: Translate {
            y: (1.0 - root.offsetProgress) * -20
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 12
            spacing: 10

            MaterialIcon {
                text: "search"
                size: 20
                color: root.searchQuery.length > 0 ? Colors.primary : Colors.textMuted
            }

            TextInput {
                id: searchInput
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                font.family: Theme.fontFamily
                font.pixelSize: 14
                font.weight: Font.Medium
                color: "#FFFFFF"
                selectByMouse: true
                clip: true
                text: root.queryText
                onTextEdited: {
                    root.queryText = text;
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !searchInput.text && !searchInput.inputMethodComposing
                    text: "Search open windows & applications..."
                    font: searchInput.font
                    color: Qt.alpha("#FFFFFF", 0.45)
                }

                Keys.onEscapePressed: {
                    if (root.queryText.length > 0) {
                        root.queryText = "";
                    } else {
                        Config.closeOverview();
                    }
                }

                Keys.onPressed: (event) => {
                    if (event.key === Qt.Key_Escape) {
                        if (root.queryText.length > 0) {
                            root.queryText = "";
                            event.accepted = true;
                        } else {
                            Config.closeOverview();
                            event.accepted = true;
                        }
                    } else if (event.key === Qt.Key_Down) {
                        if (root.searchQuery.length > 0) {
                            root.selectNextSearchItem();
                        } else {
                            root.selectGridDown();
                        }
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Up) {
                        if (root.searchQuery.length > 0) {
                            root.selectPreviousSearchItem();
                        } else {
                            root.selectGridUp();
                        }
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Left) {
                        if (root.searchQuery.length === 0) {
                            root.selectGridLeft();
                            event.accepted = true;
                        }
                    } else if (event.key === Qt.Key_Right) {
                        if (root.searchQuery.length === 0) {
                            root.selectGridRight();
                            event.accepted = true;
                        }
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        if (root.searchQuery.length > 0) {
                            root.executeSearchItem();
                        } else {
                            root.executeGridItem();
                        }
                        event.accepted = true;
                    }
                }
            }

            // Results count badge when searching
            Rectangle {
                visible: root.searchQuery.length > 0
                height: 22
                width: matchText.implicitWidth + 14
                radius: 11
                color: Colors.primaryContainer

                Text {
                    id: matchText
                    anchors.centerIn: parent
                    text: root.matchingWindows.length + " win · " + root.matchingInstalledApps.length + " app"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontLabelSmall
                    font.weight: Font.Bold
                    color: Colors.onPrimaryContainer
                }
            }

            // Clear search button
            Rectangle {
                visible: searchInput.text.length > 0
                width: 24
                height: 24
                radius: 12
                color: clearMouse.containsMouse ? Colors.glassCardHover : "transparent"

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "close"
                    size: 15
                    color: clearMouse.containsMouse ? "#FFFFFF" : Colors.textMuted
                }

                MouseArea {
                    id: clearMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.queryText = "";
                        searchInput.forceActiveFocus();
                    }
                }
            }

            // Active windows badge and Esc hint when idle
            Row {
                visible: root.searchQuery.length === 0
                spacing: 6
                Layout.alignment: Qt.AlignVCenter

                Rectangle {
                    height: 22
                    width: badgeText.implicitWidth + 14
                    radius: 11
                    color: Colors.primaryContainer

                    Row {
                        anchors.centerIn: parent
                        spacing: 4

                        MaterialIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "space_dashboard"
                            size: 13
                            color: Colors.onPrimaryContainer
                        }

                        Text {
                            id: badgeText
                            anchors.verticalCenter: parent.verticalCenter
                            text: String(WindowService.windows ? WindowService.windows.length : 0) + " Active"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontLabelSmall
                            font.weight: Font.Bold
                            color: Colors.onPrimaryContainer
                        }
                    }
                }

                Rectangle {
                    height: 22
                    width: escText.implicitWidth + 12
                    radius: 6
                    color: Qt.rgba(1, 1, 1, Colors.isDarkMode ? 0.08 : 0.12)
                    border.width: 1
                    border.color: Colors.glassBorderSubtle

                    Text {
                        id: escText
                        anchors.centerIn: parent
                        text: "esc"
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        font.weight: Font.Medium
                        color: Colors.textMuted
                    }
                }
            }
        }
    }

    OverviewLayout {
        id: layout
    }

    readonly property int gridMargin: Theme.spaceExtraLarge * 2
    readonly property int gridGap: Theme.spaceLarge
    readonly property real availW: Math.max(0, root.width - 2 * root.gridMargin)
    readonly property real availH: Math.max(0, root.height - 2 * root.gridMargin - 28)
    readonly property var grid: layout.compute(
        root.availW,
        root.availH,
        WindowService.windows ? WindowService.windows.length : 0,
        { gap: root.gridGap })
    readonly property bool gridOverflow: root.grid.gridH > root.availH

    // macOS Exposé dispersal entrance: board glides vertically and springs into place
    Item {
        id: content
        anchors.fill: parent
        visible: root.searchQuery.length === 0
        opacity: (root.searchQuery.length === 0 ? 1.0 : 0.0) * root.offsetProgress
        scale: 0.90 + 0.10 * root.offsetProgress
        transform: Translate {
            y: (1.0 - root.offsetProgress) * 32
        }
        transformOrigin: Item.Center

        Behavior on opacity { NumberAnimation { duration: Theme.animExpressiveFastEffects } }

        GridView {
            id: gridV
            visible: root.grid.cols > 0
            clip: true
            width: root.grid.cols > 0 ? root.grid.gridW + root.gridGap : 0
            height: root.gridOverflow ? root.availH : root.grid.gridH + root.gridGap
            x: (root.width - width) / 2 + root.gridGap / 2
            y: root.gridOverflow ? (root.gridMargin + 24) : ((root.height - height) / 2 + root.gridGap / 2 + 16)
            cellWidth: root.grid.cellW + root.gridGap
            cellHeight: root.grid.cellH + root.gridGap
            interactive: contentHeight > height
            model: WindowService.windows

            delegate: Item {
                id: cardWrapper
                width: root.grid.cellW
                height: root.grid.cellH

                readonly property bool isPicked: root.pickedWindowId === String(modelData.id)
                readonly property bool isOtherPicked: root.pickedWindowId !== "" && !isPicked
                readonly property bool isKeyboardSelected: root.searchQuery.length === 0 && root.selectedGridIndex === index

                z: isPicked ? 100 : (cardMouse.containsMouse || isKeyboardSelected ? 35 : (modelData.isActive ? 5 : 1))

                // macOS Exposé: other cards dissolve smoothly when one is chosen
                opacity: isOtherPicked ? 0.0 : 1.0
                Behavior on opacity {
                    NumberAnimation {
                        duration: Theme.animExpressiveFastEffects
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Theme.curveExpressiveFastEffects
                    }
                }

                // macOS Exposé spring physics: subtle 3.5% lift on hover, zoom forward on selection
                scale: isPicked ? 1.08 : (cardMouse.containsMouse || isKeyboardSelected ? 1.035 : 1.0)
                Behavior on scale {
                    NumberAnimation {
                        duration: Theme.animExpressiveFastSpatial
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Theme.curveExpressiveFastSpatial
                    }
                }

                transform: Translate {
                    y: (cardMouse.containsMouse || isKeyboardSelected) ? -4 : 0
                    Behavior on y {
                        NumberAnimation {
                            duration: Theme.animExpressiveFastSpatial
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Theme.curveExpressiveFastSpatial
                        }
                    }
                }

                LiquidGlassCard {
                    id: card
                    anchors.fill: parent
                    radius: Theme.radiusGlassCard
                    interactive: true
                    hovered: cardMouse.containsMouse || isKeyboardSelected
                    selected: Boolean(modelData.isActive) || isKeyboardSelected
                    accentGlint: (modelData.isActive || isKeyboardSelected) ? Colors.primary : Colors.glassBorderSpecular
                    elevation: isPicked ? 24 : (cardMouse.containsMouse || isKeyboardSelected ? 16 : (modelData.isActive ? 8 : 4))
                    showShadow: true
                    showSpecular: true
                    showCaustic: true
                    showRefraction: true

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.padSmall
                        spacing: Theme.spaceSmall

                        // Thumbnail well: concentric inner radius
                        // R_inner = R_outer - padding (AGENTS.md glass rule).
                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            Rectangle {
                                anchors.fill: parent
                                radius: Theme.radiusGlassCard - Theme.padSmall
                                color: Colors.surfaceContainerLowest
                                border.width: 1
                                border.color: (cardMouse.containsMouse || isKeyboardSelected)
                                    ? Qt.alpha(Colors.primary, 0.45)
                                    : (modelData.isActive
                                        ? Qt.alpha(Colors.primary, 0.25)
                                        : (Colors.isDarkMode ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06)))
                                clip: true

                                Behavior on border.color { ColorAnimation { duration: Theme.animExpressiveFastEffects } }

                                LiveWindowThumbnail {
                                    id: thumb
                                    anchors.fill: parent
                                    anchors.margins: 1
                                    source: (WindowService.overviewThumbnails || {})[String(modelData.id)] || ""
                                    identity: modelData.id
                                    fillMode: Image.PreserveAspectFit
                                }

                                MaterialIcon {
                                    anchors.centerIn: parent
                                    text: "wallpaper"
                                    size: 28
                                    color: Colors.textOnSurfaceVariant
                                    visible: !thumb.hasImage
                                }

                                // Specular top glint on thumbnail inner well
                                Rectangle {
                                    anchors.top: parent.top
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    height: 1
                                    color: Qt.rgba(1, 1, 1, Colors.isDarkMode ? 0.16 : 0.35)
                                }
                            }
                        }

                        // App identity card footer
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 22
                            spacing: Theme.spaceSmall

                            Item {
                                Layout.preferredWidth: 18
                                Layout.preferredHeight: 18

                                Image {
                                    anchors.fill: parent
                                    source: Config.iconUrl(modelData.iconName)
                                    fillMode: Image.PreserveAspectFit
                                    visible: status === Image.Ready
                                }

                                MaterialIcon {
                                    anchors.centerIn: parent
                                    text: modelData.materialIcon ? modelData.materialIcon : "window"
                                    size: 15
                                    color: Colors.primary
                                    visible: !parent.children[0].visible
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                text: (modelData.title && modelData.title.trim() !== "")
                                    ? modelData.title
                                    : (modelData.appName || "")
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontLabelSmall
                                font.weight: modelData.isActive ? Font.Bold : Font.Medium
                                color: modelData.isActive ? Colors.primary : Colors.textOnSurface
                                elide: Text.ElideRight
                            }

                            // Active window indicator dot
                            Rectangle {
                                visible: Boolean(modelData.isActive)
                                Layout.preferredWidth: 6
                                Layout.preferredHeight: 6
                                radius: 3
                                color: Colors.primary
                            }
                        }
                    }

                    // macOS-like circular close ("X") button on card hover
                    Rectangle {
                        id: closeBtn
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: Math.round(Theme.padSmall * 0.75)
                        width: 22
                        height: 22
                        radius: 11
                        z: 50
                        color: closeMouse.containsMouse
                            ? Colors.accentError
                            : (Colors.isDarkMode ? Qt.rgba(0.12, 0.12, 0.16, 0.85) : Qt.rgba(1.0, 1.0, 1.0, 0.90))
                        border.width: 1
                        border.color: closeMouse.containsMouse
                            ? Colors.accentOnError
                            : (Colors.isDarkMode ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(0, 0, 0, 0.12))

                        opacity: cardMouse.containsMouse ? 1.0 : 0.0
                        scale: cardMouse.containsMouse ? (closeMouse.pressed ? 0.88 : (closeMouse.containsMouse ? 1.10 : 1.0)) : 0.70
                        visible: opacity > 0.01

                        Behavior on opacity { NumberAnimation { duration: Theme.animExpressiveFastEffects } }
                        Behavior on scale {
                            NumberAnimation {
                                duration: Theme.animExpressiveFastSpatial
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Theme.curveExpressiveFastSpatial
                            }
                        }
                        Behavior on color { ColorAnimation { duration: Theme.animExpressiveFastEffects } }

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: "close"
                            size: 13
                            color: closeMouse.containsMouse ? Colors.accentOnError : Colors.textOnSurface
                        }

                        MouseArea {
                            id: closeMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: (mouse) => {
                                mouse.accepted = true;
                                WindowService.closeWindow(modelData.id);
                            }
                        }
                    }

                    MouseArea {
                        id: cardMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onPositionChanged: root.selectedGridIndex = index
                        onClicked: {
                            root.pickedWindowId = String(modelData.id);
                            WindowService.activateWindow(modelData.id);
                            Config.closeOverview();
                        }
                    }
                }
            }
        }

        // Empty state: an empty overview is an invitation, not a void.
        Column {
            anchors.centerIn: parent
            spacing: Theme.spaceMedium
            visible: WindowService.windows.length === 0

            MaterialIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "space_dashboard"
                size: 44
                color: Colors.textOnSurfaceVariant
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "No open windows"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontBodyMedium
                font.weight: Font.Medium
                color: Colors.textOnSurfaceVariant
            }
        }
    }

    // Unified Liquid Glass Search Results Board
    Item {
        id: searchResultsContainer
        visible: root.searchQuery.length > 0
        anchors.top: searchCapsule.bottom
        anchors.topMargin: 16
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(760, root.width - 48)

        readonly property real estimatedContentHeight: {
            if (root.searchResults.length === 0) return 140;
            let h = 0;
            if (root.matchingWindows.length > 0) {
                h += 34 + root.matchingWindows.length * 62;
            }
            if (root.matchingInstalledApps.length > 0) {
                h += 34 + root.matchingInstalledApps.length * 54;
            }
            return h + 28;
        }

        height: Math.min(estimatedContentHeight, Math.min(root.height - searchCapsule.y - searchCapsule.height - 40, 560))
        opacity: root.searchQuery.length > 0 ? 1.0 : 0.0
        scale: root.searchQuery.length > 0 ? 1.0 : 0.96
        transform: Translate {
            y: root.searchQuery.length > 0 ? 0 : 16
        }

        Behavior on height {
            NumberAnimation {
                duration: Theme.animExpressiveFastSpatial
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.curveExpressiveDefaultSpatial
            }
        }
        Behavior on opacity { NumberAnimation { duration: Theme.animExpressiveFastEffects } }
        Behavior on scale {
            NumberAnimation {
                duration: Theme.animExpressiveFastSpatial
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.curveExpressiveDefaultSpatial
            }
        }
        Behavior on transform {
            NumberAnimation {
                duration: Theme.animExpressiveFastSpatial
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.curveExpressiveDefaultSpatial
            }
        }

        LiquidGlassCard {
            id: searchCard
            anchors.fill: parent
            radius: Theme.radiusGlassModal
            elevation: 16
            showShadow: true
            showSpecular: true
            showCaustic: true
            showRefraction: true

            // Results List View
            ListView {
                id: resultsList
                anchors.fill: parent
                anchors.margins: 14
                clip: true
                spacing: 4
                boundsBehavior: Flickable.StopAtBounds
                model: root.searchResults
                currentIndex: root.selectedSearchIndex
                highlightFollowsCurrentItem: true
                reuseItems: true
                cacheBuffer: 160
                pixelAligned: true
                highlightMoveDuration: 0

                section.property: "type"
                section.criteria: ViewSection.FullString
                section.delegate: Item {
                    width: resultsList.width
                    height: 34

                    Row {
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 6
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        spacing: 8

                        MaterialIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            text: section === "window" ? "space_dashboard" : "apps"
                            size: 14
                            color: Colors.primary
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: section === "window" ? "OPEN WINDOWS" : "APPLICATIONS"
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.weight: Font.Bold
                            font.letterSpacing: 0.8
                            color: Colors.textMuted
                        }

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            height: 16
                            width: secBadge.implicitWidth + 8
                            radius: 8
                            color: Qt.rgba(1, 1, 1, Colors.isDarkMode ? 0.08 : 0.12)

                            Text {
                                id: secBadge
                                anchors.centerIn: parent
                                text: String(section === "window" ? root.matchingWindows.length : root.matchingInstalledApps.length)
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                font.weight: Font.Bold
                                color: Colors.textMuted
                            }
                        }
                    }
                }

                delegate: Rectangle {
                    id: resultRow
                    required property var modelData
                    required property int index

                    readonly property bool isSelected: root.selectedSearchIndex === index
                    readonly property bool isWindow: modelData.type === "window"
                    width: resultsList.width
                    height: isWindow ? 58 : 50
                    radius: Theme.radiusGlassItem
                    color: isSelected
                        ? Colors.glassCardActive
                        : (rowMouse.containsMouse ? Colors.glassCardHover : "transparent")
                    border.color: isSelected
                        ? Colors.glassBorderSpecular
                        : (rowMouse.containsMouse ? Colors.glassBorderSubtle : "transparent")
                    border.width: isSelected ? 1.5 : 1

                    scale: rowMouse.pressed ? 0.985 : (rowMouse.containsMouse ? 1.008 : 1.0)
                    Behavior on scale {
                        NumberAnimation {
                            duration: Theme.animExpressiveFastSpatial
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Theme.curveExpressiveFastSpatial
                        }
                    }
                    Behavior on color { ColorAnimation { duration: Theme.animExpressiveFastEffects } }
                    Behavior on border.color { ColorAnimation { duration: Theme.animExpressiveFastEffects } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 12

                        // Window item: Live thumbnail preview box with overlaid app icon
                        Item {
                            visible: resultRow.isWindow
                            Layout.preferredWidth: 68
                            Layout.preferredHeight: 42
                            Layout.alignment: Qt.AlignVCenter

                            Rectangle {
                                anchors.fill: parent
                                radius: 8
                                color: Colors.surfaceContainerLowest
                                border.width: 1
                                border.color: isSelected ? Qt.alpha(Colors.primary, 0.45) : Qt.rgba(1, 1, 1, 0.10)
                                clip: true

                                LiveWindowThumbnail {
                                    id: rowThumb
                                    anchors.fill: parent
                                    anchors.margins: 1
                                    source: (WindowService.overviewThumbnails || {})[String(modelData.data.id)] || ""
                                    identity: modelData.data.id
                                    fillMode: Image.PreserveAspectFit
                                }

                                MaterialIcon {
                                    anchors.centerIn: parent
                                    text: "wallpaper"
                                    size: 20
                                    color: Colors.textOnSurfaceVariant
                                    visible: !rowThumb.hasImage
                                }
                            }

                            // Small overlaid icon badge
                            Rectangle {
                                anchors.bottom: parent.bottom
                                anchors.right: parent.right
                                anchors.bottomMargin: -2
                                anchors.rightMargin: -2
                                width: 18
                                height: 18
                                radius: 4
                                color: Colors.surfaceContainer
                                border.width: 1
                                border.color: Colors.glassBorderSubtle

                                Image {
                                    anchors.fill: parent
                                    anchors.margins: 2
                                    source: Config.iconUrl(modelData.data.iconName)
                                    fillMode: Image.PreserveAspectFit
                                    visible: status === Image.Ready
                                }

                                MaterialIcon {
                                    anchors.centerIn: parent
                                    text: modelData.data.materialIcon || "window"
                                    size: 11
                                    color: Colors.primary
                                    visible: !parent.children[0].visible
                                }
                            }
                        }

                        // App item: Application Icon
                        Item {
                            visible: !resultRow.isWindow
                            Layout.preferredWidth: 32
                            Layout.preferredHeight: 32
                            Layout.alignment: Qt.AlignVCenter

                            Image {
                                anchors.fill: parent
                                source: Config.iconUrl(modelData.data.icon)
                                fillMode: Image.PreserveAspectFit
                                smooth: true
                                mipmap: true
                                asynchronous: true
                                sourceSize.width: 32
                                sourceSize.height: 32
                                cache: true
                                visible: status === Image.Ready
                            }

                            MaterialIcon {
                                anchors.centerIn: parent
                                text: "rocket_launch"
                                size: 22
                                color: isSelected ? Colors.primary : Colors.textMuted
                                visible: !parent.children[0].visible
                            }
                        }

                        // Text details
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1

                            Text {
                                Layout.fillWidth: true
                                text: resultRow.isWindow
                                    ? ((modelData.data.title && modelData.data.title.trim() !== "") ? modelData.data.title : (modelData.data.appName || "Window"))
                                    : (modelData.data.name || "Application")
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                font.weight: isSelected ? Font.Bold : Font.DemiBold
                                color: isSelected ? "#FFFFFF" : Colors.textOnSurface
                                elide: Text.ElideRight
                            }

                            Text {
                                Layout.fillWidth: true
                                text: resultRow.isWindow
                                    ? (modelData.data.appName || "")
                                    : (modelData.data.comment || modelData.data.exec || "")
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                color: isSelected ? Qt.alpha("#FFFFFF", 0.75) : Colors.textMuted
                                elide: Text.ElideRight
                            }
                        }

                        // Action CTA Pill
                        Rectangle {
                            height: 26
                            width: ctaText.implicitWidth + 16
                            radius: 13
                            color: isSelected ? Colors.primaryContainer : Qt.rgba(1, 1, 1, Colors.isDarkMode ? 0.06 : 0.08)
                            border.width: isSelected ? 0 : 1
                            border.color: Colors.glassBorderSubtle

                            Text {
                                id: ctaText
                                anchors.centerIn: parent
                                text: isSelected
                                    ? (resultRow.isWindow ? "Switch ↵" : "Launch ↵")
                                    : (resultRow.isWindow ? "Window" : "App")
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                font.weight: isSelected ? Font.Bold : Font.Medium
                                color: isSelected ? Colors.onPrimaryContainer : Colors.textMuted
                            }
                        }
                    }

                    MouseArea {
                        id: rowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onPositionChanged: root.selectedSearchIndex = index
                        onClicked: {
                            root.selectedSearchIndex = index;
                            root.executeSearchItem();
                        }
                    }
                }
            }

            // Empty state if no results match query
            Column {
                anchors.centerIn: parent
                spacing: Theme.spaceMedium
                visible: root.searchQuery.length > 0 && root.searchResults.length === 0

                MaterialIcon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "search_off"
                    size: 40
                    color: Colors.textMuted
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "No matching windows or applications"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontBodyMedium
                    font.weight: Font.DemiBold
                    color: Colors.textOnSurface
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Try searching with a different name or keyword"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontBodySmall
                    color: Colors.textMuted
                }
            }
        }
    }
}
