import QtQuick
import "../../modules/Astral/Kernel/components/motion"
import "../../modules/Astral/Kernel/theme"
import "../../modules/Astral/Kernel/components"
import "../../modules/Astral/Kernel/services"
import "../../modules/Astral/Kernel/config"

LiquidGlassCard {
    id: root

    readonly property int btnSize: Config.dockIconSize + 2
    readonly property int iconSize: Math.round(Config.dockIconSize * 0.62)

    readonly property int vPad: 8
    implicitWidth: Config.dockIconSize + 16
    implicitHeight: layout.implicitHeight + vPad * 2
    radius: Math.round((Config.dockIconSize + 16) * 0.5)

    showBorder: !Config.bottomPopoutVisible
    showCaustic: !Config.bottomPopoutVisible
    showRefraction: !Config.bottomPopoutVisible
    showSpecular: !Config.bottomPopoutVisible
    showShadow: !Config.bottomPopoutVisible
    showBottomRim: !Config.bottomPopoutVisible
    elevation: Config.bottomPopoutVisible ? 0 : 3
    color: Config.bottomPopoutVisible ? "transparent" : Colors.glassCard

    function isIconEnabled(id) {
        if (typeof Config === "undefined" || !Config.settings || !Config.settings.dock || !Config.settings.dock.statusIcons) return true;
        const list = Config.settings.dock.statusIcons;
        for (let i = 0; i < list.length; i++) {
            if (list[i] && list[i].id === id) {
                return list[i].enabled !== false;
            }
        }
        return true;
    }

    // The status card belongs to the status pill, but the settings gear owns no
    // drawer: entering the pill directly over the gear must close the card, not
    // open it under an icon that cannot explain it.
    HoverHandler {
        id: groupHover
        onHoveredChanged: {
            if (!hovered) {
                Config.scheduleCloseBottomPopout();
                return;
            }
            const p = point.position;
            const s = settingsItem.mapToItem(root, 0, 0);
            const overSettings = p.x >= s.x && p.x <= s.x + settingsItem.width
                && p.y >= s.y && p.y <= s.y + settingsItem.height;
            if (overSettings) {
                Config.closeBottomPopout();
            } else {
                Config.openBottomPopout("default", root.mapToItem(null, 0, root.height / 2).y);
            }
        }
    }

    Column {
        id: layout
        anchors.centerIn: parent
        spacing: 4

        // 0. Input Method / Keyboard Layout Switcher
        Item {
            id: kbItem
            // The list is the session's real input methods; when neither fcitx5
            // nor KDE answers there is nothing to switch, so no dead icon.
            visible: root.isIconEnabled("kblayout")
                && (typeof InputMethodService !== "undefined" && InputMethodService.available)
            implicitWidth: visible ? root.btnSize : 0
            implicitHeight: visible ? root.btnSize : 0
            width: implicitWidth
            height: implicitHeight

            Rectangle {
                anchors.fill: parent
                radius: Theme.radiusFull
                color: (Config.bottomPopoutVisible && Config.bottomPopoutMode === "kblayout")
                    ? Colors.primary
                    : (kbHover.hovered ? Colors.surfaceContainerHigh : "transparent")

                Text {
                    anchors.centerIn: parent
                    text: (typeof InputMethodService !== "undefined") ? InputMethodService.badge : ""
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    font.weight: Font.Bold
                    color: (Config.bottomPopoutVisible && Config.bottomPopoutMode === "kblayout")
                        ? Colors.textOnPrimary
                        : Colors.textOnSurfaceVariant
                }

                HoverHandler {
                    id: kbHover
                    onHoveredChanged: {
                        if (hovered) Config.openBottomPopout("kblayout", kbItem.mapToItem(null, 0, kbItem.height / 2).y);
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: mouse => {
                        if (mouse.button === Qt.RightButton) {
                            if (typeof InputMethodService !== "undefined") InputMethodService.nextLayout();
                        } else {
                            Config.openBottomPopout("kblayout", kbItem.mapToItem(null, 0, kbItem.height / 2).y);
                        }
                    }
                }
            }
        }

        // 1. Network / Wi-Fi
        Item {
            id: netItem
            visible: root.isIconEnabled("network")
            implicitWidth: visible ? root.btnSize : 0
            implicitHeight: visible ? root.btnSize : 0
            width: implicitWidth
            height: implicitHeight

            Rectangle {
                anchors.fill: parent
                radius: Theme.radiusFull
                color: (Config.bottomPopoutVisible && Config.bottomPopoutMode === "network") 
                    ? Colors.primary 
                    : (netHover.hovered ? Colors.surfaceContainerHigh : "transparent")

                MaterialIcon {
                    anchors.centerIn: parent
                    text: NetworkService.getIcon()
                    size: root.iconSize
                    color: (Config.bottomPopoutVisible && Config.bottomPopoutMode === "network") 
                        ? Colors.textOnPrimary 
                        : Colors.textOnSurfaceVariant
                }

                HoverHandler {
                    id: netHover
                    onHoveredChanged: {
                        if (hovered) {
                            NetworkService.rescan();
                            Config.openBottomPopout("network", netItem.mapToItem(null, 0, netItem.height / 2).y);
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        NetworkService.rescan();
                        Config.openBottomPopout("network", netItem.mapToItem(null, 0, netItem.height / 2).y);
                    }
                }
            }
        }

        // 2. Bluetooth
        Item {
            id: btItem
            visible: root.isIconEnabled("bluetooth")
            implicitWidth: visible ? root.btnSize : 0
            implicitHeight: visible ? root.btnSize : 0
            width: implicitWidth
            height: implicitHeight

            Rectangle {
                anchors.fill: parent
                radius: Theme.radiusFull
                color: (Config.bottomPopoutVisible && Config.bottomPopoutMode === "bluetooth") 
                    ? Colors.primary 
                    : (btHover.hovered ? Colors.surfaceContainerHigh : "transparent")

                MaterialIcon {
                    anchors.centerIn: parent
                    text: BluetoothService.getIcon()
                    size: root.iconSize
                    color: (Config.bottomPopoutVisible && Config.bottomPopoutMode === "bluetooth") 
                        ? Colors.textOnPrimary 
                        : Colors.textOnSurfaceVariant
                }

                HoverHandler {
                    id: btHover
                    onHoveredChanged: {
                        if (hovered) Config.openBottomPopout("bluetooth", btItem.mapToItem(null, 0, btItem.height / 2).y);
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: mouse => {
                        if (mouse.button === Qt.RightButton) {
                            BluetoothService.togglePower();
                        } else {
                            Config.openBottomPopout("bluetooth", btItem.mapToItem(null, 0, btItem.height / 2).y);
                        }
                    }
                }
            }
        }

        // 4. Clipboard Manager
        Item {
            id: clipboardItem
            visible: root.isIconEnabled("clipboard")
            implicitWidth: visible ? root.btnSize : 0
            implicitHeight: visible ? root.btnSize : 0
            width: implicitWidth
            height: implicitHeight

            Rectangle {
                anchors.fill: parent
                radius: Theme.radiusFull
                color: (Config.bottomPopoutVisible && Config.bottomPopoutMode === "clipboard")
                    ? Colors.primary
                    : (clipHover.hovered ? Colors.surfaceContainerHigh : "transparent")

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "content_paste"
                    size: root.iconSize
                    color: (Config.bottomPopoutVisible && Config.bottomPopoutMode === "clipboard")
                        ? Colors.textOnPrimary
                        : Colors.textOnSurfaceVariant
                }

                HoverHandler {
                    id: clipHover
                    onHoveredChanged: {
                        if (hovered) {
                            if (typeof ClipboardService !== "undefined") ClipboardService.refresh();
                            Config.openBottomPopout("clipboard", clipboardItem.mapToItem(null, 0, clipboardItem.height / 2).y);
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: mouse => {
                        if (typeof ClipboardService !== "undefined") ClipboardService.refresh();
                        Config.openBottomPopout("clipboard", clipboardItem.mapToItem(null, 0, clipboardItem.height / 2).y);
                    }
                }
            }
        }

        // 5. Notification Center Bell
        Item {
            id: notifBellItem
            visible: root.isIconEnabled("notifications")
            implicitWidth: visible ? root.btnSize : 0
            implicitHeight: visible ? root.btnSize : 0
            width: implicitWidth
            height: implicitHeight

            readonly property int unreadCount: (typeof NotificationService !== "undefined" && NotificationService) ? NotificationService.unreadCount : 0

            Rectangle {
                anchors.fill: parent
                radius: Theme.radiusFull
                color: (Config.bottomPopoutVisible && Config.bottomPopoutMode === "notifications")
                    ? Colors.primary
                    : (notifHover.hovered ? Colors.surfaceContainerHigh : "transparent")

                MaterialIcon {
                    anchors.centerIn: parent
                    text: notifBellItem.unreadCount > 0 ? "notifications_active" : "notifications"
                    size: root.iconSize
                    color: (Config.bottomPopoutVisible && Config.bottomPopoutMode === "notifications")
                        ? Colors.textOnPrimary
                        : (notifBellItem.unreadCount > 0 ? Colors.primary : Colors.textOnSurfaceVariant)
                }

                // Subtle unread indicator dot
                Rectangle {
                    visible: notifBellItem.unreadCount > 0
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.topMargin: 4
                    anchors.rightMargin: 4
                    width: 7
                    height: 7
                    radius: 3.5
                    color: (Config.bottomPopoutVisible && Config.bottomPopoutMode === "notifications")
                        ? Colors.textOnPrimary
                        : "#FF5449"
                }

                HoverHandler {
                    id: notifHover
                    onHoveredChanged: {
                        if (hovered) {
                            Config.openBottomPopout("notifications", notifBellItem.mapToItem(null, 0, notifBellItem.height / 2).y);
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        Config.openBottomPopout("notifications", notifBellItem.mapToItem(null, 0, notifBellItem.height / 2).y);
                    }
                }
            }
        }

        // Battery Indicator
        Item {
            id: batteryItem
            // A laptop shows the battery; a desktop with power-profiles-daemon
            // still gets this slot (it renders the profile glyph via getIcon) so
            // removing the separate profile icon does not strand the switcher.
            visible: root.isIconEnabled("battery")
                && (typeof PowerService !== "undefined")
                && (PowerService.hasBattery || PowerService.hasPowerProfiles || PowerService.batteryPercentage < 100)
            implicitWidth: visible ? root.btnSize : 0
            implicitHeight: visible ? root.btnSize : 0
            width: implicitWidth
            height: implicitHeight

            Rectangle {
                anchors.fill: parent
                radius: Theme.radiusFull
                color: (Config.bottomPopoutVisible && (Config.bottomPopoutMode === "battery" || Config.bottomPopoutMode === "default"))
                    ? Colors.primary
                    : (battHover.hovered ? Colors.surfaceContainerHigh : "transparent")

                MaterialIcon {
                    anchors.centerIn: parent
                    text: (typeof PowerService !== "undefined") ? PowerService.getIcon() : "battery_full"
                    size: root.iconSize
                    color: (Config.bottomPopoutVisible && (Config.bottomPopoutMode === "battery" || Config.bottomPopoutMode === "default"))
                        ? Colors.textOnPrimary
                        : Colors.textOnSurfaceVariant
                }

                HoverHandler {
                    id: battHover
                    onHoveredChanged: {
                        if (hovered) Config.openBottomPopout("battery", batteryItem.mapToItem(null, 0, batteryItem.height / 2).y);
                    }
                }

                // One entry owns the battery + power-profile drawer. The drawer
                // itself carries the three profile pills; middle click keeps the
                // quick-switch gesture without a second, duplicate icon.
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                    onClicked: mouse => {
                        if (mouse.button === Qt.MiddleButton) {
                            if (typeof PowerService !== "undefined") PowerService.cycleProfile();
                        } else {
                            Config.openBottomPopout("battery", batteryItem.mapToItem(null, 0, batteryItem.height / 2).y);
                        }
                    }
                }
            }
        }

        // 4. AI Token Quota Pill (Dynamic & Activity-Aware)
        Item {
            id: aiItem
            // The item exists because an app declares this dock location. Quotas *and* agent
            // activity are that app's surfaces, so a disabled app shows neither — the
            // declaration decides, not a name in the dock.
            // The shell pushes "the app that owns this dock item is enabled" as a boolean
            // (`AiTokenService.appEnabled`). The dock does not ask the host itself: a relative
            // import of the Host directory is a second singleton registration with no data
            // (spec C.13), which hid the icon even while the app was enabled.
            visible: (typeof AiTokenService !== "undefined" && AiTokenService.appEnabled)
                     && ((typeof AiTokenService !== "undefined" && AiTokenService.shouldShowPill)
                         || (typeof AiActivityService !== "undefined" && AiActivityService.isActive))
            implicitWidth: visible ? root.btnSize : 0
            implicitHeight: visible ? root.btnSize : 0
            width: implicitWidth
            height: implicitHeight

            Behavior on implicitHeight { NumberAnimation { duration: Theme.animDurationNormal } }
            Behavior on opacity { NumberAnimation { duration: Theme.animDurationNormal } }
            opacity: visible ? 1.0 : 0.0

            Rectangle {
                id: aiBg
                anchors.fill: parent
                radius: Theme.radiusFull

                readonly property bool isPopActive: Config.bottomPopoutVisible && Config.bottomPopoutMode === "ai"
                readonly property string warn: typeof AiTokenService !== "undefined" ? AiTokenService.warningLevel : "normal"

                color: isPopActive
                    ? (warn === "critical" ? "#E05353" : (warn === "warning" ? "#F59E0B" : Colors.primary))
                    : (warn === "critical"
                        ? Qt.alpha("#E05353", 0.25)
                        : (warn === "warning"
                            ? Qt.alpha("#F59E0B", 0.20)
                            : (aiHover.hovered ? Colors.surfaceContainerHigh : "transparent")))

                border.color: isPopActive
                    ? "transparent"
                    : (warn === "critical"
                        ? "#E05353"
                        : (warn === "warning"
                            ? "#F59E0B"
                            : (aiHover.hovered ? Theme.borderSubtle : "transparent")))
                border.width: (warn !== "normal") ? 1.5 : 0

                // Critical-quota heartbeat. Capped by MotionPacer: the dock is always
                // on screen, so an uncapped pulse would force full-window renders at
                // display refresh (165–240 Hz) for as long as the quota stays critical.
                opacity: 1.0 - 0.4 * warnPacer.breath
                MotionPacer {
                    id: warnPacer
                    running: aiBg.warn === "critical" && !aiBg.isPopActive
                    period: 1300
                }

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "astroid"
                    size: root.iconSize
                    color: aiBg.isPopActive
                        ? Colors.textOnPrimary
                        : (aiBg.warn === "critical"
                            ? "#E05353"
                            : (aiBg.warn === "warning"
                                ? "#F59E0B"
                                : (aiHover.hovered ? Colors.primary : Colors.textOnSurfaceVariant)))
                }

                HoverHandler {
                    id: aiHover
                    onHoveredChanged: {
                        if (hovered) {
                            AiTokenService.refresh(false);
                            Config.openBottomPopout("ai", aiItem.mapToItem(null, 0, aiItem.height / 2).y);
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: mouse => {
                        if (mouse.button === Qt.RightButton) {
                            if (typeof AiTokenService !== "undefined" && AiTokenService.launchAgent) {
                                AiTokenService.launchAgent();
                            }
                        } else {
                            if (typeof AiTokenService !== "undefined") AiTokenService.refresh(false);
                            Config.openBottomPopout("ai", aiItem.mapToItem(null, 0, aiItem.height / 2).y);
                        }
                    }
                }
            }
        }

        // 5. Settings Button
        Item {
            id: settingsItem
            implicitWidth: root.btnSize
            implicitHeight: root.btnSize
            width: root.btnSize
            height: root.btnSize

            Rectangle {
                anchors.fill: parent
                radius: Theme.radiusFull
                color: (Config.settingsVisible) 
                    ? Colors.primary 
                    : (settingsHover.containsMouse ? Colors.surfaceContainerHigh : "transparent")

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "settings"
                    size: root.iconSize
                    color: (Config.settingsVisible) 
                        ? Colors.textOnPrimary 
                        : (settingsHover.containsMouse ? Colors.primary : Colors.textOnSurfaceVariant)
                }

                MouseArea {
                    id: settingsHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    // Settings opens a window, not a drawer. Entering the gear is
                    // therefore the end of whichever drawer was open - otherwise
                    // an unrelated card (e.g. AI quotas) hangs on with no context.
                    onEntered: Config.closeBottomPopout()
                    onClicked: {
                        Config.closeBottomPopout();
                        Config.toggleSettings();
                    }
                }

                // Tooltip on hover
                Rectangle {
                    z: 100
                    visible: settingsHover.containsMouse && !Config.bottomPopoutVisible && !Config.settingsVisible
                    anchors.left: parent.right
                    anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: settingsTipText.implicitWidth + 16
                    implicitHeight: settingsTipText.implicitHeight + 10
                    radius: 7
                    color: Colors.surfaceContainerHighest
                    border.color: Colors.outlineVariant
                    border.width: 1

                    Text {
                        id: settingsTipText
                        anchors.centerIn: parent
                        text: "Theme Settings"
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        color: Colors.onSurface
                    }
                }
            }
        }

        // 5. Power Button
        Item {
            id: pwrItem
            implicitWidth: root.btnSize
            implicitHeight: root.btnSize
            width: root.btnSize
            height: root.btnSize

            Rectangle {
                anchors.fill: parent
                radius: Theme.radiusFull
                color: (Config.bottomPopoutVisible && Config.bottomPopoutMode === "power") 
                    ? "#C8372D" 
                    : (pwrHover.hovered ? Colors.surfaceContainerHigh : "transparent")

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "power_settings_new"
                    size: root.iconSize
                    color: (Config.bottomPopoutVisible && Config.bottomPopoutMode === "power") 
                        ? "#FFFFFF" 
                        : "#C8372D"
                }

                HoverHandler {
                    id: pwrHover
                    onHoveredChanged: {
                        if (hovered) Config.openBottomPopout("power", pwrItem.mapToItem(null, 0, pwrItem.height / 2).y);
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Config.openBottomPopout("power", pwrItem.mapToItem(null, 0, pwrItem.height / 2).y)
                }
            }
        }
    }
}
