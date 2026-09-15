import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../theme"
import "../config"
import "../components"
import "../services"
import "../dock/popouts"
import "../notifications"

PanelWindow {
    id: root

    required property ShellScreen targetScreen
    screen: targetScreen

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    color: "transparent"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: (dropdownContainer.offsetProgress > 0.001 || Config.bottomPopoutVisible) ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    WlrLayershell.exclusionMode: ExclusionMode.Ignore

    // Configuration and Tokens
    readonly property real borderT: Config.borderThickness
    readonly property real filletR: Config.borderRounding
    readonly property real dockW: Config.dockWidth + 6
    readonly property real iconS: Config.dockIconSize

    // Dropdown Dashboard Geometry
    readonly property real dropW: Config.dashboardWidth
    readonly property real dropH: 520
    readonly property real dropX: (root.width - root.dropW) / 2
    readonly property real currentDropH: dropdownContainer.currentDropH

    // Bottom Popout Geometry & Domain Fusion Math
    readonly property real currentPopW: (typeof fusedPopout !== "undefined" ? fusedPopout.popWidth : 280) * fusedBottomPopoutWrapper.offsetProgress
    readonly property real popoutH: (typeof fusedPopout !== "undefined" ? fusedPopout.implicitHeight : 240)

    // Domain Rules:
    // Status drawers originating from bottom dock group (Power, Battery/Profiles) or near bottom
    // clamp flush to the bottom border (root.height - root.borderT - root.popoutH) with zero gap.
    readonly property bool isPopoutFusedBottom: {
        if (Config.bottomPopoutMode === "power" || Config.bottomPopoutMode === "battery" || Config.bottomPopoutMode === "default") {
            return true;
        }
        let targetCenter = Config.popoutTargetY;
        if (targetCenter <= 0) return true;
        return (targetCenter >= root.height - root.borderT - 180) || ((targetCenter + root.popoutH / 2) >= (root.height - root.borderT - 2));
    }

    readonly property real idealPopoutY: {
        if (isPopoutFusedBottom) {
            return root.height - root.borderT - root.popoutH;
        }
        let targetCenter = Config.popoutTargetY;
        const desiredY = targetCenter - root.popoutH / 2;
        const minY = root.borderT;
        const maxY = root.height - root.borderT - root.popoutH;
        return Math.max(minY, Math.min(maxY, desiredY));
    }

    // Dynamic continuous fusion progress: 0.0 = floating, 1.0 = fused to bottom border.
    readonly property real popoutDistToBottom: Math.max(0, (root.height - root.borderT) - (fusedBottomPopoutWrapper.y + fusedBottomPopoutWrapper.height))
    readonly property real fusedProgress: isPopoutFusedBottom ? 1.0 : Math.max(0.0, Math.min(1.0, 1.0 - (popoutDistToBottom / Math.max(1, root.filletR * 2))))
    readonly property color borderColor: Theme.borderSubtle

    Component.onCompleted: {
        if (Quickshell.env("TEST_POPOUT_TARGET_Y")) {
            Config.popoutTargetY = parseFloat(Quickshell.env("TEST_POPOUT_TARGET_Y"));
        }
        const testMode = Quickshell.env("TEST_POPOUT");
        if (testMode === "default" || testMode === "bluetooth" || testMode === "network" || testMode === "power" || testMode === "clock") {
            Config.bottomPopoutMode = testMode;
            Config.bottomPopoutVisible = true;
        }
        if (Quickshell.env("TEST_DASHBOARD") === "1") {
            Config.dashboardVisible = true;
        }
        const testTab = Quickshell.env("TEST_DASHBOARD_TAB");
        if (testTab) {
            Config.activeDashboardTab = testTab;
            testTabTimer.start();
        }
    }

    Timer {
        id: testTabTimer
        interval: 200
        repeat: false
        onTriggered: {
            const testTab = Quickshell.env("TEST_DASHBOARD_TAB");
            if (testTab) Config.activeDashboardTab = testTab;
        }
    }

    // Domain Policy: Central Dropdown Dashboard Hover & Auto-Close
    readonly property bool isDashboardHovered: (dropdownContainer ? dropdownContainer.isHovered : false) || topEdgeHover.hovered

    onIsDashboardHoveredChanged: {
        if (isDashboardHovered) {
            closeTimer.stop();
        } else if (Config.dashboardVisible) {
            closeTimer.restart();
        }
    }

    Connections {
        target: Config
        function onDashboardVisibleChanged() {
            if (!Config.dashboardVisible) {
                closeTimer.stop();
            }
        }
    }

    // Auto-close grace timer when leaving the dropdown
    Timer {
        id: closeTimer
        interval: 350
        repeat: false
        onTriggered: {
            if (Quickshell.env("TEST_DASHBOARD") === "1") return;
            if (!root.isDashboardHovered) {
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
            y: fusedBottomPopoutWrapper.offsetProgress > 0.001 ? Math.max(0, fusedBottomPopoutWrapper.y - root.filletR) : 0
            width: fusedBottomPopoutWrapper.offsetProgress > 0.001 ? (root.currentPopW + root.filletR) : 0
            height: fusedBottomPopoutWrapper.offsetProgress > 0.001 ? (fusedBottomPopoutWrapper.height + root.filletR * 2 + 10) : 0
        }

        // System Notifications Popup
        Region {
            x: notifPopup.x
            y: notifPopup.y
            width: notifPopup.visible ? notifPopup.width : 0
            height: notifPopup.visible ? notifPopup.height : 0
        }
    }

    // 1. DESKTOP BORDER FRAME & INNER FILLETS
    UnifiedFrame {
        id: desktopFrame
        dockW: root.dockW
        borderT: root.borderT
        filletR: root.filletR
        borderColor: root.borderColor

        dropX: root.dropX
        dropW: root.dropW
        currentDropH: root.currentDropH
        dropdownOffsetProgress: dropdownContainer.offsetProgress

        currentPopW: root.currentPopW
        popoutY: fusedBottomPopoutWrapper.y
        popoutHeight: fusedBottomPopoutWrapper.height
        popoutOffsetProgress: fusedBottomPopoutWrapper.offsetProgress
        fusedProgress: root.fusedProgress
    }

    // 2. TOP EDGE HOVER AREA FOR CENTRAL DROPDOWN TRIGGER
    Item {
        id: topEdgeHoverArea
        x: root.dropX
        y: 0
        width: root.dropW
        height: Math.max(root.borderT, 16)
        z: 900

        HoverHandler {
            id: topEdgeHover
            onHoveredChanged: {
                if (hovered && Config.dashboardShowOnHover) {
                    closeTimer.stop();
                    Config.dashboardVisible = true;
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                Config.dashboardVisible = !Config.dashboardVisible;
                if (!Config.dashboardVisible) {
                    closeTimer.stop();
                }
            }
        }
    }

    // 3. CENTRAL DROPDOWN DASHBOARD
    CentralDropdown {
        id: dropdownContainer
        dropX: root.dropX
        dropW: root.dropW
        dropH: root.dropH
    }

    // 4. TASKBAR APP CONTEXT MENU
    AppContextMenu {
        id: appContextMenu
        dockW: root.dockW
        screenH: root.height
    }

    // 5. SYSTEM NOTIFICATIONS POPUP (TOP-RIGHT FUSED)
    NotificationPopup {
        id: notifPopup
        anchors.right: parent.right
        anchors.rightMargin: root.borderT + 12
        anchors.top: parent.top
        anchors.topMargin: root.borderT + 12
        z: 1000
    }

    // 6. LEFT DOCK CONTENT
    Item {
        id: dockArea
        visible: Config.dockEnabled
        x: 0
        y: root.borderT + 6
        width: root.dockW
        height: root.height - root.borderT * 2 - 12

        UnifiedDock {
            anchors.fill: parent
            iconS: root.iconS
            onRequestContextMenu: (app, globalY) => appContextMenu.show(app, globalY)
        }
    }

    // 7. FUSED BOTTOM POPOUT (BATTERY/PROFILES, BLUETOOTH, POWER, ETC.)
    Item {
        id: fusedBottomPopoutWrapper
        x: root.dockW
        y: root.idealPopoutY
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
