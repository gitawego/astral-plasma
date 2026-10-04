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

        // 1. Network / Wi-Fi
        Item {
            id: netItem
            implicitWidth: root.btnSize
            implicitHeight: root.btnSize
            width: root.btnSize
            height: root.btnSize

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
            implicitWidth: root.btnSize
            implicitHeight: root.btnSize
            width: root.btnSize
            height: root.btnSize

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
            implicitWidth: root.btnSize
            implicitHeight: root.btnSize
            width: root.btnSize
            height: root.btnSize

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
                    text: "token"
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
