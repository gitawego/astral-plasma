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
    // 4. LEFT DOCK CONTENT
    // ==========================================
    Item {
        id: dockContent
        visible: Config.dockEnabled
        x: 0
        y: root.borderT + 6
        width: root.dockW
        height: root.height - root.borderT * 2 - 12

        // TOP SECTION: Launcher & Workspaces Pill
        Column {
            id: topSection
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8

            // 1. App Launcher Button (^)
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                implicitWidth: 38
                implicitHeight: 38
                radius: Theme.radiusFull
                color: launcherHover.containsMouse ? Colors.surfaceContainerHigh : Colors.surfaceContainer
                border.color: Theme.borderSubtle
                border.width: 1

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "expand_less"
                    size: 20
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
            }

            // 2. Workspaces Vertical Pill
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                implicitWidth: 34
                implicitHeight: 128
                radius: Theme.radiusFull
                color: Colors.surfaceContainer
                border.color: Theme.borderSubtle
                border.width: 1

                Column {
                    anchors.centerIn: parent
                    spacing: 3

                    Repeater {
                        model: [
                            { index: 0, icon: "bedtime" },
                            { index: 1, icon: "web_asset" },
                            { index: 2, icon: "radio_button_unchecked" },
                            { index: 3, icon: "circle" }
                        ]

                        delegate: Rectangle {
                            required property var modelData
                            readonly property bool isActive: (KWinWorkspaces.desktops.length > modelData.index)
                                ? KWinWorkspaces.desktops[modelData.index].active
                                : (modelData.index === 0)

                            implicitWidth: 26
                            implicitHeight: 26
                            radius: Theme.radiusFull
                            color: isActive ? Colors.primaryContainer : (wsHover.containsMouse ? Colors.surfaceContainerHigh : "transparent")

                            MaterialIcon {
                                anchors.centerIn: parent
                                text: modelData.icon
                                size: (modelData.icon === "circle") ? 8 : 14
                                color: isActive ? Colors.primary : Colors.onSurfaceVariant
                            }

                            MouseArea {
                                id: wsHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (KWinWorkspaces.desktops.length > modelData.index) {
                                        KWinWorkspaces.switchTo(KWinWorkspaces.desktops[modelData.index].id);
                                    }
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
            anchors.topMargin: 24
            anchors.horizontalCenter: parent.horizontalCenter
            implicitWidth: 34
            implicitHeight: 130
            visible: (dockContent.height - bottomCol.implicitHeight) > 340

            Row {
                anchors.centerIn: parent
                rotation: 90
                spacing: 6

                Image {
                    id: activeIconImg
                    width: 16
                    height: 16
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
                    size: 16
                    color: Colors.textOnSurfaceVariant
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !activeIconImg.visible || activeIconImg.status !== Image.Ready
                }

                Text {
                    text: WindowService.activeTitle || "Desktop"
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
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
            spacing: 10
            anchors.bottomMargin: 8

            // Running Apps (Taskbar)
            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 5
                visible: WindowService.windows.length > 0

                Repeater {
                    model: WindowService.windows

                    delegate: Rectangle {
                        id: appDelegate
                        required property var modelData

                        width: 32
                        height: 32
                        implicitWidth: 32
                        implicitHeight: 32
                        radius: 8
                        color: modelData.isActive ? Colors.primaryContainer : (appHover.containsMouse ? Colors.surfaceContainerHigh : "transparent")

                        // Active left pill indicator
                        Rectangle {
                            anchors.left: parent.left
                            anchors.leftMargin: -5
                            anchors.verticalCenter: parent.verticalCenter
                            width: 3.5
                            height: modelData.isActive ? 16 : 0
                            radius: 1.75
                            color: Colors.primary
                            visible: modelData.isActive

                            Behavior on height {
                                NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
                            }
                        }

                        // App Icon
                        Image {
                            id: appIconImg
                            anchors.centerIn: parent
                            width: 22
                            height: 22
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
                            size: 18
                            color: modelData.isActive ? Colors.primary : Colors.onSurfaceVariant
                            visible: !appIconImg.visible || appIconImg.status !== Image.Ready
                        }

                        MouseArea {
                            id: appHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                WindowService.activateWindow(modelData.id);
                            }
                        }

                        // Tooltip on hover
                        Rectangle {
                            z: 100
                            visible: appHover.containsMouse
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
                                text: modelData.appName + (modelData.title ? (" — " + modelData.title.slice(0, 32)) : "")
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                color: Colors.onSurface
                            }
                        }
                    }
                }
            }

            // Subtle divider between Running Apps and Tray
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 18
                height: 1
                color: Colors.outlineVariant
                visible: WindowService.windows.length > 0 && WindowService.tray.length > 0
                opacity: 0.5
            }

            // System Tray Icons
            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 5
                visible: WindowService.tray.length > 0

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

                        width: 26
                        height: 26
                        implicitWidth: 26
                        implicitHeight: 26
                        radius: 6
                        color: trayHover.containsMouse ? Colors.surfaceContainerHigh : "transparent"

                        Image {
                            id: trayIconImg
                            anchors.centerIn: parent
                            width: 16
                            height: 16
                            source: (!isInputMethod && modelData.rawIcon) ? Quickshell.iconPath(modelData.rawIcon) : ""
                            fillMode: Image.PreserveAspectFit
                            visible: !isInputMethod && status === Image.Ready
                        }

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: modelData.materialIcon || (isInputMethod ? "keyboard" : "circle")
                            size: 16
                            color: isInputMethod
                                ? (trayHover.containsMouse ? Colors.primary : Colors.textOnSurface)
                                : (trayHover.containsMouse ? Colors.primary : Colors.onSurfaceVariant)
                            visible: isInputMethod || !trayIconImg.visible || trayIconImg.status !== Image.Ready
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
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    color: Colors.textOnSurface
                }

                Text {
                    id: minuteText
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "00"
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
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
