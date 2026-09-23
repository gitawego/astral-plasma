import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../components"
import "../../services"

ColumnLayout {
    id: root
    spacing: Theme.spaceMedium
    width: parent ? parent.width : 600

    property bool testMode: false
    property bool testWifiEnabled: true
    property string testActiveSsid: "darktalker"
    property var testNetworks: []

    readonly property bool wifiEnabled: testMode ? testWifiEnabled : ((typeof NetworkService !== "undefined") ? NetworkService.wifiEnabled : true)
    readonly property string activeSsid: testMode ? testActiveSsid : ((typeof NetworkService !== "undefined") ? NetworkService.activeSsid : "")
    readonly property var networksList: {
        if (testMode && testNetworks.length > 0) return testNetworks;
        if (typeof NetworkService !== "undefined" && NetworkService.wifiNetworks) {
            return NetworkService.wifiNetworks;
        }
        return [];
    }

    // Title & Header
    ColumnLayout {
        spacing: 4
        Text {
            text: "Network & Internet"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontTitleMedium
            font.weight: Font.Bold
            color: Colors.m3onSurface
        }
        Text {
            text: "Wi-Fi connections, signal strength & network interfaces"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontLabelSmall
            color: Colors.m3onSurfaceVariant
        }
    }

    // Wi-Fi Master Power Card
    Rectangle {
        id: masterPowerCard
        Layout.fillWidth: true
        height: 64
        radius: Theme.radiusMedium
        color: powerCardHover.containsMouse ? (root.wifiEnabled ? Qt.alpha(Colors.primary, 0.12) : Colors.surfaceContainerHigh) : Colors.surfaceContainer
        border.color: root.wifiEnabled ? Qt.alpha(Colors.primary, 0.4) : Theme.borderSubtle
        border.width: 1

        MouseArea {
            id: powerCardHover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (!root.testMode && typeof NetworkService !== "undefined") {
                    NetworkService.toggleWifi();
                } else {
                    root.testWifiEnabled = !root.testWifiEnabled;
                }
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: Theme.padLarge
            spacing: Theme.spaceMedium

            MaterialIcon {
                text: root.wifiEnabled ? "wifi" : "wifi_off"
                size: 24
                color: root.wifiEnabled ? Colors.primary : Colors.m3onSurfaceVariant
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Text {
                    text: "Wi-Fi"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontTitleSmall
                    font.weight: Font.DemiBold
                    color: Colors.m3onSurface
                }
                Text {
                    text: root.wifiEnabled ? (root.activeSsid ? "Connected to " + root.activeSsid : "Turned On (Searching...)") : "Turned Off"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontLabelSmall
                    color: Colors.m3onSurfaceVariant
                }
            }

            // Toggle switch pill
            Rectangle {
                width: 48
                height: 26
                radius: 13
                color: root.wifiEnabled ? Colors.primary : Colors.surfaceContainerHighest
                border.color: Theme.borderSubtle
                border.width: 1

                Rectangle {
                    width: 20
                    height: 20
                    radius: 10
                    anchors.verticalCenter: parent.verticalCenter
                    x: root.wifiEnabled ? parent.width - width - 3 : 3
                    color: root.wifiEnabled ? Colors.onPrimary : Colors.m3onSurfaceVariant

                    Behavior on x {
                        NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
                    }
                }
            }
        }
    }

    // Scanned Wi-Fi Networks List
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 12
        visible: root.wifiEnabled

        // Available Networks Header with Rescan Button
        RowLayout {
            Layout.fillWidth: true

            Text {
                text: "Available Networks"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontTitleSmall
                font.weight: Font.DemiBold
                color: Colors.m3onSurface
            }

            Item { Layout.fillWidth: true }

            PillButton {
                label: "Rescan"
                iconText: "refresh"
                active: false
                onClicked: {
                    if (!root.testMode && typeof NetworkService !== "undefined") {
                        NetworkService.rescan();
                    }
                }
            }
        }

        // List of deduplicated, sorted Wi-Fi cards
        Column {
            Layout.fillWidth: true
            spacing: 8

            Repeater {
                model: root.networksList
                delegate: Rectangle {
                    id: netCard
                    required property var modelData
                    required property int index

                    width: parent.width
                    height: 56
                    radius: Theme.radiusMedium
                    color: modelData.active
                        ? Qt.alpha(Colors.primary, 0.12)
                        : (cardHover.containsMouse ? Qt.alpha(Colors.onSurface, 0.05) : Colors.surfaceContainer)
                    border.color: modelData.active
                        ? Colors.primary
                        : (cardHover.containsMouse ? Qt.alpha(Colors.primary, 0.3) : Theme.borderSubtle)
                    border.width: 1

                    // Full card clickable for quick connection
                    MouseArea {
                        id: cardHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: modelData.active ? Qt.ArrowCursor : Qt.PointingHandCursor
                        onClicked: {
                            if (!modelData.active && !root.testMode && typeof NetworkService !== "undefined") {
                                NetworkService.connectToNetwork(modelData.ssid);
                            }
                        }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.padLarge
                        anchors.rightMargin: Theme.padLarge
                        spacing: Theme.spaceMedium

                        MaterialIcon {
                            text: {
                                const sig = modelData.signal || 0;
                                if (!modelData.active && sig === 0) return "wifi_off";
                                if (sig >= 75) return "wifi";
                                if (sig >= 50) return "network_wifi_3_bar";
                                if (sig >= 25) return "network_wifi_2_bar";
                                return "network_wifi_1_bar";
                            }
                            size: 22
                            color: modelData.active ? Colors.primary : Colors.m3onSurface
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Text {
                                text: modelData.ssid || "Hidden Network"
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                font.weight: modelData.active ? Font.Bold : Font.DemiBold
                                color: Colors.m3onSurface
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }

                            RowLayout {
                                spacing: 6
                                Text {
                                    text: modelData.active ? "Connected" : (modelData.security || "Open")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    font.weight: modelData.active ? Font.DemiBold : Font.Normal
                                    color: modelData.active ? Colors.primary : Colors.m3onSurfaceVariant
                                }

                                Text {
                                    text: "•  " + (modelData.signal || 0) + "%"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    color: Colors.m3onSurfaceVariant
                                }
                            }
                        }

                        // Connected indicator badge
                        RowLayout {
                            visible: modelData.active
                            spacing: 4

                            MaterialIcon {
                                text: "check"
                                size: 16
                                color: Colors.primary
                            }

                            Text {
                                text: "Connected"
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                font.weight: Font.Bold
                                color: Colors.primary
                            }
                        }

                        // Explicit Connect Button for inactive networks
                        Rectangle {
                            id: connectBtn
                            visible: !modelData.active
                            height: 28
                            implicitWidth: connLabel.implicitWidth + 24
                            radius: 14
                            color: connHover.containsMouse ? Colors.primary : Colors.surfaceContainerHighest
                            border.color: connHover.containsMouse ? Colors.primary : Theme.borderSubtle
                            border.width: 1
                            z: 10

                            Text {
                                id: connLabel
                                anchors.centerIn: parent
                                text: "Connect"
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                color: connHover.containsMouse ? Colors.onPrimary : Colors.m3onSurface
                            }

                            MouseArea {
                                id: connHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (!root.testMode && typeof NetworkService !== "undefined") {
                                        NetworkService.connectToNetwork(modelData.ssid);
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // Bottom breathing room spacer
        Item {
            Layout.fillWidth: true
            height: 32
        }
    }
}
