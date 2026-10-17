import QtQuick
import "../../components/motion"
import "../../theme"
import "../../components"
import "../../services"
import "../../config"

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

    HoverHandler {
        id: groupHover
        onHoveredChanged: {
            if (hovered) {
                Config.openBottomPopout("default", root.mapToItem(null, 0, root.height / 2).y);
            } else {
                Config.scheduleCloseBottomPopout();
            }
        }
    }

    Column {
        id: layout
        anchors.centerIn: parent
        spacing: 4

        // 0. Keyboard Language Switcher
        Item {
            id: kbItem
            visible: root.isIconEnabled("kblayout")
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
                    text: (typeof KbLayoutService !== "undefined" && KbLayoutService.currentLayout)
                        ? KbLayoutService.currentLayout.substring(0, 2).toUpperCase()
                        : "US"
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
                            if (typeof KbLayoutService !== "undefined") KbLayoutService.nextLayout();
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

        // 3. Audio / Master Volume
        Item {
            id: audioItem
            visible: root.isIconEnabled("audio")
            implicitWidth: visible ? root.btnSize : 0
            implicitHeight: visible ? root.btnSize : 0
            width: implicitWidth
            height: implicitHeight

            Rectangle {
                anchors.fill: parent
                radius: Theme.radiusFull
                color: (Config.bottomPopoutVisible && Config.bottomPopoutMode === "audio") 
                    ? Colors.primary 
                    : (audioHover.hovered ? Colors.surfaceContainerHigh : "transparent")

                MaterialIcon {
                    anchors.centerIn: parent
                    text: (typeof PipewireAudio !== "undefined" && PipewireAudio.getVolumeIcon) ? PipewireAudio.getVolumeIcon() : "volume_up"
                    size: root.iconSize
                    color: (Config.bottomPopoutVisible && Config.bottomPopoutMode === "audio") 
                        ? Colors.textOnPrimary 
                        : ((typeof PipewireAudio !== "undefined" && PipewireAudio.muted) ? Colors.outline : Colors.textOnSurfaceVariant)
                }

                HoverHandler {
                    id: audioHover
                    onHoveredChanged: {
                        if (hovered) Config.openBottomPopout("audio", audioItem.mapToItem(null, 0, audioItem.height / 2).y);
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: mouse => {
                        if (mouse.button === Qt.RightButton) {
                            if (typeof PipewireAudio !== "undefined") PipewireAudio.toggleMute();
                        } else {
                            Config.openBottomPopout("audio", audioItem.mapToItem(null, 0, audioItem.height / 2).y);
                        }
                    }
                    onWheel: wheel => {
                        if (typeof PipewireAudio !== "undefined") {
                            const delta = wheel.angleDelta.y > 0 ? 0.05 : -0.05;
                            const newVol = Math.max(0.0, Math.min(1.5, PipewireAudio.volume + delta));
                            PipewireAudio.setVolume(newVol);
                            if (typeof Config !== "undefined" && Config.showVolumeOsd) {
                                Config.showVolumeOsd(newVol, PipewireAudio.muted);
                            }
                        }
                    }
                }
            }
        }

        // Display Brightness
        Item {
            id: brightnessItem
            visible: root.isIconEnabled("brightness")
            implicitWidth: visible ? root.btnSize : 0
            implicitHeight: visible ? root.btnSize : 0
            width: implicitWidth
            height: implicitHeight

            Rectangle {
                anchors.fill: parent
                radius: Theme.radiusFull
                color: (Config.bottomPopoutVisible && Config.bottomPopoutMode === "brightness")
                    ? Colors.primary
                    : (brightHover.hovered ? Colors.surfaceContainerHigh : "transparent")

                MaterialIcon {
                    anchors.centerIn: parent
                    text: (typeof BrightnessService !== "undefined" && BrightnessService.normalized < 0.5) ? "brightness_low" : "brightness_medium"
                    size: root.iconSize
                    color: (Config.bottomPopoutVisible && Config.bottomPopoutMode === "brightness")
                        ? Colors.textOnPrimary
                        : Colors.textOnSurfaceVariant
                }

                HoverHandler {
                    id: brightHover
                    onHoveredChanged: {
                        if (hovered) Config.openBottomPopout("brightness", brightnessItem.mapToItem(null, 0, brightnessItem.height / 2).y);
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: {
                        Config.openBottomPopout("brightness", brightnessItem.mapToItem(null, 0, brightnessItem.height / 2).y);
                    }
                    onWheel: wheel => {
                        if (typeof BrightnessService !== "undefined") {
                            const delta = wheel.angleDelta.y > 0 ? 0.05 : -0.05;
                            const cur = BrightnessService.normalized;
                            BrightnessService.setBrightness(Math.max(0.05, Math.min(1.0, cur + delta)));
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
            visible: root.isIconEnabled("battery") && ((typeof PowerService !== "undefined" && PowerService.hasBattery) || (typeof PowerService !== "undefined" && PowerService.batteryPercentage < 100))
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

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        Config.openBottomPopout("battery", batteryItem.mapToItem(null, 0, batteryItem.height / 2).y);
                    }
                }
            }
        }

        // 4. Power Profile / Rocket
        Item {
            id: profileItem
            implicitWidth: root.btnSize
            implicitHeight: root.btnSize
            width: root.btnSize
            height: root.btnSize

            Rectangle {
                anchors.fill: parent
                radius: Theme.radiusFull
                color: (Config.bottomPopoutVisible && Config.bottomPopoutMode === "default") 
                    ? Colors.primary 
                    : (profileHover.hovered ? Colors.surfaceContainerHigh : "transparent")

                MaterialIcon {
                    anchors.centerIn: parent
                    text: {
                        switch (PowerService.currentProfile) {
                            case "power-saver": return "energy_savings_leaf";
                            case "balanced": return "balance";
                            default: return "rocket_launch";
                        }
                    }
                    size: root.iconSize
                    color: (Config.bottomPopoutVisible && Config.bottomPopoutMode === "default") 
                        ? Colors.textOnPrimary 
                        : Colors.textOnSurfaceVariant
                }

                HoverHandler {
                    id: profileHover
                    onHoveredChanged: {
                        if (hovered) Config.openBottomPopout("default", profileItem.mapToItem(null, 0, profileItem.height / 2).y);
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                    onClicked: mouse => {
                        if (mouse.button === Qt.MiddleButton) {
                            PowerService.cycleProfile();
                        } else {
                            Config.openBottomPopout("default", profileItem.mapToItem(null, 0, profileItem.height / 2).y);
                        }
                    }
                }
            }
        }

        // 4. AI Token Quota Pill (Dynamic & Activity-Aware)
        Item {
            id: aiItem
            visible: (typeof AiTokenService !== "undefined" && AiTokenService.shouldShowPill)
                     || (typeof AiActivityService !== "undefined" && AiActivityService.isActive)
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
