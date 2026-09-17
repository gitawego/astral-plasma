import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "../theme"
import "../components"
import "../config"
import "../services"
import "launcher"

PanelWindow {
    id: root

    property ShellScreen targetScreen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
    screen: targetScreen

    property bool testMode: false
    property bool activeVisible: testMode ? true : (typeof Config !== "undefined" ? Config.commandLauncherVisible : false)

    visible: activeVisible

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: activeVisible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    color: Qt.rgba(0, 0, 0, 0.4) // Dim background overlay

    // Themed token fallbacks
    readonly property color colSurface: (typeof Colors !== "undefined" && Colors.surface) ? Colors.surface : "#1a1b26"
    readonly property color colSurfaceContainer: (typeof Colors !== "undefined" && Colors.surfaceContainer) ? Colors.surfaceContainer : "#24283b"
    readonly property color colSurfaceContainerHigh: (typeof Colors !== "undefined" && Colors.surfaceContainerHigh) ? Colors.surfaceContainerHigh : "#2f354a"
    readonly property color colPrimary: (typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#7aa2f7"
    readonly property color colOnPrimary: (typeof Colors !== "undefined" && Colors.onPrimary) ? Colors.onPrimary : "#15161e"
    readonly property color colTextOnSurface: (typeof Colors !== "undefined" && Colors.textOnSurface) ? Colors.textOnSurface : "#c0caf5"
    readonly property color colTextMuted: (typeof Colors !== "undefined" && Colors.textMuted) ? Colors.textMuted : "#787c99"
    readonly property color colBorderSubtle: (typeof Theme !== "undefined" && Theme.borderSubtle) ? Theme.borderSubtle : "#22ffffff"

    // Click backdrop to close
    MouseArea {
        anchors.fill: parent
        onClicked: root.closeLauncher()
    }

    // Installed apps cached from daemon
    property var installedApps: []
    property int selectedAppIndex: 0
    property int selectedSuggestionIndex: 0
    property string queryText: ""
    property string activeMode: "" // "wallpaper", "scheme", "mode", "settings", or ""

    readonly property bool isCommandMode: queryText.startsWith(">")
    readonly property string commandName: {
        if (!isCommandMode) return "";
        const parts = queryText.slice(1).trim().split(" ");
        return parts[0].toLowerCase();
    }
    readonly property string commandArg: {
        if (!isCommandMode) return "";
        const parts = queryText.slice(1).trim().split(" ");
        return parts.length > 1 ? parts.slice(1).join(" ").toLowerCase() : "";
    }

    readonly property bool isWallpaperMode: activeMode === "wallpaper" || commandName === "wallpaper" || commandName === "wp"
    readonly property bool isSchemeMode: activeMode === "scheme" || commandName === "scheme" || commandName === "color"
    readonly property bool isModeMode: activeMode === "mode" || commandName === "mode" || commandName === "dark" || commandName === "light"
    readonly property bool isSettingsMode: activeMode === "settings" || commandName === "settings" || commandName === "set"
    readonly property bool hasActiveCommandPage: isWallpaperMode || isSchemeMode || isModeMode || isSettingsMode

    onIsWallpaperModeChanged: {
        if (isWallpaperMode && typeof WallpaperEngine !== "undefined" && WallpaperEngine.reloadWallpapers) {
            WallpaperEngine.reloadWallpapers();
        }
    }


    Connections {
        target: (typeof Config !== "undefined") ? Config : null
        function onCommandLauncherVisibleChanged() {
            if (Config && Config.commandLauncherVisible) {
                if (Config.commandLauncherMode === "wallpaper") {
                    root.queryText = ">wallpaper";
                    root.activeMode = "wallpaper";
                } else if (Config.commandLauncherMode === "scheme") {
                    root.queryText = ">scheme";
                    root.activeMode = "scheme";
                } else if (Config.commandLauncherMode === "settings") {
                    root.queryText = ">settings";
                    root.activeMode = "settings";
                } else {
                    root.queryText = "";
                    root.activeMode = "";
                }
                searchInput.forceActiveFocus();
            }
        }
        function onCommandLauncherModeChanged() {
            if (Config && Config.commandLauncherVisible) {
                if (Config.commandLauncherMode === "wallpaper") {
                    root.queryText = ">wallpaper";
                    root.activeMode = "wallpaper";
                }
            }
        }
    }

    // Filtered apps for App Search mode (Virtual Scroll optimized)
    readonly property var filteredApps: {
        if (isCommandMode) return [];
        const q = queryText.trim().toLowerCase();
        if (!q) return root.installedApps;

        const list = root.installedApps;
        const res = [];
        for (let i = 0; i < list.length; i++) {
            const app = list[i];
            const key = app._searchKey || ((app.name || "") + " " + (app.comment || "") + " " + (app.exec || "")).toLowerCase();
            if (key.indexOf(q) !== -1) {
                res.push(app);
            }
        }
        return res;
    }

    onSelectedAppIndexChanged: {
        if (appsList && appsList.visible && selectedAppIndex >= 0 && selectedAppIndex < filteredApps.length) {
            if (selectedAppIndex === 0) {
                appsList.positionViewAtIndex(0, ListView.Beginning);
            } else {
                appsList.positionViewAtIndex(selectedAppIndex, ListView.Contain);
            }
        }
    }

    onSelectedSuggestionIndexChanged: {
        if (suggestionsList && suggestionsList.visible && selectedSuggestionIndex >= 0 && selectedSuggestionIndex < filteredSuggestions.length) {
            suggestionsList.positionViewAtIndex(selectedSuggestionIndex, ListView.Contain);
        }
    }

    // Command suggestions (Frame 46)
    readonly property var commandSuggestions: [
        {
            id: "wallpaper",
            name: "Wallpaper",
            description: "Change the current wallpaper",
            icon: "wallpaper",
            aliases: ["wallpaper", "wp", "wallpapers", "background"]
        },
        {
            id: "scheme",
            name: "Color Scheme",
            description: "Switch Material 3 color presets",
            icon: "palette",
            aliases: ["scheme", "color", "colors", "theme"]
        },
        {
            id: "mode",
            name: "Dark / Light Mode",
            description: "Toggle system dark or light appearance",
            icon: "brightness_6",
            aliases: ["mode", "dark", "light", "appearance"]
        },
        {
            id: "settings",
            name: "System Settings",
            description: "Jump to system configuration pages",
            icon: "settings",
            aliases: ["settings", "set", "config", "preferences"]
        }
    ]

    readonly property var filteredSuggestions: {
        if (!isCommandMode) return [];
        const q = commandName;
        if (!q) return commandSuggestions;
        return commandSuggestions.filter(item => {
            if (item.id.indexOf(q) !== -1 || item.name.toLowerCase().indexOf(q) !== -1) return true;
            for (let i = 0; i < item.aliases.length; i++) {
                if (item.aliases[i].indexOf(q) !== -1) return true;
            }
            return false;
        });
    }

    onQueryTextChanged: {
        if (searchInput.text !== root.queryText) {
            searchInput.text = root.queryText;
        }
        selectedAppIndex = 0;
        selectedSuggestionIndex = 0;
        if (appsList && appsList.visible) {
            appsList.positionViewAtIndex(0, ListView.Beginning);
        }
        if (suggestionsList && suggestionsList.visible) {
            suggestionsList.positionViewAtIndex(0, ListView.Beginning);
        }
        if (!isCommandMode) {
            activeMode = "";
        }
    }

    // Modal Box docked flush at bottom with rounded top corners
    Rectangle {
        id: modalBox
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 0
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.isWallpaperMode ? 1200 : 640
        height: {
            if (root.isWallpaperMode) return 260;
            if (root.isCommandMode && !root.hasActiveCommandPage) {
                return Math.min(root.filteredSuggestions.length * 56 + 88, 280);
            }
            if (root.isSchemeMode) return 150;
            if (root.isModeMode) return 140;
            if (root.isSettingsMode) return 140;
            return Math.min(root.filteredApps.length * 48 + 88, 480);
        }
        radius: 28
        color: root.colSurface
        border.color: root.colBorderSubtle
        border.width: 1

        Behavior on width {
            NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
        }
        Behavior on height {
            NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
        }

        // Keep bottom edge flush against screen
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 28
            color: parent.color
        }

        // Catch clicks inside dialog
        MouseArea {
            anchors.fill: parent
            onClicked: {}
        }

        // Content Area rendered ABOVE the bottom search bar
        Item {
            id: contentArea
            anchors.top: parent.top
            anchors.topMargin: 16
            anchors.bottom: searchBar.top
            anchors.bottomMargin: 12
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.right: parent.right
            anchors.rightMargin: 16
            clip: !root.isWallpaperMode

            // 1. Wallpaper Carousel View (Frames 47 & 48)
            WallpaperCarousel {
                id: wallpaperCarousel
                visible: root.isWallpaperMode
                anchors.fill: parent
                testMode: root.testMode
                searchQuery: root.commandArg

                onWallpaperSelected: (path) => {

                    root.closeLauncher();
                }
                onCancelled: {
                    root.closeLauncher();
                }
            }

            // 2. Command Suggestions List (Frame 46)
            ListView {
                id: suggestionsList
                visible: root.isCommandMode && !root.hasActiveCommandPage
                anchors.fill: parent
                clip: true
                spacing: 6
                model: root.filteredSuggestions
                currentIndex: root.selectedSuggestionIndex
                highlightFollowsCurrentItem: true
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                    required property var modelData
                    required property int index

                    readonly property bool isSelected: root.selectedSuggestionIndex === index
                    width: suggestionsList.width
                    height: 52
                    radius: 14
                    color: isSelected ? root.colSurfaceContainerHigh : (suggHover.containsMouse ? root.colSurfaceContainer : "transparent")
                    border.color: isSelected ? root.colPrimary : "transparent"
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 14
                        spacing: 12

                        Rectangle {
                            width: 34
                            height: 34
                            radius: 10
                            color: isSelected ? root.colPrimary : root.colSurfaceContainer
                            MaterialIcon {
                                anchors.centerIn: parent
                                text: modelData.icon || "terminal"
                                size: 18
                                color: isSelected ? root.colOnPrimary : root.colPrimary
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Text {
                                Layout.fillWidth: true
                                text: modelData.name || ""
                                font.pixelSize: 13
                                font.weight: Font.DemiBold
                                color: root.colTextOnSurface
                                elide: Text.ElideRight
                            }

                            Text {
                                Layout.fillWidth: true
                                text: modelData.description || ""
                                font.pixelSize: 11
                                color: root.colTextMuted
                                elide: Text.ElideRight
                            }
                        }

                        Text {
                            text: "↵ Select"
                            font.pixelSize: 11
                            color: root.colTextMuted
                            visible: isSelected
                        }
                    }

                    MouseArea {
                        id: suggHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.selectedSuggestionIndex = index;
                            root.activateSuggestion(modelData);
                        }
                    }
                }
            }

            // 3. Preset Schemes Chooser (>scheme)
            ColumnLayout {
                visible: root.isSchemeMode
                anchors.fill: parent
                spacing: 8

                Text {
                    text: "Material 3 Expressive Color Presets:"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    color: root.colTextMuted
                }

                Row {
                    spacing: 10
                    readonly property var presets: [
                        { name: "Iris", key: "iris", col: "#cba6f7" },
                        { name: "Ocean", key: "ocean", col: "#89b4fa" },
                        { name: "Coral", key: "coral", col: "#fab387" },
                        { name: "Emerald", key: "emerald", col: "#a6e3a1" }
                    ]

                    Repeater {
                        model: parent.presets
                        delegate: Rectangle {
                            required property var modelData
                            height: 36
                            implicitWidth: pCol.implicitWidth + 24
                            radius: 18
                            color: pHover.containsMouse ? root.colSurfaceContainerHigh : root.colSurfaceContainer
                            border.color: (typeof Config !== "undefined" && Config.themePreset === modelData.key) ? modelData.col : root.colBorderSubtle
                            border.width: (typeof Config !== "undefined" && Config.themePreset === modelData.key) ? 2 : 1

                            Row {
                                id: pCol
                                anchors.centerIn: parent
                                spacing: 8
                                Rectangle {
                                    width: 14; height: 14; radius: 7
                                    color: modelData.col
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.name
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                    color: root.colTextOnSurface
                                }
                            }

                            MouseArea {
                                id: pHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (typeof Config !== "undefined") {
                                        Config.setThemePreset(modelData.key);
                                    }
                                    root.closeLauncher();
                                }
                            }
                        }
                    }
                }
            }

            // 4. Dark / Light Mode Chooser (>mode)
            Row {
                visible: root.isModeMode
                anchors.centerIn: parent
                spacing: 12

                Rectangle {
                    height: 40
                    implicitWidth: 120
                    radius: 20
                    color: darkHover.containsMouse ? root.colSurfaceContainerHigh : root.colSurfaceContainer
                    border.color: root.colPrimary
                    border.width: 1

                    Row {
                        anchors.centerIn: parent
                        spacing: 8
                        MaterialIcon { text: "dark_mode"; size: 18; color: root.colPrimary }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: "Dark Mode"; color: root.colTextOnSurface; font.pixelSize: 12 }
                    }
                    MouseArea {
                        id: darkHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (typeof Config !== "undefined") Config.setDarkMode(true);
                            root.closeLauncher();
                        }
                    }
                }

                Rectangle {
                    height: 40
                    implicitWidth: 120
                    radius: 20
                    color: lightHover.containsMouse ? root.colSurfaceContainerHigh : root.colSurfaceContainer
                    border.color: root.colBorderSubtle
                    border.width: 1

                    Row {
                        anchors.centerIn: parent
                        spacing: 8
                        MaterialIcon { text: "light_mode"; size: 18; color: root.colTextMuted }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: "Light Mode"; color: root.colTextOnSurface; font.pixelSize: 12 }
                    }
                    MouseArea {
                        id: lightHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (typeof Config !== "undefined") Config.setDarkMode(false);
                            root.closeLauncher();
                        }
                    }
                }
            }

            // 5. Settings Jump (>settings)
            Row {
                visible: root.isSettingsMode
                anchors.centerIn: parent
                spacing: 8
                readonly property var pages: [
                    { name: "Dock", key: "dock", icon: "dashboard" },
                    { name: "Status", key: "status", icon: "wifi" },
                    { name: "Theme", key: "theme", icon: "palette" },
                    { name: "System", key: "system", icon: "memory" }
                ]

                Repeater {
                    model: parent.pages
                    delegate: Rectangle {
                        required property var modelData
                        height: 36
                        implicitWidth: sRow.implicitWidth + 20
                        radius: 18
                        color: sHover.containsMouse ? root.colSurfaceContainerHigh : root.colSurfaceContainer
                        border.color: root.colBorderSubtle
                        border.width: 1

                        Row {
                            id: sRow
                            anchors.centerIn: parent
                            spacing: 6
                            MaterialIcon { text: modelData.icon; size: 16; color: root.colPrimary }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: modelData.name; font.pixelSize: 12; color: root.colTextOnSurface }
                        }

                        MouseArea {
                            id: sHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (typeof Config !== "undefined") Config.openSettings(modelData.key);
                                root.closeLauncher();
                            }
                        }
                    }
                }
            }

            // 6. App Results List (Frame 45) - High-Performance Virtual Scroll
            ListView {
                id: appsList
                visible: !root.isCommandMode
                anchors.fill: parent
                clip: true
                model: root.filteredApps
                spacing: 4
                currentIndex: root.selectedAppIndex
                highlightFollowsCurrentItem: true
                boundsBehavior: Flickable.StopAtBounds
                reuseItems: true
                cacheBuffer: 120
                pixelAligned: true
                highlightMoveDuration: 0

                delegate: Rectangle {
                    required property var modelData
                    required property int index

                    readonly property bool isSelected: root.selectedAppIndex === index
                    width: appsList.width
                    height: 48
                    radius: 12
                    color: isSelected ? root.colSurfaceContainerHigh : (appRowHover.containsMouse ? root.colSurfaceContainer : "transparent")
                    border.color: isSelected ? root.colPrimary : "transparent"
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 12

                        Item {
                            width: 28
                            height: 28
                            Layout.alignment: Qt.AlignVCenter

                            Image {
                                id: appIcon
                                anchors.fill: parent
                                source: {
                                    if (!modelData.icon) return "";
                                    if (modelData.icon.indexOf("/") !== -1) {
                                        return modelData.icon.startsWith("file://") ? modelData.icon : ("file://" + modelData.icon);
                                    }
                                    return Quickshell.iconPath(modelData.icon);
                                }
                                fillMode: Image.PreserveAspectFit
                                smooth: true
                                mipmap: true
                                asynchronous: true
                                sourceSize.width: 28
                                sourceSize.height: 28
                                cache: true
                                visible: status === Image.Ready
                            }

                            MaterialIcon {
                                anchors.centerIn: parent
                                text: "apps"
                                size: 22
                                color: isSelected ? root.colPrimary : root.colTextMuted
                                visible: !appIcon.visible || appIcon.status !== Image.Ready
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1

                            Text {
                                Layout.fillWidth: true
                                text: modelData.name || "Application"
                                font.pixelSize: 13
                                font.weight: Font.DemiBold
                                color: root.colTextOnSurface
                                elide: Text.ElideRight
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: !!modelData.comment
                                text: modelData.comment || ""
                                font.pixelSize: 11
                                color: root.colTextMuted
                                elide: Text.ElideRight
                            }
                        }

                        Text {
                            text: "↵ Launch"
                            font.pixelSize: 10
                            color: root.colTextMuted
                            visible: isSelected
                        }
                    }

                    MouseArea {
                        id: appRowHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.selectedAppIndex = index;
                            root.launchApp(modelData);
                        }
                    }
                }
            }

            // Minimalist M3 Scroll Indicator Pill for Virtual Scroll
            Rectangle {
                id: scrollIndicator
                anchors.right: parent.right
                anchors.rightMargin: 2
                width: 3
                radius: 1.5
                color: root.colPrimary
                visible: !root.isCommandMode && appsList.contentHeight > appsList.height
                opacity: (appsList.moving || appsList.flicking || root.selectedAppIndex > 0) ? 0.7 : 0.2
                y: appsList.visibleArea.yPosition * appsList.height
                height: Math.max(24, appsList.visibleArea.heightRatio * appsList.height)

                Behavior on opacity {
                    NumberAnimation { duration: 200 }
                }
            }
        }

        // Search Input Pill Row docked at the BOTTOM of the modal
        Rectangle {
            id: searchBar
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 16
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.right: parent.right
            anchors.rightMargin: 16
            height: 48
            radius: 24
            color: root.colSurfaceContainer
            border.color: searchInput.activeFocus ? root.colPrimary : "transparent"
            border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 12
                spacing: 12

                MaterialIcon {
                    text: "search"
                    size: 18
                    color: root.colTextMuted
                }

                TextInput {
                    id: searchInput
                    Layout.fillWidth: true
                    font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                    font.pixelSize: 15
                    color: root.colTextOnSurface
                    selectByMouse: true
                    clip: true
                    text: root.queryText
                    onTextEdited: {
                        root.queryText = text;
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !searchInput.text && !searchInput.inputMethodComposing
                        text: "Search apps or type > for commands..."
                        font: searchInput.font
                        color: root.colTextMuted
                    }

                    Keys.onPressed: (event) => {
                        if (event.key === Qt.Key_Escape) {
                            if (root.isWallpaperMode) {
                                root.exitWallpaperMode();
                            }
                            root.closeLauncher();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Left) {
                            if (root.isWallpaperMode) {
                                wallpaperCarousel.selectPrevious();
                                event.accepted = true;
                            }
                        } else if (event.key === Qt.Key_Right) {
                            if (root.isWallpaperMode) {
                                wallpaperCarousel.selectNext();
                                event.accepted = true;
                            }
                        } else if (event.key === Qt.Key_Down) {
                            if (root.isWallpaperMode) {
                                event.accepted = true;
                            } else {
                                root.selectNext();
                                event.accepted = true;
                            }
                        } else if (event.key === Qt.Key_Up) {
                            if (root.isWallpaperMode) {
                                event.accepted = true;
                            } else {
                                root.selectPrevious();
                                event.accepted = true;
                            }
                        } else if (event.key === Qt.Key_PageDown) {
                            root.selectPageDown(6);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_PageUp) {
                            root.selectPageUp(6);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            root.executeCurrent();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Tab) {
                            if (root.isCommandMode && !root.hasActiveCommandPage && root.filteredSuggestions.length > 0) {
                                root.activateSuggestion(root.filteredSuggestions[root.selectedSuggestionIndex]);
                                event.accepted = true;
                            }
                        }
                    }
                }

                // Clear button
                Rectangle {
                    visible: searchInput.text.length > 0
                    width: 28
                    height: 28
                    radius: 14
                    color: clearHover.containsMouse ? root.colSurfaceContainerHigh : "transparent"

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: "close"
                        size: 16
                        color: root.colTextMuted
                    }

                    MouseArea {
                        id: clearHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (root.isWallpaperMode) {
                                root.exitWallpaperMode();
                            } else {
                                searchInput.text = "";
                                searchInput.forceActiveFocus();
                            }
                        }
                    }
                }
            }
        }
    }

    function activateSuggestion(item) {
        if (!item) return;
        if (item.id === "wallpaper") {
            root.queryText = ">wallpaper";
            root.activeMode = "wallpaper";
        } else if (item.id === "scheme") {
            root.activeMode = "scheme";
        } else if (item.id === "mode") {
            root.activeMode = "mode";
        } else if (item.id === "settings") {
            root.activeMode = "settings";
        }
    }

    function exitWallpaperMode() {
        root.activeMode = "";
        if (!root.testMode && typeof WallpaperEngine !== "undefined" && WallpaperEngine.stopPreview) {
            WallpaperEngine.stopPreview();
        }
    }

    function selectNext() {
        if (!root.isCommandMode && root.filteredApps.length > 0) {
            root.selectedAppIndex = Math.min(root.filteredApps.length - 1, root.selectedAppIndex + 1);
        } else if (root.isCommandMode && !root.hasActiveCommandPage && root.filteredSuggestions.length > 0) {
            root.selectedSuggestionIndex = Math.min(root.filteredSuggestions.length - 1, root.selectedSuggestionIndex + 1);
        }
    }

    function selectPrevious() {
        if (!root.isCommandMode && root.filteredApps.length > 0) {
            root.selectedAppIndex = Math.max(0, root.selectedAppIndex - 1);
        } else if (root.isCommandMode && !root.hasActiveCommandPage && root.filteredSuggestions.length > 0) {
            root.selectedSuggestionIndex = Math.max(0, root.selectedSuggestionIndex - 1);
        }
    }

    function selectPageDown(count) {
        const step = count || 6;
        if (!root.isCommandMode && root.filteredApps.length > 0) {
            root.selectedAppIndex = Math.min(root.filteredApps.length - 1, root.selectedAppIndex + step);
        }
    }

    function selectPageUp(count) {
        const step = count || 6;
        if (!root.isCommandMode && root.filteredApps.length > 0) {
            root.selectedAppIndex = Math.max(0, root.selectedAppIndex - step);
        }
    }

    function selectIndex(idx) {
        if (!root.isCommandMode && root.filteredApps.length > 0) {
            root.selectedAppIndex = Math.max(0, Math.min(root.filteredApps.length - 1, idx));
        }
    }

    function executeCurrent() {
        if (root.isWallpaperMode) {
            wallpaperCarousel.applyCurrent();
            root.closeLauncher();
        } else if (root.isCommandMode && !root.hasActiveCommandPage) {
            if (root.filteredSuggestions.length > 0 && root.selectedSuggestionIndex < root.filteredSuggestions.length) {
                root.activateSuggestion(root.filteredSuggestions[root.selectedSuggestionIndex]);
            }
        } else if (root.isSchemeMode) {
            const p = root.commandArg || "iris";
            if (typeof Config !== "undefined") Config.setThemePreset(p);
            root.closeLauncher();
        } else if (root.isModeMode) {
            const m = root.commandArg.includes("light") ? false : true;
            if (typeof Config !== "undefined") Config.setDarkMode(m);
            root.closeLauncher();
        } else if (root.isSettingsMode) {
            const page = root.commandArg || "dock";
            if (typeof Config !== "undefined") Config.openSettings(page);
            root.closeLauncher();
        } else if (root.filteredApps.length > 0 && root.selectedAppIndex < root.filteredApps.length) {
            root.launchApp(root.filteredApps[root.selectedAppIndex]);
        }
    }

    function launchApp(app) {
        if (!app) return;
        if (!root.testMode && typeof WindowService !== "undefined" && WindowService.launchApp) {
            WindowService.launchApp(app.desktop_file || app.exec || app.name);
        }
        root.closeLauncher();
    }

    function openLauncher(mode) {
        if (mode === "wallpaper") {
            root.queryText = ">wallpaper";
            root.activeMode = "wallpaper";
            searchInput.text = ">wallpaper";
            if (typeof WallpaperEngine !== "undefined" && WallpaperEngine.reloadWallpapers) {
                WallpaperEngine.reloadWallpapers();
            }
        } else if (mode === "scheme") {

            root.queryText = ">scheme";
            root.activeMode = "scheme";
            searchInput.text = ">scheme";
        } else if (mode === "settings") {
            root.queryText = ">settings";
            root.activeMode = "settings";
            searchInput.text = ">settings";
        } else {
            root.queryText = "";
            root.activeMode = "";
            searchInput.text = "";
        }
        root.selectedAppIndex = 0;
        root.selectedSuggestionIndex = 0;
        if (typeof Config !== "undefined") {
            Config.commandLauncherMode = mode || "apps";
            Config.commandLauncherVisible = true;
        }
        searchInput.forceActiveFocus();
        if (appsList) {
            appsList.positionViewAtIndex(0, ListView.Beginning);
        }
    }

    function closeLauncher() {
        if (root.isWallpaperMode) {
            root.exitWallpaperMode();
        }
        if (typeof Config !== "undefined") {
            Config.commandLauncherVisible = false;
        }
        root.queryText = "";
        root.activeMode = "";
    }

    // Process to query installed apps on completion (with pre-computed search keys for virtual scroll)
    Process {
        id: appsProc
        command: [(typeof Config !== "undefined" && Config.daemonBin) ? Config.daemonBin : "./bin/astral-plasma", "apps"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(this.text.trim());
                    if (Array.isArray(parsed)) {
                        for (let i = 0; i < parsed.length; i++) {
                            const a = parsed[i];
                            a._searchKey = ((a.name || "") + " " + (a.comment || "") + " " + (a.exec || "")).toLowerCase();
                        }
                        root.installedApps = parsed;
                    }
                } catch (e) {}
            }
        }
    }

    function syncWithConfig() {
        if (typeof Config !== "undefined" && Config.commandLauncherVisible) {
            if (Config.commandLauncherMode === "wallpaper") {
                root.openLauncher("wallpaper");
            } else if (Config.commandLauncherMode === "scheme") {
                root.openLauncher("scheme");
            } else if (Config.commandLauncherMode === "settings") {
                root.openLauncher("settings");
            }
        }
    }

    Component.onCompleted: {
        syncWithConfig();
        if (!root.testMode && appsProc.command) {
            appsProc.running = true;
        }
    }

    onActiveVisibleChanged: {
        if (activeVisible) {
            syncWithConfig();
            searchInput.forceActiveFocus();
            if (root.installedApps.length === 0 && !root.testMode) {
                appsProc.running = true;
            }
        }
    }
}
