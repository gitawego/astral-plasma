pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import qs.theme
import qs.config
import qs.components
import qs.services
import "../services"
import qs.dock
import qs.dock.components
import qs.dock.popouts
import qs.dashboard.tabs

PanelWindow {
    id: root

    required property ShellScreen targetScreen
    screen: targetScreen

    WlrLayershell.namespace: "caelestia-shell"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.exclusionMode: ExclusionMode.Ignore

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    color: "transparent"

    readonly property int dockW: Config.dockWidth
    readonly property int iconS: Config.dockIconSize
    readonly property int borderT: Config.borderThickness
    readonly property int filletR: Config.borderRounding
    readonly property int dropW: Config.dashboardWidth
    readonly property int dropX: Math.round((root.width - dropW) / 2)
    readonly property int dropH: Math.round(dashCard.implicitHeight)

    Component.onCompleted: {
        console.log("DEBUG_BORDER_SUBTLE:", Theme.borderSubtle, "DEBUG_OUTLINE:", Colors.outline);
        const testMode = Quickshell.env("TEST_POPOUT");
        if (testMode === "default" || testMode === "bluetooth" || testMode === "network" || testMode === "power") {
            Config.bottomPopoutMode = testMode;
            Config.bottomPopoutVisible = true;
        }
        if (Quickshell.env("TEST_DASHBOARD") === "1") {
            Config.dashboardVisible = true;
        }
    }

    // Auto-close grace timer when leaving the dropdown
    Timer {
        id: closeTimer
        interval: 500
        repeat: false
        onTriggered: {
            if (Quickshell.env("TEST_DASHBOARD") === "1") return;
            if (!dropdownHover.hovered && !topEdgeHover.hovered) {
                Config.dashboardVisible = false;
            }
        }
    }

    // Input mask: only accept clicks inside the dock, border frame, open dashboard, or active popout
    mask: Region {
        // Left Dock
        Region {
            x: 0
            y: 0
            width: Config.dockEnabled ? root.dockW : 0
            height: root.height
        }

        // Top Border / Top Hover Area
        Region {
            x: 0
            y: 0
            width: root.width
            height: Math.max(root.borderT, 16)
        }

        // Right Border
        Region {
            x: root.width - root.borderT
            y: 0
            width: root.borderT
            height: root.height
        }

        // Bottom Border
        Region {
            x: 0
            y: root.height - root.borderT
            width: root.width
            height: root.borderT
        }

        // Top-left corner fillet
        Region {
            x: root.dockW
            y: root.borderT
            width: root.filletR
            height: root.filletR
        }

        // Active Popout (Network, Bluetooth, Audio, etc.)
        Region {
            x: root.dockW
            y: Math.max(root.borderT, Math.round((root.height - 400) / 2))
            width: Config.activePopout !== "" ? 340 : 0
            height: Config.activePopout !== "" ? 400 : 0
        }

        // Central Fused Dropdown Dashboard (when open)
        Region {
            x: root.dropX - root.filletR
            y: 0
            width: Config.dashboardVisible ? (root.dropW + root.filletR * 2) : 0
            height: Config.dashboardVisible ? (root.dropH + 20) : 0
        }

        // Fused Bottom Popout (when open)
        Region {
            x: root.dockW
            y: Config.bottomPopoutVisible ? Math.max(0, root.height - root.borderT - fusedPopout.implicitHeight - root.filletR) : 0
            width: Config.bottomPopoutVisible ? (fusedPopout.popWidth + root.filletR) : 0
            height: Config.bottomPopoutVisible ? (fusedPopout.implicitHeight + root.filletR + root.borderT) : 0
        }

        // Taskbar App Context Menu & Dismiss Area (when open)
        Region {
            x: 0
            y: 0
            width: appContextMenu.visible ? root.width : 0
            height: appContextMenu.visible ? root.height : 0
        }
    }

    // ==========================================
    // 1. DESKTOP BORDER FRAME & INNER FILLETS
    // ==========================================
    Item {
        id: desktopFrame
        anchors.fill: parent

        layer.enabled: false
        layer.effect: MultiEffect {
            shadowEnabled: true
            blurMax: 16
            shadowBlur: 1.0
            shadowColor: Qt.rgba(0, 0, 0, 0.25)
        }

        // Left Dock Surface
        Rectangle {
            id: dockBg
            visible: Config.dockEnabled
            x: 0
            y: 0
            width: root.dockW
            height: root.height
            color: Colors.surface
        }

        // Thin Top Border
        Rectangle {
            id: topBorder
            x: 0
            y: 0
            width: root.width
            height: root.borderT
            color: Colors.surface
        }

        // Thin Right Border
        Rectangle {
            id: rightBorder
            x: root.width - root.borderT
            y: 0
            width: root.borderT
            height: root.height
            color: Colors.surface
        }

        // Thin Bottom Border
        Rectangle {
            id: bottomBorder
            x: 0
            y: root.height - root.borderT
            width: root.width
            height: root.borderT
            color: Colors.surface
        }

        // Inner Fillet: Top-Left
        CornerFillet {
            x: root.dockW
            y: root.borderT
            orientation: "topLeft"
            cornerRadius: root.filletR
            fillColor: Colors.surface
            strokeColor: "transparent"
        }

        // Inner Fillet: Top-Right
        CornerFillet {
            x: root.width - root.borderT - root.filletR
            y: root.borderT
            orientation: "topRight"
            cornerRadius: root.filletR
            fillColor: Colors.surface
            strokeColor: "transparent"
        }

        // Inner Fillet: Bottom-Left
        CornerFillet {
            visible: !Config.bottomPopoutVisible
            x: root.dockW
            y: root.height - root.borderT - root.filletR
            orientation: "bottomLeft"
            cornerRadius: root.filletR
            fillColor: Colors.surface
            strokeColor: "transparent"
        }

        // Inner Fillet: Bottom-Right
        CornerFillet {
            x: root.width - root.borderT - root.filletR
            y: root.height - root.borderT - root.filletR
            orientation: "bottomRight"
            cornerRadius: root.filletR
            fillColor: Colors.surface
            strokeColor: "transparent"
        }
    }

    // ==========================================
    // 2. TOP-CENTER HOVER TRIGGER ZONE
    // ==========================================
    Item {
        id: hoverTriggerZone
        x: root.dropX
        y: 0
        width: root.dropW
        height: Math.max(root.borderT, 16)

        HoverHandler {
            id: topEdgeHover
            onHoveredChanged: {
                if (hovered && Config.dashboardShowOnHover) {
                    closeTimer.stop();
                    Config.dashboardVisible = true;
                }
            }
        }
    }

    // ==========================================
    // 3. FUSED DROPDOWN DASHBOARD MENU
    // ==========================================
    Item {
        id: dropdownContainer
        x: root.dropX
        y: 0
        width: root.dropW
        height: root.dropH
        visible: offsetProgress > 0

        property real offsetProgress: Config.dashboardVisible ? 1.0 : 0.0

        Behavior on offsetProgress {
            NumberAnimation {
                duration: Theme.animDurationNormal
                easing.type: Easing.OutCubic
            }
        }

        transform: Translate {
            y: -root.dropH * (1.0 - dropdownContainer.offsetProgress)
        }

        // Robust hover tracker covering the entire dropdown from y=0 to y=dropH
        HoverHandler {
            id: dropdownHover
            onHoveredChanged: {
                if (hovered) {
                    closeTimer.stop();
                } else if (Config.dashboardShowOnHover && Config.dashboardVisible) {
                    closeTimer.restart();
                }
            }
        }

        // Inverted Fillet on the Left of the Dropdown
        CornerFillet {
            id: dropFilletL
            visible: dropdownContainer.offsetProgress > 0.8
            x: -root.filletR
            y: root.borderT
            orientation: "dropdownLeft"
            cornerRadius: root.filletR
            fillColor: Colors.surface
            strokeColor: "transparent"
            z: 1
        }

        // Inverted Fillet on the Right of the Dropdown
        CornerFillet {
            id: dropFilletR
            visible: dropdownContainer.offsetProgress > 0.8
            x: root.dropW
            y: root.borderT
            orientation: "dropdownRight"
            cornerRadius: root.filletR
            fillColor: Colors.surface
            strokeColor: "transparent"
            z: 1
        }

        // Main Fused Dropdown Card
        Rectangle {
            id: dashCard
            x: 0
            y: 0
            width: root.dropW
            implicitHeight: cardLayout.implicitHeight + Theme.padLarge * 2

            focus: true
            Keys.onEscapePressed: Config.dashboardVisible = false

            // Flush at top, rounded corners at bottom
            topLeftRadius: 0
            topRightRadius: 0
            bottomLeftRadius: Theme.radiusLarge
            bottomRightRadius: Theme.radiusLarge

            color: Colors.surface
            border.width: 0

            // Soft drop shadow confined strictly below the top border and fillets
            RectangularShadow {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.top: parent.top
                anchors.topMargin: root.borderT + root.filletR
                bottomLeftRadius: parent.bottomLeftRadius
                bottomRightRadius: parent.bottomRightRadius
                blur: 24
                spread: 0
                offset.y: 6
                color: Qt.rgba(0, 0, 0, 0.35)
                z: -1
            }

            ColumnLayout {
                id: cardLayout
                anchors.fill: parent
                anchors.margins: Theme.padLarge
                spacing: Theme.spaceMedium

                // ======================================
                // Tabs Header (Dashboard, Media, Performance, Workspaces)
                // ======================================
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: Theme.spaceExtraLarge

                    Repeater {
                        model: [
                            { id: "dashboard", label: "Dashboard", icon: "dashboard" },
                            { id: "media", label: "Media", icon: "queue_music" },
                            { id: "performance", label: "Performance", icon: "speed" },
                            { id: "workspaces", label: "Workspaces", icon: "grid_view" }
                        ]

                        delegate: Rectangle {
                            required property var modelData
                            readonly property bool isSelected: Config.activeDashboardTab === modelData.id

                            implicitWidth: tabContentRow.implicitWidth + Theme.padLarge * 2
                            implicitHeight: 36
                            radius: Theme.radiusFull
                            color: isSelected ? Colors.primaryContainer : (tabHover.containsMouse ? Colors.surfaceContainerHigh : "transparent")

                            RowLayout {
                                id: tabContentRow
                                anchors.centerIn: parent
                                spacing: Theme.spaceSmall

                                MaterialIcon {
                                    text: modelData.icon
                                    size: 16
                                    color: isSelected ? Colors.primary : Colors.onSurfaceVariant
                                }

                                Text {
                                    text: modelData.label
                                    font.pixelSize: Theme.fontMedium
                                    font.weight: isSelected ? Font.Bold : Font.Normal
                                    font.family: Theme.fontFamily
                                    color: isSelected ? Colors.primary : Colors.onSurfaceVariant
                                }
                            }

                            // Active tab indicator underline
                            Rectangle {
                                anchors.bottom: parent.bottom
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: parent.width * 0.55
                                height: 2
                                radius: 1
                                color: Colors.primary
                                visible: isSelected
                            }

                            MouseArea {
                                id: tabHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    Config.activeDashboardTab = modelData.id;
                                    closeTimer.stop();
                                }
                            }
                        }
                    }
                }

                // Header Separator
                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Theme.borderSubtle
                }

                // Tab Content Stack
                StackLayout {
                    Layout.fillWidth: true
                    currentIndex: {
                        switch (Config.activeDashboardTab) {
                            case "dashboard": return 0;
                            case "media": return 1;
                            case "performance": return 2;
                            case "workspaces": return 3;
                            default: return 0;
                        }
                    }

                    DashboardTab {}
                    MediaTab {}
                    PerformanceTab {}
                    WorkspacesTab {}
                }
            }
        }
    }

    // ==========================================
    // 4. TASKBAR APP CONTEXT MENU
    // ==========================================
    MouseArea {
        id: menuDismissArea
        anchors.fill: parent
        z: 9998
        visible: appContextMenu.visible
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: appContextMenu.visible = false
    }

    Rectangle {
        id: appContextMenu
        visible: false
        z: 9999

        property var targetApp: null
        property real targetGlobalY: 0

        x: root.dockW + 10
        y: Math.max(12, Math.min(root.height - height - 12, targetGlobalY - 10))
        width: 175
        height: menuCol.implicitHeight + 16
        radius: 12
        color: Colors.surfaceContainerLowest
        border.color: Colors.outlineVariant
        border.width: 1

        Rectangle {
            anchors.fill: parent
            anchors.margins: -1
            radius: 13
            color: "transparent"
            border.color: Qt.alpha(Colors.primary, 0.15)
            border.width: 1
            z: -1
        }

        Column {
            id: menuCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 8
            spacing: 4

            // Header: App icon + App Name
            Row {
                spacing: 8
                width: parent.width
                leftPadding: 4
                rightPadding: 4
                bottomPadding: 4

                Image {
                    width: 18
                    height: 18
                    anchors.verticalCenter: parent.verticalCenter
                    source: {
                        if (!appContextMenu.targetApp || !appContextMenu.targetApp.iconName) return "";
                        if (appContextMenu.targetApp.iconName.indexOf("/") !== -1) {
                            return appContextMenu.targetApp.iconName.startsWith("file://") ? appContextMenu.targetApp.iconName : ("file://" + appContextMenu.targetApp.iconName);
                        }
                        return Quickshell.iconPath(appContextMenu.targetApp.iconName);
                    }
                    fillMode: Image.PreserveAspectFit
                    visible: status === Image.Ready
                }

                MaterialIcon {
                    width: 18
                    height: 18
                    anchors.verticalCenter: parent.verticalCenter
                    text: appContextMenu.targetApp ? (appContextMenu.targetApp.materialIcon || "apps") : "apps"
                    size: 16
                    color: Colors.primary
                    visible: !parent.children[0].visible
                }

                Column {
                    width: parent.width - 32
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1

                    Text {
                        text: appContextMenu.targetApp ? appContextMenu.targetApp.appName : ""
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        color: Colors.textOnSurface
                        elide: Text.ElideRight
                        width: parent.width
                    }

                    Text {
                        text: {
                            if (!appContextMenu.targetApp) return "";
                            if (appContextMenu.targetApp.isPinned && appContextMenu.targetApp.isRunning) {
                                return "Pinned • Running";
                            } else if (appContextMenu.targetApp.isPinned) {
                                return "Pinned";
                            } else {
                                return "Running (Unpinned)";
                            }
                        }
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        color: Colors.textMuted
                        elide: Text.ElideRight
                        width: parent.width
                    }
                }
            }

            // Divider
            Rectangle {
                width: parent.width
                height: 1
                color: Colors.outlineVariant
                opacity: 0.6
            }

            // Pin / Unpin Action
            Rectangle {
                width: parent.width
                height: 32
                radius: 6
                color: pinHover.containsMouse ? Colors.surfaceContainerHighest : "transparent"

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    spacing: 10

                    MaterialIcon {
                        text: (appContextMenu.targetApp && appContextMenu.targetApp.isPinned) ? "keep_off" : "push_pin"
                        size: 16
                        color: (appContextMenu.targetApp && appContextMenu.targetApp.isPinned) 
                            ? Colors.primary 
                            : (pinHover.containsMouse ? Colors.primary : Colors.textOnSurfaceVariant)
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: (appContextMenu.targetApp && appContextMenu.targetApp.isPinned) ? "Unpin from dock" : "Pin to dock"
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        font.weight: pinHover.containsMouse ? Font.Medium : Font.Normal
                        color: pinHover.containsMouse ? Colors.primary : Colors.textOnSurface
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                MouseArea {
                    id: pinHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (!appContextMenu.targetApp) return;
                        if (appContextMenu.targetApp.isPinned) {
                            Config.unpinApp(appContextMenu.targetApp.appId, appContextMenu.targetApp.desktopFile, appContextMenu.targetApp.appName);
                        } else {
                            Config.pinApp(appContextMenu.targetApp);
                        }
                        appContextMenu.visible = false;
                    }
                }
            }

            // Close Window Action (if running)
            Rectangle {
                width: parent.width
                height: 32
                radius: 6
                visible: appContextMenu.targetApp && appContextMenu.targetApp.isRunning
                color: closeHover.containsMouse ? Qt.rgba(0.85, 0.2, 0.15, 0.12) : "transparent"

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    spacing: 10

                    MaterialIcon {
                        text: "close"
                        size: 16
                        color: closeHover.containsMouse ? "#D93025" : Colors.textOnSurfaceVariant
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: "Close window"
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        font.weight: closeHover.containsMouse ? Font.Medium : Font.Normal
                        color: closeHover.containsMouse ? "#D93025" : Colors.textOnSurface
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                MouseArea {
                    id: closeHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (appContextMenu.targetApp && appContextMenu.targetApp.id) {
                            WindowService.closeWindow(appContextMenu.targetApp.id);
                        }
                        appContextMenu.visible = false;
                    }
                }
            }

            // Launch Action (if pinned and not running)
            Rectangle {
                width: parent.width
                height: 32
                radius: 6
                visible: appContextMenu.targetApp && !appContextMenu.targetApp.isRunning
                color: launchHover.containsMouse ? Colors.surfaceContainerHighest : "transparent"

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    spacing: 10

                    MaterialIcon {
                        text: "play_arrow"
                        size: 16
                        color: launchHover.containsMouse ? Colors.primary : Colors.textOnSurfaceVariant
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: "Launch application"
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        font.weight: launchHover.containsMouse ? Font.Medium : Font.Normal
                        color: launchHover.containsMouse ? Colors.primary : Colors.textOnSurface
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                MouseArea {
                    id: launchHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (appContextMenu.targetApp) {
                            WindowService.launchApp(appContextMenu.targetApp.desktopFile || appContextMenu.targetApp.appId);
                        }
                        appContextMenu.visible = false;
                    }
                }
            }
        }
    }

    // ==========================================
    // 5. LEFT DOCK CONTENT
    // ==========================================
    Item {
        id: dockContent
        visible: Config.dockEnabled
        x: 0
        y: root.borderT + 6
        width: root.dockW
        height: root.height - root.borderT * 2 - 12

        readonly property var pinnedList: {
            const pinned = Config.pinnedApps || [];
            const wins = WindowService.windows || [];
            const result = [];
            const matchedWinIds = new Set();

            for (let i = 0; i < pinned.length; i++) {
                const p = pinned[i];
                const pId = (p.appId || "").toLowerCase();
                const pDesk = (p.desktopFile || "").toLowerCase();
                const pName = (p.appName || "").toLowerCase();

                let found = null;
                for (let j = 0; j < wins.length; j++) {
                    const w = wins[j];
                    if (matchedWinIds.has(w.id)) continue;
                    const wId = (w.appId || "").toLowerCase();
                    const wDesk = (w.desktopFile || "").toLowerCase();
                    const wName = (w.appName || "").toLowerCase();
                    const wCls = (w.cls || "").toLowerCase();

                    if ((pId && (wId === pId || wDesk === pId || wCls === pId))
                        || (pDesk && (wDesk === pDesk || wId === pDesk))
                        || (pName && wName === pName)) {
                        found = w;
                        break;
                    }
                }

                if (found) {
                    matchedWinIds.add(found.id);
                    result.push({
                        isPinned: true,
                        isRunning: true,
                        id: found.id,
                        appId: p.appId,
                        appName: p.appName || found.appName,
                        iconName: p.iconName || found.iconName,
                        materialIcon: p.materialIcon || found.materialIcon,
                        desktopFile: p.desktopFile || found.desktopFile,
                        title: found.title,
                        isActive: found.isActive
                    });
                } else {
                    result.push({
                        isPinned: true,
                        isRunning: false,
                        id: "",
                        appId: p.appId,
                        appName: p.appName,
                        iconName: p.iconName,
                        materialIcon: p.materialIcon,
                        desktopFile: p.desktopFile,
                        title: "",
                        isActive: false
                    });
                }
            }
            return result;
        }

        readonly property var unpinnedList: {
            const pinned = Config.pinnedApps || [];
            const wins = WindowService.windows || [];
            const result = [];
            const matchedWinIds = new Set();

            for (let i = 0; i < pinned.length; i++) {
                const p = pinned[i];
                const pId = (p.appId || "").toLowerCase();
                const pDesk = (p.desktopFile || "").toLowerCase();
                const pName = (p.appName || "").toLowerCase();

                for (let j = 0; j < wins.length; j++) {
                    const w = wins[j];
                    if (matchedWinIds.has(w.id)) continue;
                    const wId = (w.appId || "").toLowerCase();
                    const wDesk = (w.desktopFile || "").toLowerCase();
                    const wName = (w.appName || "").toLowerCase();
                    const wCls = (w.cls || "").toLowerCase();

                    if ((pId && (wId === pId || wDesk === pId || wCls === pId))
                        || (pDesk && (wDesk === pDesk || wId === pDesk))
                        || (pName && wName === pName)) {
                        matchedWinIds.add(w.id);
                        break;
                    }
                }
            }

            for (let k = 0; k < wins.length; k++) {
                const w = wins[k];
                if (!matchedWinIds.has(w.id)) {
                    result.push({
                        isPinned: false,
                        isRunning: true,
                        id: w.id,
                        appId: w.appId || (w.appName ? w.appName.toLowerCase() : "window"),
                        appName: w.appName,
                        iconName: w.iconName,
                        materialIcon: w.materialIcon,
                        desktopFile: w.desktopFile || w.appId,
                        title: w.title,
                        isActive: w.isActive
                    });
                }
            }

            return result;
        }

        readonly property var taskbarList: pinnedList.concat(unpinnedList)

        // TOP SECTION: Launcher & Workspaces Pill
        Column {
            id: topSection
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8

            // 1. App Launcher Button (^)
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: root.iconS + 10
                height: root.iconS + 10
                implicitWidth: root.iconS + 10
                implicitHeight: root.iconS + 10
                radius: Theme.radiusFull
                color: launcherHover.containsMouse ? Colors.surfaceContainerHigh : Colors.surfaceContainer
                border.color: Theme.borderSubtle
                border.width: 1

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "expand_less"
                    size: Math.round(root.iconS * 0.82)
                    color: Colors.primary
                }

                MouseArea {
                    id: launcherHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        Config.dashboardVisible = !Config.dashboardVisible;
                    }
                }

                // Launcher Tooltip
                Rectangle {
                    z: 100
                    visible: launcherHover.containsMouse
                    anchors.left: parent.right
                    anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: launcherTipText.implicitWidth + 16
                    implicitHeight: launcherTipText.implicitHeight + 10
                    radius: 8
                    color: Colors.surfaceContainerHighest
                    border.color: Theme.borderSubtle
                    border.width: 1

                    Text {
                        id: launcherTipText
                        anchors.centerIn: parent
                        text: "App Launcher & Dashboard"
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        color: Colors.textOnSurface
                    }
                }
            }

            // 2. Workspaces Vertical Pill (KDE Plasma Virtual Desktops)
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                implicitWidth: root.iconS + 16
                implicitHeight: (root.iconS + 10 + 4) * 4 + 8
                radius: Theme.radiusFull
                color: Colors.surfaceContainer
                border.color: Theme.borderSubtle
                border.width: 1

                Column {
                    anchors.centerIn: parent
                    spacing: 4

                    Repeater {
                        model: [
                            { index: 0, icon: "bedtime", name: "Workspace 1" },
                            { index: 1, icon: "web_asset", name: "Workspace 2" },
                            { index: 2, icon: "radio_button_unchecked", name: "Workspace 3" },
                            { index: 3, icon: "circle", name: "Workspace 4" }
                        ]

                        delegate: Rectangle {
                            id: wsDelegate
                            required property var modelData
                            readonly property bool isActive: (KWinWorkspaces.desktops.length > modelData.index)
                                ? KWinWorkspaces.desktops[modelData.index].active
                                : (modelData.index === 0)

                            readonly property int wsBtnSize: root.iconS + 10

                            width: wsBtnSize
                            height: wsBtnSize
                            implicitWidth: wsBtnSize
                            implicitHeight: wsBtnSize
                            radius: Theme.radiusFull
                            color: isActive ? Colors.primaryContainer : (wsHover.containsMouse ? Colors.surfaceContainerHigh : "transparent")

                            MaterialIcon {
                                anchors.centerIn: parent
                                text: modelData.icon
                                size: (modelData.icon === "circle") ? Math.round(root.iconS * 0.45) : Math.round(root.iconS * 0.72)
                                color: isActive ? Colors.primary : Colors.onSurfaceVariant
                            }

                            MouseArea {
                                id: wsHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    KWinWorkspaces.switchToWorkspace(modelData.index);
                                }
                            }

                            // Workspace Tooltip
                            Rectangle {
                                z: 100
                                visible: wsHover.containsMouse
                                anchors.left: parent.right
                                anchors.leftMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                implicitWidth: wsTipText.implicitWidth + 16
                                implicitHeight: wsTipText.implicitHeight + 10
                                radius: 8
                                color: Colors.surfaceContainerHighest
                                border.color: Theme.borderSubtle
                                border.width: 1

                                Text {
                                    id: wsTipText
                                    anchors.centerIn: parent
                                    text: (KWinWorkspaces.desktops.length > modelData.index && KWinWorkspaces.desktops[modelData.index].name)
                                        ? KWinWorkspaces.desktops[modelData.index].name
                                        : modelData.name
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    color: Colors.textOnSurface
                                }
                            }
                        }
                    }
                }
            }
        }

        // MIDDLE SECTION: Vertical Rotated Active Window / Desktop
        Item {
            id: activeWindowPill
            anchors.top: topSection.bottom
            anchors.topMargin: 20
            anchors.horizontalCenter: parent.horizontalCenter
            implicitWidth: root.iconS + 16
            implicitHeight: 140
            visible: (dockContent.height - bottomCol.implicitHeight) > 300

            Row {
                anchors.centerIn: parent
                rotation: 90
                spacing: 8

                Image {
                    id: activeIconImg
                    width: root.iconS
                    height: root.iconS
                    source: {
                        if (!WindowService.activeIconName) return "";
                        if (WindowService.activeIconName.indexOf("/") !== -1) {
                            return WindowService.activeIconName.startsWith("file://") ? WindowService.activeIconName : ("file://" + WindowService.activeIconName);
                        }
                        return Quickshell.iconPath(WindowService.activeIconName);
                    }
                    fillMode: Image.PreserveAspectFit
                    visible: status === Image.Ready
                    anchors.verticalCenter: parent.verticalCenter
                }

                MaterialIcon {
                    text: WindowService.activeMaterialIcon || "desktop_windows"
                    size: Math.round(root.iconS * 0.82)
                    color: Colors.textOnSurfaceVariant
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !activeIconImg.visible || activeIconImg.status !== Image.Ready
                }

                Text {
                    text: WindowService.activeTitle || "Desktop"
                    font.family: Theme.fontFamily
                    font.pixelSize: Math.max(13, Math.round(root.iconS * 0.45))
                    font.weight: Font.Medium
                    color: Colors.textOnSurfaceVariant
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        // LOWER SECTION (Tray + Running Apps + Clock) & BOTTOM SECTION (Status Icons)
        Column {
            id: bottomCol
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8
            anchors.bottomMargin: 8

            // 1. APPS CONTAINER (Dedicated capsule pill for applications)
            Rectangle {
                id: appsContainer
                anchors.horizontalCenter: parent.horizontalCenter
                implicitWidth: root.iconS + 16
                implicitHeight: appsCol.implicitHeight + 8
                radius: Math.round((root.iconS + 16) * 0.25)
                color: Colors.surfaceContainer
                border.color: Theme.borderSubtle
                border.width: 1
                visible: dockContent.taskbarList.length > 0

                Column {
                    id: appsCol
                    anchors.centerIn: parent
                    spacing: 4

                    Component {
                        id: appDelegateComponent

                        Rectangle {
                            id: appDelegate
                            required property var modelData

                            readonly property int itemSize: root.iconS + 10

                            width: itemSize
                            height: itemSize
                            implicitWidth: itemSize
                            implicitHeight: itemSize
                            radius: Math.max(6, Math.round(itemSize * 0.22))
                            color: modelData.isActive ? Colors.primaryContainer : (appHover.containsMouse ? Colors.surfaceContainerHigh : "transparent")

                            // Active left pill indicator
                            Rectangle {
                                anchors.left: parent.left
                                anchors.leftMargin: 1
                                anchors.verticalCenter: parent.verticalCenter
                                width: 3
                                height: modelData.isActive ? Math.round(root.iconS * 0.65) : 0
                                radius: 1.5
                                color: Colors.primary
                                visible: modelData.isActive

                                Behavior on height {
                                    NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
                                }
                            }

                            // Running dot indicator for inactive running windows
                            Rectangle {
                                anchors.left: parent.left
                                anchors.leftMargin: 1
                                anchors.verticalCenter: parent.verticalCenter
                                width: 3
                                height: 3
                                radius: 1.5
                                color: Colors.textMuted
                                visible: modelData.isRunning && !modelData.isActive
                            }

                            // App Icon
                            Image {
                                id: appIconImg
                                anchors.centerIn: parent
                                width: root.iconS
                                height: root.iconS
                                opacity: modelData.isRunning ? 1.0 : 0.65
                                source: {
                                    if (!modelData.iconName) return "";
                                    if (modelData.iconName.indexOf("/") !== -1) {
                                        return modelData.iconName.startsWith("file://") ? modelData.iconName : ("file://" + modelData.iconName);
                                    }
                                    return Quickshell.iconPath(modelData.iconName);
                                }
                                fillMode: Image.PreserveAspectFit
                                visible: status === Image.Ready
                            }

                            MaterialIcon {
                                anchors.centerIn: parent
                                text: modelData.materialIcon || "desktop_windows"
                                size: Math.round(root.iconS * 0.82)
                                opacity: modelData.isRunning ? 1.0 : 0.65
                                color: modelData.isActive ? Colors.primary : Colors.onSurfaceVariant
                                visible: !appIconImg.visible || appIconImg.status !== Image.Ready
                            }

                            MouseArea {
                                id: appHover
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                cursorShape: Qt.PointingHandCursor
                                onClicked: mouse => {
                                    if (mouse.button === Qt.RightButton) {
                                        const mapped = mapToItem(dockContent, 0, 0);
                                        appContextMenu.targetApp = modelData;
                                        appContextMenu.targetGlobalY = mapped.y;
                                        appContextMenu.visible = true;
                                    } else {
                                        if (modelData.isRunning) {
                                            WindowService.activateWindow(modelData.id);
                                        } else {
                                            WindowService.launchApp(modelData.desktopFile || modelData.appId);
                                        }
                                    }
                                }
                            }

                            // Tooltip on hover
                            Rectangle {
                                z: 100
                                visible: appHover.containsMouse && !appContextMenu.visible
                                anchors.left: parent.right
                                anchors.leftMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                implicitWidth: tipText.implicitWidth + 16
                                implicitHeight: tipText.implicitHeight + 10
                                radius: 7
                                color: Colors.surfaceContainerHighest
                                border.color: Colors.outlineVariant
                                border.width: 1

                                Text {
                                    id: tipText
                                    anchors.centerIn: parent
                                    text: {
                                        if (modelData.isPinned && modelData.isRunning) {
                                            return (modelData.appName + (modelData.title ? (" — " + modelData.title.slice(0, 32)) : "")) + " (Pinned)";
                                        } else if (modelData.isPinned && !modelData.isRunning) {
                                            return modelData.appName + " (Click to launch)";
                                        } else {
                                            return (modelData.appName + (modelData.title ? (" — " + modelData.title.slice(0, 32)) : "")) + " (Running)";
                                        }
                                    }
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    color: Colors.onSurface
                                }
                            }
                        }
                    }

                    // 1. Pinned Apps
                    Repeater {
                        model: dockContent.pinnedList
                        delegate: appDelegateComponent
                    }

                    // 2. Clear Divider between Pinned Apps and Unpinned Running Apps
                    Item {
                        anchors.horizontalCenter: parent.horizontalCenter
                        implicitWidth: root.iconS + 10
                        implicitHeight: 12
                        visible: dockContent.pinnedList.length > 0 && dockContent.unpinnedList.length > 0

                        Rectangle {
                            anchors.centerIn: parent
                            width: Math.round(root.iconS * 0.65)
                            height: 2
                            radius: 1
                            color: Colors.outline
                            opacity: 0.7
                        }
                    }

                    // 3. Unpinned Running Apps
                    Repeater {
                        model: dockContent.unpinnedList
                        delegate: appDelegateComponent
                    }
                }
            }

            // 2. CLEAR VISUAL DIVIDER BETWEEN APPS & STATUS
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                implicitWidth: root.iconS + 16
                implicitHeight: 16
                visible: dockContent.taskbarList.length > 0 && WindowService.tray.length > 0

                Rectangle {
                    anchors.centerIn: parent
                    width: Math.round(root.iconS * 0.75)
                    height: 2.5
                    radius: 1.25
                    color: Colors.outline
                    opacity: 0.85
                }
            }

            // 3. SYSTEM TRAY ICONS CONTAINER (Dedicated capsule pill for system status tray)
            Rectangle {
                id: trayContainer
                anchors.horizontalCenter: parent.horizontalCenter
                implicitWidth: root.iconS + 16
                implicitHeight: trayCol.implicitHeight + 8
                radius: Math.round((root.iconS + 16) * 0.25)
                color: Colors.surfaceContainer
                border.color: Theme.borderSubtle
                border.width: 1
                visible: WindowService.tray.length > 0

                Column {
                    id: trayCol
                    anchors.centerIn: parent
                    spacing: 4

                    Repeater {
                        model: WindowService.tray

                        delegate: Rectangle {
                            id: trayDelegate
                            required property var modelData

                            readonly property bool isInputMethod: {
                                const raw = (modelData.rawIcon || "").toLowerCase();
                                const id = (modelData.id || "").toLowerCase();
                                const title = (modelData.title || "").toLowerCase();
                                return raw.includes("keyboard") || raw.includes("fcitx") || id.includes("fcitx") || id.includes("input") || title.includes("input");
                            }

                            readonly property int itemSize: root.iconS + 10

                            width: itemSize
                            height: itemSize
                            implicitWidth: itemSize
                            implicitHeight: itemSize
                            radius: Math.max(6, Math.round(itemSize * 0.22))
                            color: trayHover.containsMouse ? Colors.surfaceContainerHigh : "transparent"

                            // Text badge for Input Method (EN / 中 / 拼) for highest readability
                            Text {
                                id: imBadgeText
                                anchors.centerIn: parent
                                visible: isInputMethod && !!modelData.imBadge
                                text: modelData.imBadge || ""
                                font.family: Theme.fontFamily
                                font.pixelSize: Math.max(13, Math.round(root.iconS * 0.48))
                                font.bold: true
                                color: (modelData.imBadge === "中" || modelData.imBadge === "拼")
                                    ? Colors.primary
                                    : (trayHover.containsMouse ? Colors.primary : Colors.textOnSurface)
                            }

                            Image {
                                id: trayIconImg
                                anchors.centerIn: parent
                                width: root.iconS
                                height: root.iconS
                                source: modelData.rawIcon ? Quickshell.iconPath(modelData.rawIcon) : ""
                                fillMode: Image.PreserveAspectFit
                                visible: !imBadgeText.visible && status === Image.Ready
                            }

                            MaterialIcon {
                                anchors.centerIn: parent
                                text: modelData.materialIcon || "circle"
                                size: Math.round(root.iconS * 0.82)
                                color: trayHover.containsMouse ? Colors.primary : Colors.onSurfaceVariant
                                visible: !imBadgeText.visible && (!trayIconImg.visible || trayIconImg.status !== Image.Ready)
                            }

                            MouseArea {
                                id: trayHover
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                cursorShape: Qt.PointingHandCursor
                                onClicked: mouse => {
                                    if (mouse.button === Qt.RightButton) {
                                        WindowService.contextMenuTray(modelData.service, modelData.path);
                                    } else {
                                        WindowService.activateTray(modelData.service, modelData.path);
                                    }
                                }
                            }

                            // Tooltip on hover
                            Rectangle {
                                z: 100
                                visible: trayHover.containsMouse
                                anchors.left: parent.right
                                anchors.leftMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                implicitWidth: trayTipText.implicitWidth + 16
                                implicitHeight: trayTipText.implicitHeight + 10
                                radius: 7
                                color: Colors.surfaceContainerHighest
                                border.color: Colors.outlineVariant
                                border.width: 1

                                Text {
                                    id: trayTipText
                                    anchors.centerIn: parent
                                    text: modelData.title || modelData.id
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    color: Colors.onSurface
                                }
                            }
                        }
                    }
                }
            }

            // Stacked Clock (Hours over Minutes)
            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 1

                Timer {
                    id: clockTimer
                    interval: 1000
                    running: true
                    repeat: true
                    triggeredOnStart: true
                    onTriggered: {
                        const now = new Date();
                        hourText.text = Qt.formatDateTime(now, "HH");
                        minuteText.text = Qt.formatDateTime(now, "mm");
                    }
                }

                Text {
                    id: hourText
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "12"
                    font.family: Theme.fontFamily
                    font.pixelSize: Math.max(13, Math.round(root.iconS * 0.44))
                    font.weight: Font.DemiBold
                    color: Colors.textOnSurface
                }

                Text {
                    id: minuteText
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "00"
                    font.family: Theme.fontFamily
                    font.pixelSize: Math.max(13, Math.round(root.iconS * 0.44))
                    font.weight: Font.DemiBold
                    color: Colors.textOnSurface
                }
            }

            // Anchored Status Icons Group Pill at the Bottom
            DockStatusIcons {
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    // ==========================================
    // 5. FUSED BOTTOM POPOUT (BATTERY/PROFILES, BLUETOOTH, ETC.)
    // ==========================================
    Item {
        id: fusedBottomPopoutWrapper
        x: root.dockW
        y: root.height - root.borderT - fusedPopout.implicitHeight
        width: fusedPopout.popWidth
        height: fusedPopout.implicitHeight
        visible: offsetProgress > 0

        property real offsetProgress: Config.bottomPopoutVisible ? 1.0 : 0.0

        Behavior on offsetProgress {
            NumberAnimation {
                duration: Theme.animDurationNormal
                easing.type: Easing.OutCubic
            }
        }

        opacity: offsetProgress
        transform: Translate {
            y: 16 * (1.0 - fusedBottomPopoutWrapper.offsetProgress)
        }

        HoverHandler {
            id: bottomPopoutHover
            onHoveredChanged: {
                if (hovered) {
                    Config.keepBottomPopout();
                } else {
                    Config.scheduleCloseBottomPopout();
                }
            }
        }

        // Top-Left Inverted Fillet (Dock to Popout)
        CornerFillet {
            visible: fusedBottomPopoutWrapper.offsetProgress > 0.8
            x: 0
            y: -root.filletR
            orientation: "bottomLeft"
            cornerRadius: root.filletR
            fillColor: Colors.surface
            strokeColor: "transparent"
        }

        // Bottom-Right Inverted Fillet (Popout to Bottom Border)
        CornerFillet {
            visible: fusedBottomPopoutWrapper.offsetProgress > 0.8
            x: fusedPopout.popWidth
            y: fusedPopout.implicitHeight - root.filletR
            orientation: "bottomLeft"
            cornerRadius: root.filletR
            fillColor: Colors.surface
            strokeColor: "transparent"
        }

        RectangularShadow {
            anchors.fill: fusedPopout
            topRightRadius: Config.borderRounding
            blur: 28
            spread: 0
            offset.x: 6
            offset.y: -4
            color: Qt.rgba(0, 0, 0, 0.4)
            z: -1
        }

        FusedBottomPopout {
            id: fusedPopout
            mode: Config.bottomPopoutMode
        }
    }
}
