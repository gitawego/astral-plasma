import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../components"
import "../../services"

ColumnLayout {
    id: root
    spacing: Theme.spaceLarge
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

    // Wi-Fi Master Toggle Card
    Rectangle {
        Layout.fillWidth: true
        height: 64
        radius: Theme.radiusMedium
        color: Colors.surfaceContainer
        border.color: Theme.borderSubtle
        border.width: 1

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

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (!root.testMode && typeof NetworkService !== "undefined") {
                            NetworkService.toggleWifi();
                        } else {
                            root.testWifiEnabled = !root.testWifiEnabled;
                        }
                    }
                }
            }
        }
    }

    // Scanned Wi-Fi Networks List
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 8
        visible: root.wifiEnabled

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

        Column {
            Layout.fillWidth: true
            spacing: 6

            Repeater {
                model: root.networksList
                delegate: Rectangle {
                    required property var modelData
                    required property int index

                    width: parent.width
                    height: 52
                    radius: Theme.radiusSmall
                    color: modelData.active ? Qt.alpha(Colors.primary, 0.15) : (netRowHover.containsMouse ? Colors.pillHover : Colors.surfaceContainer)
                    border.color: modelData.active ? Colors.primary : Theme.borderSubtle
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.padLarge
                        anchors.rightMargin: Theme.padLarge
                        spacing: Theme.spaceMedium

                        MaterialIcon {
                            text: {
                                const sig = modelData.signal || 0;
                                if (sig > 75) return "wifi";
                                if (sig > 45) return "network_wifi_3_bar";
                                return "network_wifi_1_bar";
                            }
                            size: 20
                            color: modelData.active ? Colors.primary : Colors.m3onSurfaceVariant
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            Text {
                                text: modelData.ssid || "Hidden Network"
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                font.weight: modelData.active ? Font.Bold : Font.DemiBold
                                color: Colors.m3onSurface
                            }
                            Text {
                                text: modelData.active ? "Connected" : (modelData.security || "Open")
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                color: modelData.active ? Colors.primary : Colors.m3onSurfaceVariant
                            }
                        }

                        // Connect button if not currently active
                        Rectangle {
                            visible: !modelData.active
                            height: 28
                            implicitWidth: connLabel.implicitWidth + 20
                            radius: 14
                            color: connHover.containsMouse ? Colors.primary : Colors.surfaceContainerHighest
                            border.color: Theme.borderSubtle
                            border.width: 1

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

                    MouseArea {
                        id: netRowHover
                        anchors.fill: parent
                        hoverEnabled: true
                    }
                }
            }
        }
    }
}
