import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../components"
import "../../services"

Item {
    id: root

    implicitWidth: 680
    implicitHeight: {
        if (root.searchQuery.trim().length > 0) {
            return Math.min(480, Math.max(260, 52 + root.filteredWindows.length * 58 + 48));
        }
        const cols = (typeof stageGrid !== "undefined" && stageGrid && stageGrid.columns) ? stageGrid.columns : 2;
        const count = Math.max(1, root.totalDesktopsCount);
        const rows = Math.ceil(count / Math.max(1, cols));
        if (rows <= 1) return 240;
        if (rows === 2) return 360;
        return Math.min(480, 240 + (rows - 1) * 124);
    }

    readonly property bool usesLiquidGlassCards: true

    property string searchQuery: ""
    readonly property bool searchActive: Boolean(searchBox && searchBox.activeFocus)

    // Shield: consume clicks within WorkspacesTab to prevent fall-through to backdrop scrim
    MouseArea {
        anchors.fill: parent
        onClicked: mouse.accepted = true
    }

    // Helper: list of windows belonging to a specific virtual desktop
    function getWindowsForDesktop(desktopId) {
        if (!desktopId || typeof WindowService === "undefined" || !WindowService.windows || !Array.isArray(WindowService.windows)) {
            return [];
        }
        const wins = WindowService.windows;
        const res = [];
        for (let i = 0; i < wins.length; i++) {
            const w = wins[i];
            if (!w) continue;
            if (w.onAllDesktops) {
                res.push(w);
                continue;
            }
            if (w.desktopIds && Array.isArray(w.desktopIds)) {
                if (w.desktopIds.indexOf(desktopId) !== -1) {
                    res.push(w);
                    continue;
                }
            } else if (typeof KWinWorkspaces !== "undefined" && KWinWorkspaces.currentId === desktopId && (!w.desktopIds || w.desktopIds.length === 0)) {
                // Fallback for untagged windows on current desktop
                res.push(w);
            }
        }
        return res;
    }

    // Helper: desktop label for a window
    function getDesktopNameForWindow(win) {
        if (!win) return "";
        if (win.onAllDesktops) return "All Desktops";
        if (typeof KWinWorkspaces !== "undefined" && KWinWorkspaces.desktops && win.desktopIds && win.desktopIds.length > 0) {
            for (let i = 0; i < KWinWorkspaces.desktops.length; i++) {
                const d = KWinWorkspaces.desktops[i];
                if (d && win.desktopIds.indexOf(d.id) !== -1) {
                    return d.name || ("Desktop " + (d.index + 1));
                }
            }
        }
        return "Current";
    }

    // Helper: focus a window and switch to its desktop
    function focusWindow(win) {
        if (!win) return;
        if (typeof WindowService !== "undefined") {
            WindowService.activateWindow(win.id);
        }
        if (win.desktopIds && win.desktopIds.length > 0 && typeof KWinWorkspaces !== "undefined") {
            KWinWorkspaces.switchTo(win.desktopIds[0]);
        }
    }

    readonly property var filteredWindows: {
        const q = root.searchQuery.trim().toLowerCase();
        if (q.length === 0 || typeof WindowService === "undefined" || !WindowService.windows || !Array.isArray(WindowService.windows)) {
            return [];
        }
        return WindowService.windows.filter(w => {
            if (!w) return false;
            const title = (w.title || "").toLowerCase();
            const app = (w.appName || w.appId || "").toLowerCase();
            return title.indexOf(q) !== -1 || app.indexOf(q) !== -1;
        });
    }

    readonly property int totalWindowsCount: (typeof WindowService !== "undefined" && WindowService.windows && Array.isArray(WindowService.windows)) ? WindowService.windows.length : 0
    readonly property int totalDesktopsCount: (typeof KWinWorkspaces !== "undefined" && KWinWorkspaces.desktops && Array.isArray(KWinWorkspaces.desktops)) ? KWinWorkspaces.desktops.length : 0

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: (typeof Theme !== "undefined" && Theme.padLarge) ? Theme.padLarge : 16
        spacing: (typeof Theme !== "undefined" && Theme.spaceMedium) ? Theme.spaceMedium : 12

        // ==========================================
        // Top Toolbar: Title, Telemetry & Operations
        // ==========================================
        RowLayout {
            Layout.fillWidth: true
            spacing: (typeof Theme !== "undefined" && Theme.spaceMedium) ? Theme.spaceMedium : 10

            Row {
                Layout.alignment: Qt.AlignVCenter
                spacing: (typeof Theme !== "undefined" && Theme.spaceSmall) ? Theme.spaceSmall : 8

                MaterialIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "workspaces"
                    size: 20
                    color: (typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#9bcbfb"
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Workspaces & Stage"
                    font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                    font.pixelSize: (typeof Theme !== "undefined" && Theme.fontTitleMedium) ? Theme.fontTitleMedium : 16
                    font.weight: Font.DemiBold
                    color: (typeof Colors !== "undefined" && Colors.m3onSurface) ? Colors.m3onSurface : "#FFFFFF"
                }

                // Counter pill
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    height: 22
                    width: counterText.implicitWidth + 14
                    radius: 11
                    color: (typeof Colors !== "undefined" && Colors.m3surfaceVariant) ? Qt.alpha(Colors.m3surfaceVariant, 0.45) : Qt.rgba(1, 1, 1, 0.08)
                    border.width: 1
                    border.color: (typeof Colors !== "undefined" && Colors.glassBorderSubtle) ? Colors.glassBorderSubtle : Qt.rgba(1, 1, 1, 0.12)

                    Text {
                        id: counterText
                        anchors.centerIn: parent
                        text: root.totalDesktopsCount + " Desktops • " + root.totalWindowsCount + " Windows"
                        font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                        font.pixelSize: (typeof Theme !== "undefined" && Theme.fontLabelSmall) ? Theme.fontLabelSmall : 11
                        font.weight: Font.Medium
                        color: (typeof Colors !== "undefined" && Colors.m3onSurfaceVariant) ? Colors.m3onSurfaceVariant : "#c4c7c5"
                    }
                }
            }

            Item { Layout.fillWidth: true }

            // Search Bar
            LiquidGlassCard {
                implicitWidth: Math.min(190, Math.max(130, root.width * 0.24))
                implicitHeight: 32
                radius: 16
                elevation: 2
                interactive: true
                showSpecular: false

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 6

                    MaterialIcon {
                        text: "search"
                        size: 15
                        color: (typeof Colors !== "undefined" && Colors.m3onSurfaceVariant) ? Colors.m3onSurfaceVariant : "#c4c7c5"
                    }

                    TextInput {
                        id: searchBox
                        Layout.fillWidth: true
                        font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                        font.pixelSize: (typeof Theme !== "undefined" && Theme.fontBodySmall) ? Theme.fontBodySmall : 12
                        color: (typeof Colors !== "undefined" && Colors.m3onSurface) ? Colors.m3onSurface : "#FFFFFF"
                        clip: true
                        verticalAlignment: TextInput.AlignVCenter
                        onTextChanged: root.searchQuery = text

                        Keys.onEscapePressed: {
                            text = "";
                            root.searchQuery = "";
                        }
                        Keys.onReturnPressed: {
                            if (root.filteredWindows.length > 0) {
                                root.focusWindow(root.filteredWindows[0]);
                            }
                        }

                        Text {
                            anchors.fill: parent
                            verticalAlignment: Text.AlignVCenter
                            visible: !searchBox.text && !searchBox.activeFocus
                            text: "Find window..."
                            font.family: searchBox.font.family
                            font.pixelSize: searchBox.font.pixelSize
                            color: (typeof Colors !== "undefined" && Colors.m3outline) ? Colors.m3outline : Qt.rgba(1, 1, 1, 0.4)
                        }
                    }

                    // Clear button
                    MaterialIcon {
                        visible: searchBox.text.length > 0
                        text: "close"
                        size: 14
                        color: (typeof Colors !== "undefined" && Colors.m3onSurfaceVariant) ? Colors.m3onSurfaceVariant : "#c4c7c5"

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                searchBox.text = "";
                                root.searchQuery = "";
                            }
                        }
                    }
                }
            }

            // Overview Compositor Chip
            LiquidGlassCard {
                implicitWidth: 88
                implicitHeight: 32
                radius: 16
                elevation: 3
                interactive: true
                hovered: ovMouse.containsMouse

                Row {
                    anchors.centerIn: parent
                    spacing: 4

                    MaterialIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "grid_view"
                        size: 15
                        color: (typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#9bcbfb"
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Overview"
                        font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                        font.pixelSize: (typeof Theme !== "undefined" && Theme.fontLabelSmall) ? Theme.fontLabelSmall : 11
                        font.weight: Font.Medium
                        color: (typeof Colors !== "undefined" && Colors.m3onSurface) ? Colors.m3onSurface : "#FFFFFF"
                    }
                }

                MouseArea {
                    id: ovMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (typeof KWinWorkspaces !== "undefined") {
                            KWinWorkspaces.toggleOverview();
                        }
                    }
                }
            }

            // Add Virtual Desktop Chip
            LiquidGlassCard {
                implicitWidth: 32
                implicitHeight: 32
                radius: 16
                elevation: 3
                interactive: true
                hovered: addMouse.containsMouse

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "add"
                    size: 18
                    color: (typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#9bcbfb"
                }

                MouseArea {
                    id: addMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (typeof KWinWorkspaces !== "undefined") {
                            KWinWorkspaces.createDesktop();
                        }
                    }
                }
            }
        }

        // ==========================================
        // Stage View: Search Results vs Spatial Stage
        // ==========================================
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            // ------------------------------------------
            // 1. Search Results Mode (Active Query)
            // ------------------------------------------
            ListView {
                id: searchListView
                anchors.fill: parent
                visible: root.searchQuery.trim().length > 0
                clip: true
                spacing: 6
                model: root.filteredWindows

                delegate: LiquidGlassCard {
                    width: searchListView.width
                    height: 52
                    radius: (typeof Theme !== "undefined" && Theme.radiusMedium) ? Theme.radiusMedium : 10
                    interactive: true
                    hovered: itemMouse.containsMouse
                    elevation: itemMouse.containsMouse ? 6 : 2

                    MouseArea {
                        id: itemMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.focusWindow(modelData)
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 10

                        MaterialIcon {
                            text: modelData.materialIcon || "desktop_windows"
                            size: 20
                            color: (typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#9bcbfb"
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1

                            Text {
                                Layout.fillWidth: true
                                text: modelData.title || modelData.appName || "Window"
                                font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                                font.pixelSize: (typeof Theme !== "undefined" && Theme.fontBodyMedium) ? Theme.fontBodyMedium : 13
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                                color: (typeof Colors !== "undefined" && Colors.m3onSurface) ? Colors.m3onSurface : "#FFFFFF"
                            }

                            Text {
                                text: (modelData.appName || "App") + (modelData.isMaximized ? " • Maximized" : "")
                                font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                                font.pixelSize: (typeof Theme !== "undefined" && Theme.fontLabelSmall) ? Theme.fontLabelSmall : 11
                                color: (typeof Colors !== "undefined" && Colors.m3onSurfaceVariant) ? Colors.m3onSurfaceVariant : "#c4c7c5"
                            }
                        }

                        // Desktop tag
                        Rectangle {
                            height: 22
                            width: wsTagText.implicitWidth + 12
                            radius: 11
                            color: (typeof Colors !== "undefined" && Colors.primary) ? Qt.alpha(Colors.primary, 0.15) : Qt.rgba(1, 1, 1, 0.1)
                            border.width: 1
                            border.color: (typeof Colors !== "undefined" && Colors.primary) ? Qt.alpha(Colors.primary, 0.35) : Qt.rgba(1, 1, 1, 0.2)

                            Text {
                                id: wsTagText
                                anchors.centerIn: parent
                                text: root.getDesktopNameForWindow(modelData)
                                font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                                font.pixelSize: 11
                                font.weight: Font.Medium
                                color: (typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#9bcbfb"
                            }
                        }

                        // Focus Jump Button
                        Rectangle {
                            height: 26
                            width: 58
                            radius: 13
                            color: (typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#9bcbfb"

                            Text {
                                anchors.centerIn: parent
                                text: "Focus"
                                font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                                font.pixelSize: 11
                                font.weight: Font.Bold
                                color: (typeof Colors !== "undefined" && Colors.m3onPrimary) ? Colors.m3onPrimary : "#00325b"
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.focusWindow(modelData)
                            }
                        }

                        // Close button
                        Rectangle {
                            height: 26
                            width: 26
                            radius: 13
                            color: closeMouse.containsMouse ? Qt.rgba(1, 0.3, 0.3, 0.35) : Qt.rgba(1, 1, 1, 0.08)

                            MaterialIcon {
                                anchors.centerIn: parent
                                text: "close"
                                size: 14
                                color: closeMouse.containsMouse ? "#ff6b6b" : ((typeof Colors !== "undefined" && Colors.m3onSurfaceVariant) ? Colors.m3onSurfaceVariant : "#c4c7c5")
                            }

                            MouseArea {
                                id: closeMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (typeof WindowService !== "undefined") {
                                        WindowService.closeWindow(modelData.id);
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Search Empty State
            Text {
                anchors.centerIn: parent
                visible: root.searchQuery.trim().length > 0 && root.filteredWindows.length === 0
                text: "No windows matching \"" + root.searchQuery + "\""
                font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                font.pixelSize: (typeof Theme !== "undefined" && Theme.fontBodyMedium) ? Theme.fontBodyMedium : 13
                color: (typeof Colors !== "undefined" && Colors.m3outline) ? Colors.m3outline : Qt.rgba(1, 1, 1, 0.4)
            }

            // ------------------------------------------
            // 2. Spatial Stage Mode (Grid of Desktops)
            // ------------------------------------------
            Flickable {
                id: stageFlickable
                anchors.fill: parent
                visible: root.searchQuery.trim().length === 0
                contentWidth: width
                contentHeight: stageGrid.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                GridLayout {
                    id: stageGrid
                    width: parent.width
                    columns: {
                        const count = root.totalDesktopsCount;
                        if (parent.width >= 720) {
                            return count <= 3 ? count : (count === 4 ? 2 : 3);
                        } else if (parent.width >= 460) {
                            return 2;
                        }
                        return 1;
                    }
                    columnSpacing: 10
                    rowSpacing: 10

                    Repeater {
                        model: (typeof KWinWorkspaces !== "undefined" && KWinWorkspaces.desktops) ? KWinWorkspaces.desktops : []

                        delegate: LiquidGlassCard {
                            id: desktopCard
                            Layout.fillWidth: true
                            implicitHeight: 114
                            radius: (typeof Theme !== "undefined" && Theme.radiusLarge) ? Theme.radiusLarge : 14
                            interactive: true
                            selected: Boolean(modelData.active)
                            hovered: wsCardMouse.containsMouse
                            elevation: modelData.active ? 8 : 4

                            readonly property var winsOnDesktop: root.getWindowsForDesktop(modelData.id)
                            readonly property int maxVisibleChips: desktopCard.width < 340 ? 2 : (desktopCard.width < 500 ? 3 : 4)
                            readonly property real maxChipWidth: desktopCard.width < 340 ? 104 : 126
                            readonly property real maxLabelWidth: desktopCard.width < 340 ? 60 : 80

                            // Card click-to-switch mouse area (sits directly on card background, under child buttons)
                            MouseArea {
                                id: wsCardMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (typeof KWinWorkspaces !== "undefined") {
                                        KWinWorkspaces.switchTo(modelData.id);
                                    }
                                }
                            }

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 6

                                // Card Header
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    MaterialIcon {
                                        text: modelData.active ? "radio_button_checked" : "radio_button_unchecked"
                                        size: 15
                                        color: modelData.active 
                                            ? ((typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#9bcbfb")
                                            : ((typeof Colors !== "undefined" && Colors.m3onSurfaceVariant) ? Colors.m3onSurfaceVariant : "#c4c7c5")
                                    }

                                    Text {
                                        text: modelData.name || ("Desktop " + (modelData.index + 1))
                                        font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                                        font.pixelSize: (typeof Theme !== "undefined" && Theme.fontBodyMedium) ? Theme.fontBodyMedium : 13
                                        font.weight: modelData.active ? Font.Bold : Font.DemiBold
                                        color: (typeof Colors !== "undefined" && Colors.m3onSurface) ? Colors.m3onSurface : "#FFFFFF"
                                        elide: Text.ElideRight
                                        Layout.maximumWidth: desktopCard.width < 340 ? 85 : 150
                                    }

                                    // Active Badge
                                    Rectangle {
                                        visible: Boolean(modelData.active)
                                        height: 18
                                        width: activeBadgeText.implicitWidth + 10
                                        radius: 9
                                        color: (typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#9bcbfb"

                                        Text {
                                            id: activeBadgeText
                                            anchors.centerIn: parent
                                            text: "Active"
                                            font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                                            font.pixelSize: 10
                                            font.weight: Font.Bold
                                            color: (typeof Colors !== "undefined" && Colors.m3onPrimary) ? Colors.m3onPrimary : "#00325b"
                                        }
                                    }

                                    Item { Layout.fillWidth: true }

                                    // Window count indicator
                                    Rectangle {
                                        height: 18
                                        width: countBadgeText.implicitWidth + 10
                                        radius: 9
                                        color: Qt.rgba(1, 1, 1, 0.08)

                                        Text {
                                            id: countBadgeText
                                            anchors.centerIn: parent
                                            text: desktopCard.winsOnDesktop.length === 0 ? "Empty" : (desktopCard.winsOnDesktop.length + (desktopCard.winsOnDesktop.length === 1 ? " win" : " wins"))
                                            font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                                            font.pixelSize: 10
                                            font.weight: Font.Medium
                                            color: (typeof Colors !== "undefined" && Colors.m3onSurfaceVariant) ? Colors.m3onSurfaceVariant : "#c4c7c5"
                                        }
                                    }

                                    // Delete empty desktop button
                                    Rectangle {
                                        visible: !modelData.active && desktopCard.winsOnDesktop.length === 0 && root.totalDesktopsCount > 1
                                        height: 18
                                        width: 18
                                        radius: 9
                                        color: delWsMouse.containsMouse ? Qt.rgba(1, 0.3, 0.3, 0.35) : "transparent"

                                        MaterialIcon {
                                            anchors.centerIn: parent
                                            text: "close"
                                            size: 12
                                            color: delWsMouse.containsMouse ? "#ff6b6b" : ((typeof Colors !== "undefined" && Colors.m3onSurfaceVariant) ? Colors.m3onSurfaceVariant : "#c4c7c5")
                                        }

                                        MouseArea {
                                            id: delWsMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (typeof KWinWorkspaces !== "undefined") {
                                                    KWinWorkspaces.removeDesktop(modelData.id);
                                                }
                                            }
                                        }
                                    }
                                }

                                // Card Body: Window Chips Stage
                                Item {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    clip: true

                                    // Empty stage state
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.left: parent.left
                                        visible: desktopCard.winsOnDesktop.length === 0
                                        text: "No open windows on this stage"
                                        font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                                        font.pixelSize: 11
                                        font.italic: true
                                        elide: Text.ElideRight
                                        width: parent.width
                                        color: (typeof Colors !== "undefined" && Colors.m3outline) ? Colors.m3outline : Qt.rgba(1, 1, 1, 0.35)
                                    }

                                    // Flow of window chips
                                    Row {
                                        anchors.fill: parent
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 6
                                        visible: desktopCard.winsOnDesktop.length > 0

                                        Repeater {
                                            model: desktopCard.winsOnDesktop.slice(0, desktopCard.maxVisibleChips)

                                            delegate: Rectangle {
                                                height: 28
                                                width: Math.min(desktopCard.maxChipWidth, chipRow.implicitWidth + 14)
                                                radius: 14
                                                color: chipMouse.containsMouse 
                                                    ? Qt.rgba(1, 1, 1, 0.16) 
                                                    : (modelData.isActive ? Qt.alpha(Colors.primary, 0.22) : Qt.rgba(1, 1, 1, 0.08))
                                                border.width: 1
                                                border.color: modelData.isActive 
                                                    ? ((typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#9bcbfb")
                                                    : Qt.rgba(1, 1, 1, 0.15)

                                                Row {
                                                    id: chipRow
                                                    anchors.centerIn: parent
                                                    spacing: 4

                                                    MaterialIcon {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        text: modelData.materialIcon || "desktop_windows"
                                                        size: 14
                                                        color: modelData.isActive 
                                                            ? ((typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#9bcbfb")
                                                            : ((typeof Colors !== "undefined" && Colors.m3onSurface) ? Colors.m3onSurface : "#FFFFFF")
                                                    }

                                                    Text {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        text: modelData.appName || modelData.title || "Window"
                                                        font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                                                        font.pixelSize: 11
                                                        font.weight: modelData.isActive ? Font.Bold : Font.Normal
                                                        elide: Text.ElideRight
                                                        width: Math.min(desktopCard.maxLabelWidth, implicitWidth)
                                                        color: (typeof Colors !== "undefined" && Colors.m3onSurface) ? Colors.m3onSurface : "#FFFFFF"
                                                    }
                                                }

                                                MouseArea {
                                                    id: chipMouse
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        root.focusWindow(modelData);
                                                    }
                                                }
                                            }
                                        }

                                        // More windows overflow badge
                                        Rectangle {
                                            visible: desktopCard.winsOnDesktop.length > desktopCard.maxVisibleChips
                                            height: 28
                                            width: overflowText.implicitWidth + 12
                                            radius: 14
                                            color: overflowMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.08)
                                            border.width: 1
                                            border.color: Qt.rgba(1, 1, 1, 0.12)

                                            Text {
                                                id: overflowText
                                                anchors.centerIn: parent
                                                text: "+" + (desktopCard.winsOnDesktop.length - desktopCard.maxVisibleChips)
                                                font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                                                font.pixelSize: 11
                                                font.weight: Font.Bold
                                                color: (typeof Colors !== "undefined" && Colors.m3onSurfaceVariant) ? Colors.m3onSurfaceVariant : "#c4c7c5"
                                            }

                                            MouseArea {
                                                id: overflowMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    if (typeof KWinWorkspaces !== "undefined") {
                                                        KWinWorkspaces.switchTo(modelData.id);
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                // Card Footer: Actions
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 4

                                    // For inactive desktop: "Move active window here"
                                    Rectangle {
                                        visible: !modelData.active && typeof WindowService !== "undefined" && Boolean(WindowService.activeId)
                                        height: 22
                                        width: moveBtnRow.implicitWidth + 12
                                        radius: 11
                                        color: moveMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.08)
                                        border.width: 1
                                        border.color: Qt.rgba(1, 1, 1, 0.12)

                                        Row {
                                            id: moveBtnRow
                                            anchors.centerIn: parent
                                            spacing: 4

                                            MaterialIcon {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: "south_west"
                                                size: 12
                                                color: (typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#9bcbfb"
                                            }

                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: "Move active here"
                                                font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                                                font.pixelSize: 10
                                                font.weight: Font.Medium
                                                color: (typeof Colors !== "undefined" && Colors.m3onSurfaceVariant) ? Colors.m3onSurfaceVariant : "#c4c7c5"
                                            }
                                        }

                                        MouseArea {
                                            id: moveMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (typeof KWinWorkspaces !== "undefined" && typeof WindowService !== "undefined") {
                                                    KWinWorkspaces.moveWindow(WindowService.activeId, modelData.id);
                                                }
                                            }
                                        }
                                    }

                                    // For active desktop: "Current stage"
                                    Text {
                                        visible: Boolean(modelData.active)
                                        text: "Current Workspace"
                                        font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                                        font.pixelSize: 10
                                        font.weight: Font.Medium
                                        color: (typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#9bcbfb"
                                    }

                                    Item { Layout.fillWidth: true }

                                    Text {
                                        text: "Click to switch"
                                        font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                                        font.pixelSize: 10
                                        color: wsCardMouse.containsMouse 
                                            ? ((typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#9bcbfb")
                                            : Qt.alpha(Colors.m3onSurfaceVariant, 0.5)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Glass Scrollbar indicator
            Rectangle {
                anchors.right: parent.right
                anchors.rightMargin: 1
                y: stageFlickable.visibleArea.yPosition * stageFlickable.height
                width: 3
                height: Math.max(20, stageFlickable.visibleArea.heightRatio * stageFlickable.height)
                radius: 1.5
                color: (typeof Colors !== "undefined" && Colors.primary) ? Qt.alpha(Colors.primary, 0.5) : Qt.rgba(1, 1, 1, 0.3)
                visible: stageFlickable.visible && stageFlickable.visibleArea.heightRatio < 0.99
            }
        }
    }

    Component.onCompleted: {
        if (typeof KWinWorkspaces !== "undefined" && typeof KWinWorkspaces.refresh === "function") {
            KWinWorkspaces.refresh();
        }
    }
}
