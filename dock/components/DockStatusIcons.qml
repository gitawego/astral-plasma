import QtQuick
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
                    onClicked: Config.openBottomPopout("bluetooth", btItem.mapToItem(null, 0, btItem.height / 2).y)
                }
            }
        }

        // 3. Power Profile / Rocket
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
                    onClicked: Config.openBottomPopout("default", profileItem.mapToItem(null, 0, profileItem.height / 2).y)
                }
            }
        }

        // 4. AI Token Quota Pill (Dynamic & Activity-Aware)
        Item {
            id: aiItem
            visible: (typeof AiTokenService !== "undefined" && AiTokenService.shouldShowPill)
                     || (typeof AiActivityService !== "undefined" && (AiActivityService.isActive || (Config.modelActivityEffect && AiActivityService.displayName !== "AI Agent")))
            implicitWidth: visible ? root.btnSize : 0
            implicitHeight: visible ? root.btnSize : 0
            width: implicitWidth
            height: implicitHeight

            Behavior on implicitHeight { NumberAnimation { duration: Theme.animDurationNormal } }
            Behavior on opacity { NumberAnimation { duration: Theme.animDurationNormal } }
            opacity: visible ? 1.0 : 0.0

            // Breathing Specular Halo for AI Model Activity
            Rectangle {
                id: aiAura
                anchors.centerIn: parent
                width: parent.width + 8
                height: parent.height + 8
                radius: Theme.radiusFull
                z: -1
                visible: Config.modelActivityEffect && (typeof AiActivityService !== "undefined") && (AiActivityService.isActive || opacity > 0.01)
                color: (typeof AiActivityService !== "undefined" && AiActivityService.brandColor)
                    ? Qt.alpha(AiActivityService.brandColor, 0.35)
                    : Qt.alpha(Colors.primary, 0.35)
                opacity: (typeof AiActivityService !== "undefined" && AiActivityService.isActive)
                    ? (0.25 + (auraPulse * 0.50))
                    : 0.0

                Behavior on opacity {
                    NumberAnimation { duration: 4000; easing.type: Easing.OutQuad } // 4s smooth fade
                }

                property real auraPulse: 0.0

                SequentialAnimation on auraPulse {
                    running: Config.modelActivityEffect && (typeof AiActivityService !== "undefined") && AiActivityService.isActive
                    loops: Animation.Infinite
                    NumberAnimation { to: 1.0; duration: (typeof AiActivityService !== "undefined") ? Math.round(AiActivityService.pulseDuration / 2) : 1000; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 0.0; duration: (typeof AiActivityService !== "undefined") ? Math.round(AiActivityService.pulseDuration / 2) : 1000; easing.type: Easing.InOutSine }
                }
            }

            Rectangle {
                id: aiBg
                anchors.fill: parent
                radius: Theme.radiusFull

                readonly property bool isPopActive: Config.bottomPopoutVisible && Config.bottomPopoutMode === "ai"
                readonly property string warn: typeof AiTokenService !== "undefined" ? AiTokenService.warningLevel : "normal"
                readonly property bool hasModelActivity: typeof AiActivityService !== "undefined" && Config.modelActivityEffect && AiActivityService.isActive

                color: isPopActive
                    ? (warn === "critical" ? "#E05353" : (warn === "warning" ? "#F59E0B" : Colors.primary))
                    : (warn === "critical"
                        ? Qt.alpha("#E05353", 0.25)
                        : (warn === "warning"
                            ? Qt.alpha("#F59E0B", 0.20)
                            : (hasModelActivity
                                ? Qt.alpha(AiActivityService.brandColor, 0.18)
                                : (aiHover.hovered ? Colors.surfaceContainerHigh : "transparent"))))

                border.color: isPopActive
                    ? "transparent"
                    : (warn === "critical"
                        ? "#E05353"
                        : (warn === "warning"
                            ? "#F59E0B"
                            : (hasModelActivity
                                ? Qt.alpha(AiActivityService.brandColor, 0.60)
                                : (aiHover.hovered ? Theme.borderSubtle : "transparent"))))
                border.width: (warn !== "normal" || hasModelActivity) ? 1.5 : 0

                SequentialAnimation on opacity {
                    running: aiBg.warn === "critical" && !aiBg.isPopActive
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.6; duration: 650; easing.type: Easing.InOutQuad }
                    NumberAnimation { to: 1.0; duration: 650; easing.type: Easing.InOutQuad }
                }

                readonly property string activeAiIcon: (typeof AiActivityService !== "undefined" && Config.modelActivityEffect && AiActivityService.brandIcon && AiActivityService.displayName !== "AI Agent")
                    ? AiActivityService.brandIcon
                    : "auto_awesome"

                MaterialIcon {
                    anchors.centerIn: parent
                    text: aiBg.activeAiIcon
                    size: root.iconSize
                    color: aiBg.isPopActive
                        ? Colors.textOnPrimary
                        : (aiBg.warn === "critical"
                            ? "#E05353"
                            : (aiBg.warn === "warning"
                                ? "#F59E0B"
                                : (aiBg.hasModelActivity
                                    ? AiActivityService.brandColor
                                    : (aiHover.hovered ? Colors.primary : Colors.textOnSurfaceVariant))))
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
                    onClicked: {
                        AiTokenService.refresh(false);
                        Config.openBottomPopout("ai", aiItem.mapToItem(null, 0, aiItem.height / 2).y);
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
