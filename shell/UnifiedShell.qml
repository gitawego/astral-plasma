pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import QtQuick.Shapes
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
import "../menus"
import "../notifications"
import "../components"

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
    readonly property int dropH: Math.round(cardLayout.implicitHeight + Theme.padLarge * 2)
    readonly property real currentDropH: borderT + (dropH - borderT) * dropdownContainer.offsetProgress
    readonly property real currentPopW: (typeof fusedPopout !== "undefined" ? fusedPopout.popWidth : 280) * fusedBottomPopoutWrapper.offsetProgress
    readonly property color borderColor: Theme.borderSubtle

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
        const testTab = Quickshell.env("TEST_DASHBOARD_TAB");
        if (testTab) {
            Config.activeDashboardTab = testTab;
        }
    }

    // Auto-close grace timer when leaving the dropdown
    Timer {
        id: closeTimer
        interval: 350
        repeat: false
        onTriggered: {
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
            width: dropdownContainer.offsetProgress > 0.001 ? (root.dropW + root.filletR * 2) : 0
            height: dropdownContainer.offsetProgress > 0.001 ? (root.currentDropH + 20) : 0
        }

        // Fused Bottom Popout (when open)
        Region {
            x: root.dockW
            y: fusedBottomPopoutWrapper.offsetProgress > 0.001 ? Math.max(0, root.height - root.borderT - fusedPopout.implicitHeight - root.filletR) : 0
            width: fusedBottomPopoutWrapper.offsetProgress > 0.001 ? (root.currentPopW + root.filletR) : 0
            height: fusedBottomPopoutWrapper.offsetProgress > 0.001 ? (fusedPopout.implicitHeight + root.filletR + root.borderT) : 0
        }

        // Taskbar App Context Menu & Dismiss Area (when open)
        Region {
            x: 0
            y: 0
            width: appContextMenu.visible ? root.width : 0
            height: appContextMenu.visible ? root.height : 0
        }

        // Top-Right Fused Notification Popup (when visible)
        Region {
            x: sysNotifPopup.visible ? (root.width - sysNotifPopup.width - root.filletR) : 0
            y: 0
            width: sysNotifPopup.visible ? (sysNotifPopup.width + root.filletR) : 0
            height: sysNotifPopup.visible ? (sysNotifPopup.height + root.filletR) : 0
        }
    }

    // ==========================================
    // 1. DESKTOP BORDER FRAME & INNER FILLETS
    // ==========================================
    Item {
        id: desktopFrame
        anchors.fill: parent

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            blurMax: 32
            shadowBlur: 1.0
            shadowVerticalOffset: 3
            shadowColor: Qt.rgba(0, 0, 0, 0.28)
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

            Rectangle {
                x: parent.width - 1
                y: root.borderT + root.filletR
                width: 1
                height: Math.max(0, parent.height - (root.borderT * 2 + root.filletR * 2))
                color: root.borderColor
            }
        }

        // Thin Top Border
        Rectangle {
            id: topBorder
            x: 0
            y: 0
            width: root.width
            height: root.borderT
            color: Colors.surface

            // Segment left of dropdown
            Rectangle {
                x: root.dockW + root.filletR
                y: parent.height - 1
                height: 1
                width: dropdownContainer.offsetProgress > 0.001 
                    ? Math.max(0, root.dropX - root.filletR - (root.dockW + root.filletR))
                    : Math.max(0, root.width - root.borderT - root.filletR - (root.dockW + root.filletR))
                color: root.borderColor
            }

            // Segment right of dropdown (only when dropdown is open)
            Rectangle {
                visible: dropdownContainer.offsetProgress > 0.001
                x: root.dropX + root.dropW + root.filletR
                y: parent.height - 1
                height: 1
                width: Math.max(0, root.width - root.borderT - root.filletR - (root.dropX + root.dropW + root.filletR))
                color: root.borderColor
            }
        }

        // Thin Right Border
        Rectangle {
            id: rightBorder
            x: root.width - root.borderT
            y: 0
            width: root.borderT
            height: root.height
            color: Colors.surface

            Rectangle {
                x: 0
                y: root.borderT + root.filletR
                width: 1
                height: Math.max(0, parent.height - (root.borderT * 2 + root.filletR * 2))
                color: root.borderColor
            }
        }

        // Thin Bottom Border
        Rectangle {
            id: bottomBorder
            x: 0
            y: root.height - root.borderT
            width: root.width
            height: root.borderT
            color: Colors.surface

            Rectangle {
                x: root.dockW + root.filletR
                y: 0
                height: 1
                width: Math.max(0, parent.width - (root.dockW + root.borderT + root.filletR * 2))
                color: root.borderColor
            }
        }

        // Inner Fillet: Top-Left
        CornerFillet {
            x: root.dockW
            y: root.borderT
            orientation: "topLeft"
            cornerRadius: root.filletR
            fillColor: Colors.surface
            strokeColor: root.borderColor
            strokeWidth: 1
        }

        // Inner Fillet: Top-Right
        CornerFillet {
            visible: !NotificationService.hasNotification
            x: root.width - root.borderT - root.filletR
            y: root.borderT
            orientation: "topRight"
            cornerRadius: root.filletR
            fillColor: Colors.surface
            strokeColor: root.borderColor
            strokeWidth: 1
        }

        // Inner Fillet: Bottom-Left
        CornerFillet {
            visible: fusedBottomPopoutWrapper.offsetProgress < 0.99
            opacity: 1.0 - fusedBottomPopoutWrapper.offsetProgress
            x: root.dockW
            y: root.height - root.borderT - root.filletR
            orientation: "bottomLeft"
            cornerRadius: root.filletR
            fillColor: Colors.surface
            strokeColor: root.borderColor
            strokeWidth: 1
        }

        // Inner Fillet: Bottom-Right
        CornerFillet {
            x: root.width - root.borderT - root.filletR
            y: root.height - root.borderT - root.filletR
            orientation: "bottomRight"
            cornerRadius: root.filletR
            fillColor: Colors.surface
            strokeColor: root.borderColor
            strokeWidth: 1
        }

        // ======================================
        // Central Dashboard Fused Solid Surface
        // ======================================
        Item {
            id: dashSurfaceWrapper
            x: root.dropX
            y: 0
            width: root.dropW
            height: root.currentDropH
            visible: dropdownContainer.offsetProgress > 0.001

            readonly property real filletFactor: Math.max(0.0, Math.min(1.0, (root.currentDropH - root.borderT) / Math.max(1, root.filletR)))

            // Left Inverted Fillet (permanently anchored to topBorder)
            CornerFillet {
                x: -root.filletR
                y: root.borderT
                orientation: "dropdownLeft"
                cornerRadius: root.filletR
                fillColor: Colors.surface
                strokeColor: "transparent"
                visible: dashSurfaceWrapper.filletFactor > 0.01
                opacity: dashSurfaceWrapper.filletFactor
            }

            // Right Inverted Fillet (permanently anchored to topBorder)
            CornerFillet {
                x: root.dropW
                y: root.borderT
                orientation: "dropdownRight"
                cornerRadius: root.filletR
                fillColor: Colors.surface
                strokeColor: "transparent"
                visible: dashSurfaceWrapper.filletFactor > 0.01
                opacity: dashSurfaceWrapper.filletFactor
            }

            // Expanding Dashboard Body anchored permanently at y = 0
            Rectangle {
                x: -2
                y: 0
                width: root.dropW + 4
                height: root.currentDropH
                color: Colors.surface
                topLeftRadius: 0
                topRightRadius: 0
                bottomLeftRadius: root.filletR
                bottomRightRadius: root.filletR
            }

            // Continuous 1px Gray Border around Expanding Dropdown & Inverted Fillets
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                visible: dashSurfaceWrapper.filletFactor > 0.01
                opacity: dashSurfaceWrapper.filletFactor

                ShapePath {
                    fillColor: "transparent"
                    strokeColor: root.borderColor
                    strokeWidth: 1
                    capStyle: ShapePath.FlatCap

                    startX: -root.filletR; startY: root.borderT
                    PathArc {
                        x: 0
                        y: root.borderT + root.filletR
                        radiusX: root.filletR
                        radiusY: root.filletR
                        direction: PathArc.Clockwise
                    }
                    PathLine {
                        x: 0
                        y: Math.max(root.borderT + root.filletR, root.currentDropH - root.filletR)
                    }
                    PathArc {
                        x: root.filletR
                        y: root.currentDropH
                        radiusX: root.filletR
                        radiusY: root.filletR
                        direction: PathArc.Counterclockwise
                    }
                    PathLine {
                        x: Math.max(root.filletR, root.dropW - root.filletR)
                        y: root.currentDropH
                    }
                    PathArc {
                        x: root.dropW
                        y: Math.max(root.borderT + root.filletR, root.currentDropH - root.filletR)
                        radiusX: root.filletR
                        radiusY: root.filletR
                        direction: PathArc.Counterclockwise
                    }
                    PathLine {
                        x: root.dropW
                        y: root.borderT + root.filletR
                    }
                    PathArc {
                        x: root.dropW + root.filletR
                        y: root.borderT
                        radiusX: root.filletR
                        radiusY: root.filletR
                        direction: PathArc.Clockwise
                    }
                }
            }
        }

        // ======================================
        // Bottom Popout Fused Solid Surface & Fillets
        // ======================================
        Item {
            id: bottomPopoutSurface
            x: root.dockW
            y: fusedBottomPopoutWrapper.y
            width: root.currentPopW
            height: fusedBottomPopoutWrapper.height + root.borderT
            visible: fusedBottomPopoutWrapper.offsetProgress > 0.001

            readonly property real filletFactor: Math.max(0.0, Math.min(1.0, root.currentPopW / Math.max(1, root.filletR)))

            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                visible: bottomPopoutSurface.filletFactor > 0.01
                opacity: bottomPopoutSurface.filletFactor

                // Solid Surface Fill
                ShapePath {
                    fillColor: Colors.surface
                    strokeColor: "transparent"
                    strokeWidth: 0

                    startX: -2; startY: -root.filletR
                    PathLine { x: 0; y: -root.filletR }
                    PathArc {
                        x: root.filletR
                        y: 0
                        radiusX: root.filletR
                        radiusY: root.filletR
                        direction: PathArc.Counterclockwise
                    }
                    PathLine {
                        x: Math.max(root.filletR, root.currentPopW - root.filletR)
                        y: 0
                    }
                    PathArc {
                        x: root.currentPopW
                        y: root.filletR
                        radiusX: root.filletR
                        radiusY: root.filletR
                        direction: PathArc.Clockwise
                    }
                    PathLine {
                        x: root.currentPopW
                        y: Math.max(root.filletR, fusedBottomPopoutWrapper.height - root.filletR)
                    }
                    PathArc {
                        x: Math.max(root.filletR, root.currentPopW - root.filletR)
                        y: fusedBottomPopoutWrapper.height
                        radiusX: root.filletR
                        radiusY: root.filletR
                        direction: PathArc.Clockwise
                    }
                    PathLine {
                        x: -2
                        y: fusedBottomPopoutWrapper.height
                    }
                    PathLine {
                        x: -2
                        y: -root.filletR
                    }
                }

                // Continuous 1px Gray Border Outline
                ShapePath {
                    fillColor: "transparent"
                    strokeColor: root.borderColor
                    strokeWidth: 1
                    capStyle: ShapePath.FlatCap

                    startX: 0; startY: -root.filletR
                    PathArc {
                        x: root.filletR
                        y: 0
                        radiusX: root.filletR
                        radiusY: root.filletR
                        direction: PathArc.Counterclockwise
                    }
                    PathLine {
                        x: Math.max(root.filletR, root.currentPopW - root.filletR)
                        y: 0
                    }
                    PathArc {
                        x: root.currentPopW
                        y: root.filletR
                        radiusX: root.filletR
                        radiusY: root.filletR
                        direction: PathArc.Clockwise
                    }
                    PathLine {
                        x: root.currentPopW
                        y: Math.max(root.filletR, fusedBottomPopoutWrapper.height - root.filletR)
                    }
                    PathArc {
                        x: Math.max(root.filletR, root.currentPopW - root.filletR)
                        y: fusedBottomPopoutWrapper.height
                        radiusX: root.filletR
                        radiusY: root.filletR
                        direction: PathArc.Clockwise
                    }
                }
            }
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
                if (hovered) {
                    closeTimer.stop();
                    if (Config.dashboardShowOnHover) {
                        Config.dashboardVisible = true;
                    }
                } else if (Config.dashboardVisible && !dropdownHover.hovered) {
                    closeTimer.restart();
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
        height: root.currentDropH
        visible: offsetProgress > 0.001
        clip: true

        property real offsetProgress: Config.dashboardVisible ? 1.0 : 0.0

        Behavior on offsetProgress {
            NumberAnimation {
                duration: Theme.animExpressiveDefaultSpatial
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.curveExpressiveDefaultSpatial
            }
        }

        focus: true
        Keys.onEscapePressed: Config.dashboardVisible = false

        // Robust hover tracker covering the entire dropdown
        HoverHandler {
            id: dropdownHover
            onHoveredChanged: {
                if (hovered) {
                    closeTimer.stop();
                } else if (Config.dashboardVisible && !topEdgeHover.hovered) {
                    closeTimer.restart();
                }
            }
        }

        ColumnLayout {
            id: cardLayout
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: Theme.padLarge
            anchors.topMargin: Theme.padLarge + Math.min(0, root.currentDropH - root.dropH)
            spacing: Theme.spaceMedium

                // ======================================
                // Tabs Header with Fluid Sliding Indicator
                // ======================================
                Item {
                    id: tabsHeader
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: tabsRow.implicitWidth
                    implicitHeight: 60

                    Row {
                        id: tabsRow
                        anchors.top: parent.top
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 16

                        Repeater {
                            id: tabRepeater
                            model: [
                                { id: "dashboard", label: "Dashboard", icon: "dashboard" },
                                { id: "media", label: "Media", icon: "queue_music" },
                                { id: "performance", label: "Performance", icon: "speed" },
                                { id: "workspaces", label: "Workspaces", icon: "grid_view" }
                            ]

                            delegate: Rectangle {
                                id: tabItem
                                required property var modelData
                                required property int index
                                readonly property bool isSelected: Config.activeDashboardTab === modelData.id

                                width: 175
                                height: 50
                                radius: Theme.radiusSmall
                                color: tabHover.containsMouse ? Qt.alpha(Colors.textMain, 0.04) : "transparent"

                                Behavior on color {
                                    ColorAnimation {
                                        duration: Theme.animExpressiveFastEffects
                                        easing.type: Easing.BezierSpline
                                        easing.bezierCurve: Theme.curveExpressiveFastEffects
                                    }
                                }

                                Column {
                                    anchors.centerIn: parent
                                    spacing: 3

                                    MaterialIcon {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: modelData.icon
                                        size: 20
                                        color: isSelected ? Colors.primary : (tabHover.containsMouse ? Colors.primary : Colors.onSurfaceVariant)
                                        Behavior on color {
                                            ColorAnimation { duration: Theme.animExpressiveFastEffects }
                                        }
                                    }

                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: modelData.label
                                        font.pixelSize: 12
                                        font.weight: Font.DemiBold
                                        font.family: Theme.fontFamily
                                        color: isSelected ? Colors.primary : (tabHover.containsMouse ? Colors.primary : Colors.onSurfaceVariant)
                                        Behavior on color {
                                            ColorAnimation { duration: Theme.animExpressiveFastEffects }
                                        }
                                    }
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

                    // Fluid Sliding Underline Indicator (Centered under active tab)
                    Rectangle {
                        id: tabSlidingIndicator
                        anchors.bottom: parent.bottom
                        height: 2
                        radius: 1
                        color: Colors.primary

                        readonly property int activeIdx: {
                            switch (Config.activeDashboardTab) {
                                case "dashboard": return 0;
                                case "media": return 1;
                                case "performance": return 2;
                                case "workspaces": return 3;
                                default: return 0;
                            }
                        }

                        readonly property Item activeTabItem: (tabRepeater.count > activeIdx) ? tabRepeater.itemAt(activeIdx) : null
                        readonly property real targetWidth: 60
                        readonly property real targetX: activeTabItem ? (tabsRow.x + activeTabItem.x + (activeTabItem.width - targetWidth) / 2) : 0

                        x: targetX
                        width: targetWidth

                        Behavior on x {
                            NumberAnimation {
                                duration: Theme.animExpressiveDefaultSpatial
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Theme.curveExpressiveDefaultSpatial
                            }
                        }

                        Behavior on width {
                            NumberAnimation {
                                duration: Theme.animExpressiveDefaultSpatial
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Theme.curveExpressiveDefaultSpatial
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

                // Tab Content Sliding View
                Item {
                    id: tabContentContainer
                    Layout.fillWidth: true
                    Layout.preferredHeight: implicitHeight
                    clip: true
                    implicitHeight: {
                        switch (Config.activeDashboardTab) {
                            case "dashboard": return tabPane0.implicitHeight;
                            case "media": return tabPane1.implicitHeight;
                            case "performance": return tabPane2.implicitHeight;
                            case "workspaces": return tabPane3.implicitHeight;
                            default: return tabPane0.implicitHeight;
                        }
                    }

                    Behavior on implicitHeight {
                        NumberAnimation {
                            duration: Theme.animExpressiveDefaultSpatial
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Theme.curveExpressiveDefaultSpatial
                        }
                    }

                    readonly property int activeTabIndex: {
                        switch (Config.activeDashboardTab) {
                            case "dashboard": return 0;
                            case "media": return 1;
                            case "performance": return 2;
                            case "workspaces": return 3;
                            default: return 0;
                        }
                    }

                    Item {
                        id: tabSlider
                        width: tabContentContainer.width * 4
                        height: parent.height

                        x: -tabContentContainer.activeTabIndex * tabContentContainer.width

                        Behavior on x {
                            NumberAnimation {
                                duration: Theme.animExpressiveDefaultSpatial
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Theme.curveExpressiveDefaultSpatial
                            }
                        }

                        Item {
                            id: tabPane0
                            x: 0
                            width: tabContentContainer.width
                            height: implicitHeight
                            implicitHeight: dashTab.implicitHeight

                            DashboardTab {
                                id: dashTab
                                width: parent.width
                                height: parent.height
                            }
                        }

                        Item {
                            id: tabPane1
                            x: tabContentContainer.width
                            width: tabContentContainer.width
                            height: implicitHeight
                            implicitHeight: mediaTab.implicitHeight

                            MediaTab {
                                id: mediaTab
                                width: parent.width
                                height: parent.height
                            }
                        }

                        Item {
                            id: tabPane2
                            x: tabContentContainer.width * 2
                            width: tabContentContainer.width
                            height: implicitHeight
                            implicitHeight: perfTab.implicitHeight

                            PerformanceTab {
                                id: perfTab
                                width: parent.width
                                height: parent.height
                            }
                        }

                        Item {
                            id: tabPane3
                            x: tabContentContainer.width * 3
                            width: tabContentContainer.width
                            height: implicitHeight
                            implicitHeight: wsTab.implicitHeight

                            WorkspacesTab {
                                id: wsTab
                                width: parent.width
                                height: parent.height
                            }
                        }
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

    MenuCard {
        id: appContextMenu
        visible: false
        z: 9999

        property var targetApp: null
        property real targetGlobalY: 0

        x: root.dockW + 10
        y: Math.max(12, Math.min(root.height - height - 12, targetGlobalY - 10))
        width: 220

        Behavior on y {
            NumberAnimation {
                duration: Theme.animExpressiveDefaultSpatial
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.curveExpressiveDefaultSpatial
            }
        }

        MenuHeader {
            title: appContextMenu.targetApp ? appContextMenu.targetApp.appName : ""
            subtitle: {
                if (!appContextMenu.targetApp) return "";
                if (appContextMenu.targetApp.isPinned && appContextMenu.targetApp.isRunning) return "Pinned • Running";
                if (appContextMenu.targetApp.isPinned) return "Pinned";
                return "Running (Unpinned)";
            }
            iconSource: {
                if (!appContextMenu.targetApp || !appContextMenu.targetApp.iconName) return "";
                if (appContextMenu.targetApp.iconName.indexOf("/") !== -1) {
                    return appContextMenu.targetApp.iconName.startsWith("file://") ? appContextMenu.targetApp.iconName : ("file://" + appContextMenu.targetApp.iconName);
                }
                return Quickshell.iconPath(appContextMenu.targetApp.iconName);
            }
            materialIcon: appContextMenu.targetApp ? (appContextMenu.targetApp.materialIcon || "apps") : "apps"
        }

        MenuDivider {}

        MenuItem {
            text: (appContextMenu.targetApp && appContextMenu.targetApp.isPinned) ? "Unpin from dock" : "Pin to dock"
            materialIcon: (appContextMenu.targetApp && appContextMenu.targetApp.isPinned) ? "keep_off" : "push_pin"
            checked: appContextMenu.targetApp && appContextMenu.targetApp.isPinned
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

        MenuItem {
            visible: appContextMenu.targetApp && appContextMenu.targetApp.isRunning
            text: "Close window"
            materialIcon: "close"
            isDangerous: true
            onClicked: {
                if (appContextMenu.targetApp && appContextMenu.targetApp.id) {
                    WindowService.closeWindow(appContextMenu.targetApp.id);
                }
                appContextMenu.visible = false;
            }
        }

        MenuItem {
            visible: appContextMenu.targetApp && !appContextMenu.targetApp.isRunning
            text: "Launch application"
            materialIcon: "play_arrow"
            onClicked: {
                if (appContextMenu.targetApp) {
                    WindowService.launchApp(appContextMenu.targetApp.desktopFile || appContextMenu.targetApp.appId);
                }
                appContextMenu.visible = false;
            }
        }
    }

    // ==========================================
    // 5. SYSTEM NOTIFICATIONS POPUP (TOP-RIGHT FUSED)
    // ==========================================
    NotificationPopup {
        id: sysNotifPopup
        x: root.width - width
        y: 0
        z: 9990
        borderThickness: root.borderT
        borderRounding: root.filletR
        visible: NotificationService.hasNotification
        summary: NotificationService.currentSummary
        body: NotificationService.currentBody
        appName: NotificationService.currentAppName
        materialIcon: NotificationService.currentIcon
        timeStr: NotificationService.currentTime
        onClosed: NotificationService.dismiss()
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
            spacing: 10

            // 1. App Launcher Button (Arch Linux Logo matching reference)
            Item {
                id: launcherBtn
                anchors.horizontalCenter: parent.horizontalCenter
                width: root.iconS
                height: root.iconS
                implicitWidth: root.iconS
                implicitHeight: root.iconS

                Text {
                    id: launcherIcon
                    anchors.centerIn: parent
                    text: "\uf303" // Arch Linux logo glyph
                    font.family: Theme.fontFamily
                    font.pixelSize: Math.round(root.iconS * 0.72)
                    color: launcherHover.containsMouse ? Colors.primary : Colors.primary
                    opacity: launcherHover.containsMouse ? 1.0 : 0.85
                    scale: launcherHover.pressed ? 0.9 : (launcherHover.containsMouse ? 1.12 : 1.0)

                    Behavior on scale {
                        NumberAnimation { duration: Theme.animDurationFast; easing.type: Easing.OutQuad }
                    }
                    Behavior on opacity {
                        NumberAnimation { duration: Theme.animDurationFast }
                    }
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

            // 2. Workspaces Vertical Pill with 4 Gray Dots and Active Pacman Icon
            Rectangle {
                id: wsContainer
                anchors.horizontalCenter: parent.horizontalCenter
                readonly property int wsBtnSize: 24
                readonly property int wsSpacing: 8
                readonly property int wsPad: 6
                implicitWidth: 30
                implicitHeight: (wsBtnSize + wsSpacing) * 4 - wsSpacing + wsPad * 2
                radius: Theme.radiusFull
                color: Colors.surfaceContainer
                border.color: Theme.borderSubtle
                border.width: 1

                readonly property int activeWsIndex: {
                    for (let i = 0; i < Math.min(4, KWinWorkspaces.desktops.length); i++) {
                        if (KWinWorkspaces.desktops[i].active) return i;
                    }
                    return 0;
                }

                // Asymmetric Stretch Liquid Indicator
                property real startY: 0
                property real endY: wsBtnSize

                function updateLiquidTrail() {
                    const newStart = activeWsIndex * (wsBtnSize + wsSpacing);
                    const goingUp = newStart < startY;
                    const lead = Theme.animExpressiveDefaultSpatial;
                    const trail = Math.round(lead * 1.5);

                    startAnim.stop();
                    endAnim.stop();
                    startAnim.to = newStart;
                    endAnim.to = newStart + wsBtnSize;
                    startAnim.duration = goingUp ? lead : trail;
                    endAnim.duration = goingUp ? trail : lead;
                    startAnim.start();
                    endAnim.start();
                }

                onActiveWsIndexChanged: updateLiquidTrail()
                Component.onCompleted: updateLiquidTrail()

                // Liquid Pill Graphic (Warm Primary / Terracotta capsule)
                Rectangle {
                    id: wsLiquidIndicator
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: wsContainer.startY + wsContainer.wsPad
                    width: wsContainer.wsBtnSize
                    height: Math.max(wsContainer.wsBtnSize, wsContainer.endY - wsContainer.startY)
                    radius: Theme.radiusFull
                    color: Colors.primary
                    border.color: Qt.alpha(Colors.textOnPrimary, 0.15)
                    border.width: 1
                    z: 0

                    NumberAnimation {
                        id: startAnim
                        target: wsContainer
                        property: "startY"
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Theme.curveExpressiveDefaultSpatial
                    }

                    NumberAnimation {
                        id: endAnim
                        target: wsContainer
                        property: "endY"
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Theme.curveExpressiveDefaultSpatial
                    }
                }

                Column {
                    anchors.centerIn: parent
                    spacing: wsContainer.wsSpacing
                    z: 1

                    Repeater {
                        model: [
                            { index: 0, name: "Desktop 1" },
                            { index: 1, name: "Desktop 2" },
                            { index: 2, name: "Desktop 3" },
                            { index: 3, name: "Desktop 4" }
                        ]

                        delegate: Item {
                            id: wsDelegate
                            required property var modelData
                            readonly property bool isActive: wsContainer.activeWsIndex === modelData.index
                            readonly property int itemSize: wsContainer.wsBtnSize

                            width: itemSize
                            height: itemSize
                            implicitWidth: itemSize
                            implicitHeight: itemSize

                            // Inactive State: Gray Dot Icon
                            Rectangle {
                                anchors.centerIn: parent
                                width: 6
                                height: 6
                                radius: 3
                                visible: !wsDelegate.isActive
                                color: wsHover.containsMouse ? Colors.primary : Colors.outline
                                scale: wsHover.containsMouse ? 1.3 : 1.0

                                Behavior on color {
                                    ColorAnimation { duration: Theme.animDurationFast }
                                }
                                Behavior on scale {
                                    NumberAnimation { duration: Theme.animDurationFast }
                                }
                            }

                            // Active State: Pacman SVG Icon from Lucida/Lucide
                            PacmanIcon {
                                anchors.centerIn: parent
                                visible: wsDelegate.isActive
                                size: 16
                                color: Colors.textOnPrimary
                                scale: wsDelegate.isActive ? 1.0 : 0.4
                                opacity: wsDelegate.isActive ? 1.0 : 0.0

                                Behavior on scale {
                                    NumberAnimation {
                                        duration: Theme.animDurationNormal
                                        easing.type: Easing.BezierSpline
                                        easing.bezierCurve: Theme.curveExpressiveDefaultSpatial
                                    }
                                }
                                Behavior on opacity {
                                    NumberAnimation { duration: Theme.animDurationFast }
                                }
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

                            // Tooltip
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

        // MIDDLE SECTION: Vertical Rotated Active Window / Desktop (Matching upstream Caelestia)
        Item {
            id: activeWindowPill
            anchors.top: topSection.bottom
            anchors.topMargin: 8
            anchors.horizontalCenter: parent.horizontalCenter
            implicitWidth: root.iconS + 16
            implicitHeight: Math.max(0, dockContent.height - topSection.implicitHeight - bottomCol.implicitHeight - 20)
            visible: implicitHeight >= (root.iconS + 10)

            // 1. App / Category Icon (Upright at top)
            Item {
                id: activeIconContainer
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                width: root.iconS + 4
                height: root.iconS + 4

                Image {
                    id: activeIconImg
                    anchors.centerIn: parent
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
                }

                MaterialIcon {
                    anchors.centerIn: parent
                    text: WindowService.activeMaterialIcon || "desktop_windows"
                    size: Math.round(root.iconS * 0.82)
                    color: Colors.primary
                    visible: !activeIconImg.visible || activeIconImg.status !== Image.Ready
                }
            }

            // 2. Vertical Rotated Title with Cross-fade (Matching upstream Caelestia)
            Item {
                id: activeTitleRotated
                anchors.top: activeIconContainer.bottom
                anchors.topMargin: 6
                anchors.horizontalCenter: parent.horizontalCenter
                width: 24
                height: Math.max(0, parent.height - activeIconContainer.height - 8)
                clip: true
                visible: height >= 36

                readonly property string windowTitle: WindowService.activeTitle || "Desktop"
                property bool showingFirst: true

                TextMetrics {
                    id: titleMetrics
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    font.weight: Font.Medium
                    text: activeTitleRotated.windowTitle
                    elide: Text.ElideRight
                    elideWidth: Math.max(20, activeTitleRotated.height)

                    onTextChanged: {
                        activeTitleRotated.showingFirst = !activeTitleRotated.showingFirst;
                        if (activeTitleRotated.showingFirst) {
                            titleText1.text = elidedText;
                        } else {
                            titleText2.text = elidedText;
                        }
                    }
                    onElideWidthChanged: {
                        if (activeTitleRotated.showingFirst) {
                            titleText1.text = elidedText;
                        } else {
                            titleText2.text = elidedText;
                        }
                    }
                }

                Component.onCompleted: {
                    titleText1.text = titleMetrics.elidedText;
                }

                Text {
                    id: titleText1
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    font: titleMetrics.font
                    color: Colors.textOnSurfaceVariant
                    opacity: activeTitleRotated.showingFirst ? 1.0 : 0.0
                    width: implicitHeight
                    height: implicitWidth
                    horizontalAlignment: Text.AlignLeft

                    transform: [
                        Rotation {
                            angle: 90
                            origin.x: titleText1.implicitHeight / 2
                            origin.y: titleText1.implicitHeight / 2
                        }
                    ]

                    Behavior on opacity {
                        NumberAnimation {
                            duration: Theme.animExpressiveDefaultEffects
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Theme.curveExpressiveDefaultEffects
                        }
                    }
                }

                Text {
                    id: titleText2
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    font: titleMetrics.font
                    color: Colors.textOnSurfaceVariant
                    opacity: activeTitleRotated.showingFirst ? 0.0 : 1.0
                    width: implicitHeight
                    height: implicitWidth
                    horizontalAlignment: Text.AlignLeft

                    transform: [
                        Rotation {
                            angle: 90
                            origin.x: titleText2.implicitHeight / 2
                            origin.y: titleText2.implicitHeight / 2
                        }
                    ]

                    Behavior on opacity {
                        NumberAnimation {
                            duration: Theme.animExpressiveDefaultEffects
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Theme.curveExpressiveDefaultEffects
                        }
                    }
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
                readonly property int maxAppsHeight: Math.max(120, dockContent.height - topSection.implicitHeight - 360)
                implicitHeight: Math.min(appsCol.implicitHeight + 8, maxAppsHeight)
                radius: Math.round((root.iconS + 16) * 0.25)
                color: Colors.surfaceContainer
                border.color: Theme.borderSubtle
                border.width: 1
                visible: dockContent.taskbarList.length > 0
                clip: true

                Flickable {
                    id: appsFlickable
                    anchors.fill: parent
                    anchors.topMargin: 4
                    anchors.bottomMargin: 4
                    contentWidth: width
                    contentHeight: appsCol.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true
                    interactive: contentHeight > height

                    Column {
                        id: appsCol
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: Math.max(0, (parent.height - implicitHeight) / 2)
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

                            readonly property int itemSize: root.iconS + 4

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
                                source: (modelData.rawIcon && !modelData.rawIcon.startsWith("Error")) ? Quickshell.iconPath(modelData.rawIcon) : ""
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
                                    text: (modelData.title && !modelData.title.startsWith("Error")) ? modelData.title : ((modelData.id && !modelData.id.startsWith("Error")) ? modelData.id : "Application")
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
        y: Math.max(root.borderT + 10, root.height - root.borderT - fusedPopout.implicitHeight)
        width: root.currentPopW
        height: fusedPopout.implicitHeight
        visible: offsetProgress > 0.001
        clip: true

        property real offsetProgress: Config.bottomPopoutVisible ? 1.0 : 0.0

        Behavior on offsetProgress {
            NumberAnimation {
                duration: Theme.animExpressiveDefaultSpatial
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.curveExpressiveDefaultSpatial
            }
        }

        Behavior on y {
            enabled: fusedBottomPopoutWrapper.offsetProgress > 0.01
            NumberAnimation {
                duration: Theme.animExpressiveDefaultSpatial
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.curveExpressiveDefaultSpatial
            }
        }

        Behavior on height {
            enabled: fusedBottomPopoutWrapper.offsetProgress > 0.01
            NumberAnimation {
                duration: Theme.animExpressiveDefaultSpatial
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.curveExpressiveDefaultSpatial
            }
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

        Item {
            id: popoutContentContainer
            anchors.left: parent.left
            anchors.leftMargin: (-fusedPopout.popWidth - 5) * (1.0 - fusedBottomPopoutWrapper.offsetProgress)
            anchors.top: parent.top
            width: fusedPopout.popWidth
            height: fusedPopout.implicitHeight

            FusedBottomPopout {
                id: fusedPopout
                mode: Config.bottomPopoutMode
            }
        }
    }
}
