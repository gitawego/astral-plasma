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
    WlrLayershell.keyboardFocus: (PowerService.confirmDialogVisible || dropdownContainer.offsetProgress > 0.001 || Config.bottomPopoutVisible) ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    WlrLayershell.exclusionMode: ExclusionMode.Ignore

    // Wayland Native Compositor Backdrop Blur for Liquid Glass
    BackgroundEffect.blurRegion: Region {
        // Left Dock
        Region {
            x: 0
            y: 0
            width: Config.dockEnabled ? root.dockW : 0
            height: root.height
        }

        // Top Border
        Region {
            x: root.dockW
            y: 0
            width: root.width - root.dockW - root.borderT
            height: root.borderT
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
            x: root.dockW
            y: root.height - root.borderT
            width: root.width - root.dockW - root.borderT
            height: root.borderT
        }

        // 4 Screen Corner Fillets (curved quarter-circle blur matching CornerFillet geometry)
        // Top-Left Corner Fillet: quarter-circle in top-left (bottom-right cut out)
        Region {
            x: root.dockW
            y: root.borderT
            width: root.cornerFilletR
            height: root.cornerFilletR
            bottomRightRadius: root.cornerFilletR
        }

        // Top-Right Corner Fillet: quarter-circle in top-right (bottom-left cut out)
        Region {
            x: root.width - root.borderT - root.cornerFilletR
            y: root.borderT
            width: root.cornerFilletR
            height: root.cornerFilletR
            bottomLeftRadius: root.cornerFilletR
        }

        // Bottom-Left Corner Fillet: quarter-circle in bottom-left (top-right cut out)
        Region {
            x: root.dockW
            y: root.height - root.borderT - root.cornerFilletR
            width: root.cornerFilletR
            height: root.cornerFilletR
            topRightRadius: root.cornerFilletR
        }

        // Bottom-Right Corner Fillet: quarter-circle in bottom-right (top-left cut out)
        Region {
            x: root.width - root.borderT - root.cornerFilletR
            y: root.height - root.borderT - root.cornerFilletR
            width: root.cornerFilletR
            height: root.cornerFilletR
            topLeftRadius: root.cornerFilletR
        }

        // System Notifications Popup Blur (covers full popup + fused shoulder fillets)
        Region {
            x: (notifPopup.visible && !notifPopup.isDismissed) ? Math.max(0, root.width - notifPopup.width - root.filletR) : 0
            y: 0
            width: (notifPopup.visible && !notifPopup.isDismissed) ? (notifPopup.width + root.filletR) : 0
            height: (notifPopup.visible && !notifPopup.isDismissed) ? (notifPopup.height + root.filletR) : 0
        }

        // Left Drawer / Context Menu (when open)
        Region {
            x: (appContextMenu.menuCardVisible || trayContextMenu.menuCardVisible) ? root.dockW : 0
            y: trayContextMenu.menuCardVisible ? trayContextMenu.menuCardY : (appContextMenu.menuCardVisible ? appContextMenu.menuCardY : 0)
            width: trayContextMenu.menuCardVisible ? trayContextMenu.menuCardW : (appContextMenu.menuCardVisible ? appContextMenu.menuCardW : 0)
            height: trayContextMenu.menuCardVisible ? trayContextMenu.menuCardH : (appContextMenu.menuCardVisible ? appContextMenu.menuCardH : 0)
            topRightRadius: Theme.radiusGlassCard
            bottomRightRadius: Theme.radiusGlassCard
        }

        // Central Dropdown Dashboard (when open)
        Region {
            x: dropdownContainer.offsetProgress > 0.001 ? root.dropX : 0
            y: 0
            width: dropdownContainer.offsetProgress > 0.001 ? root.dropW : 0
            height: dropdownContainer.offsetProgress > 0.001 ? root.currentDropH : 0
            bottomLeftRadius: Theme.radiusGlassModal
            bottomRightRadius: Theme.radiusGlassModal
        }
        // Central Dropdown: Left shoulder fillet
        Region {
            x: dropdownContainer.offsetProgress > 0.001 ? (root.dropX - root.filletR) : 0
            y: dropdownContainer.offsetProgress > 0.001 ? root.borderT : 0
            width: dropdownContainer.offsetProgress > 0.001 ? root.filletR : 0
            height: dropdownContainer.offsetProgress > 0.001 ? root.filletR : 0
            bottomLeftRadius: root.filletR
        }
        // Central Dropdown: Right shoulder fillet
        Region {
            x: dropdownContainer.offsetProgress > 0.001 ? (root.dropX + root.dropW) : 0
            y: dropdownContainer.offsetProgress > 0.001 ? root.borderT : 0
            width: dropdownContainer.offsetProgress > 0.001 ? root.filletR : 0
            height: dropdownContainer.offsetProgress > 0.001 ? root.filletR : 0
            bottomRightRadius: root.filletR
        }

        // Fused Bottom Popout: Main Card Body
        Region {
            x: fusedBottomPopoutWrapper.offsetProgress > 0.001 ? root.dockW : 0
            y: fusedBottomPopoutWrapper.offsetProgress > 0.001 ? fusedBottomPopoutWrapper.y : 0
            width: fusedBottomPopoutWrapper.offsetProgress > 0.001 ? root.currentPopW : 0
            height: fusedBottomPopoutWrapper.offsetProgress > 0.001 ? fusedBottomPopoutWrapper.height : 0
            topRightRadius: Theme.radiusGlassCard
            bottomRightRadius: (root.fusedProgress > 0.5) ? 0 : Theme.radiusGlassCard
        }

        // Right Edge Control: Main Body
        Region {
            x: rightEdgeControlWrapper.offsetProgress > 0.001 ? (root.width - root.borderT - root.rightControlW) : 0
            y: rightEdgeControlWrapper.offsetProgress > 0.001 ? root.rightControlY : 0
            width: rightEdgeControlWrapper.offsetProgress > 0.001 ? root.rightControlW : 0
            height: rightEdgeControlWrapper.offsetProgress > 0.001 ? root.rightControlH : 0
            topLeftRadius: Theme.radiusGlassCard
            bottomLeftRadius: Theme.radiusGlassCard
        }
    }

    // Configuration and Tokens
    readonly property real borderT: Config.borderThickness
    readonly property real filletR: Config.borderRounding
    readonly property bool hasMaximizedWindow: (typeof WindowService !== "undefined" && WindowService && (WindowService.hasMaximizedWindow || WindowService.hasActiveMaximized)) ? true : false
    readonly property real cornerFilletR: hasMaximizedWindow ? 0 : root.filletR
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

    // Right Edge Volume/Brightness Control Geometry
    readonly property real rightControlW: 60
    readonly property real rightControlH: 280
    readonly property real rightControlY: Math.round((root.height - rightControlH) / 2)

    // Domain Rules:
    // Status drawers originating from bottom dock group (Power, Battery/Profiles) or near bottom
    // clamp flush to the bottom border (root.height - root.borderT - root.popoutH) with zero gap.
    readonly property bool isPopoutFusedBottom: {
        if (Config.bottomPopoutMode === "power" || Config.bottomPopoutMode === "battery" || Config.bottomPopoutMode === "default") {
            return true;
        }
        if (Config.bottomPopoutMode === "app") {
            return false;
        }
        let targetCenter = Config.popoutTargetY;
        if (targetCenter <= 0) return true;
        return (targetCenter >= root.height - root.borderT - 180) || ((targetCenter + root.popoutH / 2) >= (root.height - root.borderT - 2));
    }

    readonly property real popoutHeaderCenterY: {
        if (typeof fusedPopout === "undefined" || !fusedPopout) return 49.5;
        if (Config.bottomPopoutMode === "app") {
            return fusedPopout.appIconCenterY;
        }
        if (Config.bottomPopoutMode === "tray") {
            return fusedPopout.trayIconCenterY;
        }
        return root.popoutH / 2;
    }

    readonly property real idealPopoutY: {
        if (isPopoutFusedBottom) {
            return root.height - root.borderT - root.popoutH;
        }
        let targetCenter = Config.popoutTargetY;
        // For app and tray drawers, anchor the drawer header icon to the dock item center so both icons align on the exact same line.
        const headerOffsetY = (Config.bottomPopoutMode === "app" || Config.bottomPopoutMode === "tray")
            ? root.popoutHeaderCenterY
            : (root.popoutH / 2);
        const desiredY = targetCenter - headerOffsetY;
        const minY = root.borderT;
        const maxY = root.height - root.borderT - root.popoutH;
        return Math.max(minY, Math.min(maxY, desiredY));
    }

    // Fusion State Policy:
    // Only fuse once the drawer has physically arrived at the bottom border.
    // While in flight from a mid-dock icon, keep it floating to prevent premature shape deformation.
    // Once docked, latch until the user selects a floating icon (!isPopoutFusedBottom) or closes the drawer.
    readonly property real popoutDistToBottom: Math.max(0, (root.height - root.borderT) - (fusedBottomPopoutWrapper.y + fusedBottomPopoutWrapper.height))
    readonly property bool isPopoutAtBottom: isPopoutFusedBottom && Config.bottomPopoutVisible && ((fusedBottomPopoutWrapper.offsetProgress <= 0.01) || (popoutDistToBottom <= 3.0))

    property bool isFusedToBottom: isPopoutAtBottom

    onIsPopoutAtBottomChanged: {
        if (isPopoutAtBottom) {
            isFusedToBottom = true;
        } else if (!isPopoutFusedBottom || !Config.bottomPopoutVisible) {
            isFusedToBottom = false;
        }
    }

    Connections {
        target: Config
        function onBottomPopoutVisibleChanged() {
            if (!Config.bottomPopoutVisible) {
                isFusedToBottom = false;
            }
        }
        function onBottomPopoutModeChanged() {
            if (!isPopoutFusedBottom) {
                isFusedToBottom = false;
            }
        }
    }

    readonly property real fusedProgress: isFusedToBottom ? 1.0 : 0.0
    readonly property color borderColor: Colors.glassBorderSpecular

    Component.onCompleted: {
        if (Config.debugMode) {
            DebugService.log("Shell", "UnifiedShell initialized with Debug Mode active");
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
            if (Config.debugMode) return;
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

        // Right Border / Right Edge Hover Area
        Region {
            x: root.width - Math.max(root.borderT, 16)
            y: 0
            width: Math.max(root.borderT, 16)
            height: root.height
        }

        // Bottom Border
        Region {
            x: 0
            y: root.height - root.borderT
            width: root.width
            height: root.borderT
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
            y: fusedBottomPopoutWrapper.offsetProgress > 0.001 ? fusedBottomPopoutWrapper.y : 0
            width: fusedBottomPopoutWrapper.offsetProgress > 0.001 ? root.currentPopW : 0
            height: fusedBottomPopoutWrapper.offsetProgress > 0.001 ? fusedBottomPopoutWrapper.height : 0
        }

        // Right Edge Volume/Brightness Control (when open)
        Region {
            x: rightEdgeControlWrapper.offsetProgress > 0.001
                ? (root.width - root.borderT - root.rightControlW)
                : 0
            y: rightEdgeControlWrapper.offsetProgress > 0.001
                ? root.rightControlY
                : 0
            width: rightEdgeControlWrapper.offsetProgress > 0.001
                ? (root.rightControlW + root.borderT)
                : 0
            height: rightEdgeControlWrapper.offsetProgress > 0.001
                ? root.rightControlH
                : 0
        }

        // System Notifications Popup
        Region {
            x: (notifPopup.visible && !notifPopup.isDismissed) ? Math.max(0, root.width - notifPopup.width) : 0
            y: 0
            width: (notifPopup.visible && !notifPopup.isDismissed) ? notifPopup.width : 0
            height: (notifPopup.visible && !notifPopup.isDismissed) ? notifPopup.height : 0
        }

        // App Context Menu or Tray Context Menu (when open)
        Region {
            x: 0
            y: 0
            width: (appContextMenu.visible || trayContextMenu.visible) ? root.width : 0
            height: (appContextMenu.visible || trayContextMenu.visible) ? root.height : 0
        }
    }

    // 1. DESKTOP BORDER FRAME & INNER FILLETS
    UnifiedFrame {
        id: desktopFrame
        dockW: root.dockW
        borderT: root.borderT
        filletR: root.filletR
        borderColor: root.borderColor
        notifHeight: (notifPopup.visible && !notifPopup.isDismissed) ? notifPopup.height : 74

        dropX: root.dropX
        dropW: root.dropW
        currentDropH: root.currentDropH
        dropdownOffsetProgress: dropdownContainer.offsetProgress

        currentPopW: root.currentPopW
        popoutY: fusedBottomPopoutWrapper.y
        popoutHeight: fusedBottomPopoutWrapper.height
        popoutOffsetProgress: fusedBottomPopoutWrapper.offsetProgress
        fusedProgress: root.fusedProgress

        rightControlW: root.rightControlW
        rightControlH: root.rightControlH
        rightControlY: root.rightControlY
        rightControlOffsetProgress: rightEdgeControlWrapper.offsetProgress
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

    // 2b. RIGHT BORDER EDGE HOVER AREA FOR VOLUME & BRIGHTNESS TRIGGER
    Item {
        id: rightEdgeHoverArea
        x: root.width - Math.max(root.borderT, 16)
        y: 0
        width: Math.max(root.borderT, 16)
        height: root.height
        z: 900

        HoverHandler {
            id: rightEdgeHover
            onHoveredChanged: {
                if (hovered) {
                    Config.openRightEdgeControl();
                } else if (!rightEdgeControlWrapper.isHovered) {
                    Config.scheduleCloseRightEdgeControl();
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

    // 4b. SYSTEM TRAY CONTEXT MENU
    TrayContextMenu {
        id: trayContextMenu
        dockW: root.dockW
        screenH: root.height
    }

    // 5. SYSTEM NOTIFICATIONS POPUP (TOP-RIGHT FUSED)
    NotificationPopup {
        id: notifPopup
        x: Math.max(0, root.width - width)
        y: 0
        z: 1000
        visible: NotificationService.hasNotification
        summary: NotificationService.currentSummary
        body: NotificationService.currentBody
        appName: NotificationService.currentAppName
        materialIcon: NotificationService.currentIcon
        iconSource: (NotificationService.currentIcon && (NotificationService.currentIcon.indexOf("/") !== -1 || NotificationService.currentIcon.indexOf("file:") !== -1)) ? NotificationService.currentIcon : ""
        imageSource: (NotificationService.currentImage && NotificationService.currentImage.length > 0) ? NotificationService.currentImage : ((NotificationService.currentIcon && (NotificationService.currentIcon.indexOf("/") !== -1 || NotificationService.currentIcon.indexOf("file:") !== -1)) ? NotificationService.currentIcon : "")
        onClosed: {
            NotificationService.dismiss();
        }
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
            onRequestTrayContextMenu: (item, globalY) => trayContextMenu.show(item, globalY)
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

    // 8. RIGHT BORDER EDGE VOLUME & BRIGHTNESS CONTROL TAB
    Item {
        id: rightEdgeControlWrapper
        x: root.width - root.borderT - root.rightControlW * offsetProgress
        y: root.rightControlY
        width: root.rightControlW
        height: root.rightControlH
        visible: offsetProgress > 0.001
        clip: true
        z: 950

        property real offsetProgress: Config.rightEdgeControlVisible ? 1.0 : 0.0
        readonly property bool isHovered: rightControlHover.hovered

        Behavior on offsetProgress {
            NumberAnimation {
                duration: Theme.animExpressiveDefaultSpatial
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.curveExpressiveDefaultSpatial
            }
        }

        HoverHandler {
            id: rightControlHover
            onHoveredChanged: {
                if (hovered) {
                    Config.keepRightEdgeControl();
                } else if (!rightEdgeHover.hovered) {
                    Config.scheduleCloseRightEdgeControl();
                }
            }
        }

        RightEdgeControl {
            anchors.fill: parent
        }
    }

    // 9. CENTRAL TRANSLUCENT VOLUME OSD (~0.6 transparency, macOS style)
    VolumeOsd {
        id: volumeOsd
        anchors.centerIn: parent
        z: 1100
    }

    // 10. POWER CONFIRMATION DIALOG (LOGOUT / RESTART / SHUTDOWN)
    PowerConfirmDialog {
        id: powerConfirmDialog
        anchors.fill: parent
        z: 2000
    }
}
