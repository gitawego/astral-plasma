pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import qs.theme
import qs.config
import qs.components
import qs.services

Item {
    id: root

    property string mode: "default" // "default", "bluetooth", "network", "audio", "power"
    readonly property int popWidth: 280
    implicitWidth: popWidth
    implicitHeight: popCard.implicitHeight

    Rectangle {
        id: popCard
        width: root.popWidth
        implicitHeight: contentLoader.implicitHeight + Theme.padLarge * 2
        height: implicitHeight + Config.borderThickness

        // Flush on left and bottom, rounded at top-right
        topLeftRadius: 0
        topRightRadius: Config.borderRounding
        bottomLeftRadius: 0
        bottomRightRadius: 0

        color: Colors.surface
        border.color: Theme.borderSubtle
        border.width: 1

        // Left border mask (seamless fusion with left dock)
        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 2
            color: Colors.surface
            z: 2
        }

        // Bottom border mask (seamless fusion with bottom border)
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 2
            color: Colors.surface
            z: 2
        }

        // Top-left corner mask under concave fillet
        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            width: Config.borderRounding
            height: 2
            color: Colors.surface
            z: 2
        }

        // Bottom-right corner mask under concave fillet
        Rectangle {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            width: 2
            height: Config.borderThickness + Config.borderRounding
            color: Colors.surface
            z: 2
        }

        ColumnLayout {
            id: contentLoader
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Theme.padLarge
            spacing: Theme.spaceMedium

            // ==========================================
            // 1. DEFAULT STATUS / BATTERY & POWER PROFILES (Screenshot 1)
            // ==========================================
            ColumnLayout {
                visible: root.mode === "default" || root.mode === "battery"
                Layout.fillWidth: true
                spacing: Theme.spaceMedium

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Text {
                        text: PowerService.batteryString
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontMedium
                        font.weight: Font.DemiBold
                        color: Colors.textOnSurface
                    }

                    Text {
                        text: "Power profile: " + PowerService.currentProfile.charAt(0).toUpperCase() + PowerService.currentProfile.slice(1)
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSmall
                        color: Colors.textOnSurfaceVariant
                    }
                }

                // Compact Power Profile Pill matching design
                Rectangle {
                    Layout.alignment: Qt.AlignLeft
                    implicitWidth: 124
                    implicitHeight: 32
                    radius: Theme.radiusFull
                    color: Colors.surfaceContainer
                    border.color: Theme.borderSubtle
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 2
                        spacing: 2

                        Repeater {
                            model: [
                                { id: "power-saver", icon: "energy_savings_leaf" },
                                { id: "balanced", icon: "balance" },
                                { id: "performance", icon: "rocket_launch" }
                            ]

                            delegate: Rectangle {
                                required property var modelData
                                readonly property bool isCurrent: PowerService.currentProfile === modelData.id

                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                radius: Theme.radiusFull
                                color: isCurrent ? Colors.primary : (profileHover.containsMouse ? Colors.surfaceContainerHigh : "transparent")

                                MaterialIcon {
                                    anchors.centerIn: parent
                                    text: modelData.icon
                                    size: 16
                                    color: isCurrent ? Colors.textOnPrimary : Colors.textOnSurfaceVariant
                                }

                                MouseArea {
                                    id: profileHover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: PowerService.setProfile(modelData.id)
                                }
                            }
                        }
                    }
                }
            }

            // ==========================================
            // 2. BLUETOOTH ACTIONS LIST (Screenshot 2)
            // ==========================================
            ColumnLayout {
                visible: root.mode === "bluetooth"
                Layout.fillWidth: true
                spacing: 2

                ActionItem {
                    icon: "bluetooth"
                    label: (Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.enabled) ? "Turn Bluetooth Off" : "Turn Bluetooth On"
                    onClicked: {
                        if (Bluetooth.defaultAdapter) {
                            Bluetooth.defaultAdapter.enabled = !Bluetooth.defaultAdapter.enabled;
                        } else {
                            Quickshell.execDetached(["bluetoothctl", "power", "toggle"]);
                        }
                    }
                }

                ActionItem {
                    icon: "search"
                    label: "Make Discoverable"
                    onClicked: Quickshell.execDetached(["bluetoothctl", "discoverable", "on"])
                }

                ActionDivider {}

                ActionItem {
                    icon: "send"
                    label: "Send Files to Device..."
                    onClicked: Quickshell.execDetached(["blueman-sendto"])
                }

                ActionItem {
                    icon: "history"
                    label: "Reconnect to..."
                }

                // Connected / Paired devices
                Repeater {
                    model: Bluetooth.devices ? Bluetooth.devices.values.slice(0, 3) : []

                    delegate: ActionItem {
                        required property var modelData
                        icon: "headphones"
                        iconColor: modelData.connected ? "#388E3C" : Colors.textOnSurfaceVariant
                        label: (modelData.name || modelData.address || "Audio Device")
                        onClicked: {
                            if (modelData.connected) modelData.disconnect();
                            else modelData.connect();
                        }
                    }
                }

                ActionDivider {}

                ActionItem {
                    icon: "devices"
                    label: "Devices..."
                    onClicked: Quickshell.execDetached(["blueman-manager"])
                }

                ActionItem {
                    icon: "settings"
                    label: "Adaptors..."
                    onClicked: Quickshell.execDetached(["blueman-adapters"])
                }

                ActionItem {
                    icon: "lan"
                    label: "Local Services..."
                }

                ActionDivider {}

                ActionItem {
                    icon: "extension"
                    label: "Plugins"
                }

                ActionItem {
                    icon: "help"
                    label: "Help"
                }

                ActionItem {
                    icon: "close"
                    label: "Exit"
                    onClicked: Config.activePopout = ""
                }
            }

            // ==========================================
            // 3. NETWORK / WIFI ACTIONS LIST
            // ==========================================
            ColumnLayout {
                visible: root.mode === "network"
                Layout.fillWidth: true
                spacing: 2

                ActionItem {
                    icon: "wifi"
                    label: "Wi-Fi: " + (NetworkService.connected ? NetworkService.ssid : "Disconnected")
                    onClicked: NetworkService.toggleWifi()
                }

                ActionDivider {}

                Repeater {
                    model: NetworkService.wifiNetworks ? NetworkService.wifiNetworks.slice(0, 5) : []

                    delegate: ActionItem {
                        required property var modelData
                        icon: "wifi"
                        label: modelData.ssid || "Hidden Network"
                        detail: modelData.signal + "%"
                        onClicked: NetworkService.connectToNetwork(modelData.ssid)
                    }
                }

                ActionDivider {}

                ActionItem {
                    icon: "settings"
                    label: "Network Settings..."
                    onClicked: Quickshell.execDetached(["kcmshell6", "kcm_networkmanagement"])
                }
            }

            // ==========================================
            // 4. AUDIO / VOLUME ACTIONS LIST
            // ==========================================
            ColumnLayout {
                visible: root.mode === "audio"
                Layout.fillWidth: true
                spacing: Theme.spaceMedium

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spaceSmall

                    MaterialIcon {
                        text: PipewireAudio.getVolumeIcon()
                        size: 20
                        color: Colors.primary
                    }

                    Text {
                        Layout.fillWidth: true
                        text: "Volume: " + Math.round(PipewireAudio.volume * 100) + "%"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontMedium
                        font.weight: Font.Bold
                        color: Colors.textOnSurface
                    }

                    Rectangle {
                        implicitWidth: 32
                        implicitHeight: 26
                        radius: Theme.radiusFull
                        color: PipewireAudio.muted ? Colors.primary : Colors.surfaceContainerHigh

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: PipewireAudio.muted ? "volume_off" : "volume_up"
                            size: 14
                            color: PipewireAudio.muted ? Colors.textOnPrimary : Colors.textOnSurface
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: PipewireAudio.toggleMute()
                        }
                    }
                }

                // Volume Slider Track
                Rectangle {
                    Layout.fillWidth: true
                    height: 8
                    radius: 4
                    color: Colors.surfaceContainerHigh

                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: parent.width * Math.min(1.0, Math.max(0.0, PipewireAudio.volume))
                        radius: 4
                        color: Colors.primary
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: mouse => PipewireAudio.setVolume(mouse.x / width)
                        onPositionChanged: mouse => {
                            if (pressed) PipewireAudio.setVolume(mouse.x / width);
                        }
                    }
                }

                ActionDivider {}

                ActionItem {
                    icon: "speaker"
                    label: PipewireAudio.sinkName
                }

                ActionItem {
                    icon: "settings"
                    label: "Audio Settings..."
                    onClicked: Quickshell.execDetached(["kcmshell6", "kcm_pulseaudio"])
                }
            }

            // ==========================================
            // 5. POWER ACTIONS LIST
            // ==========================================
            ColumnLayout {
                visible: root.mode === "power"
                Layout.fillWidth: true
                spacing: 2

                ActionItem {
                    icon: "lock"
                    label: "Lock Screen"
                    onClicked: PowerService.lock()
                }

                ActionItem {
                    icon: "bedtime"
                    label: "Sleep / Suspend"
                    onClicked: PowerService.suspend()
                }

                ActionDivider {}

                ActionItem {
                    icon: "restart_alt"
                    label: "Restart..."
                    onClicked: PowerService.reboot()
                }

                ActionItem {
                    icon: "power_settings_new"
                    iconColor: "#D32F2F"
                    label: "Shut Down..."
                    onClicked: PowerService.poweroff()
                }
            }
        }
    }

    // ==========================================
    // ACTION ITEM HELPER COMPONENT
    // ==========================================
    component ActionItem: Rectangle {
        id: actionRoot
        property string icon: ""
        property color iconColor: Colors.textOnSurface
        property string label: ""
        property string detail: ""
        signal clicked()

        Layout.fillWidth: true
        implicitHeight: 30
        radius: Theme.radiusSmall
        color: actionMouse.containsMouse ? Colors.surfaceContainerHigh : "transparent"

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.padSmall
            anchors.rightMargin: Theme.padSmall
            spacing: Theme.spaceSmall

            MaterialIcon {
                visible: actionRoot.icon !== ""
                text: actionRoot.icon
                size: 16
                color: actionRoot.iconColor
            }

            Text {
                Layout.fillWidth: true
                text: actionRoot.label
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSmall
                color: Colors.textOnSurface
                elide: Text.ElideRight
            }

            Text {
                visible: actionRoot.detail !== ""
                text: actionRoot.detail
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontLabelSmall
                color: Colors.textOnSurfaceVariant
            }
        }

        MouseArea {
            id: actionMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: actionRoot.clicked()
        }
    }

    // ==========================================
    // ACTION DIVIDER COMPONENT
    // ==========================================
    component ActionDivider: Rectangle {
        Layout.fillWidth: true
        height: 1
        color: Theme.borderSubtle
        Layout.topMargin: 2
        Layout.bottomMargin: 2
    }
}
