import "../../modules/Astral/Kernel/components"
import "../../modules/Astral/Kernel/services"
import "../../modules/Astral/Kernel/theme"
import QtQuick
import QtQuick.Layouts

SettingsPage {
    id: root

    property bool testMode: false
    property bool testPowered: true
    property var testDevices: []
    readonly property bool powered: testMode ? testPowered : ((typeof BluetoothService !== "undefined") ? BluetoothService.powered : true)
    readonly property var devicesList: {
        if (testMode && testDevices.length > 0)
            return testDevices;

        if (typeof BluetoothService !== "undefined" && BluetoothService.devices)
            return BluetoothService.devices;

        return [];
    }

    // The devices tab exists only while Bluetooth is on: there is no device list
    // to show on a powered-off adapter.
    function tabList() {
        const tabs = [{
            "id": "power",
            "label": "Power",
            "icon": "bluetooth"
        }];
        if (root.powered)
            tabs.push({
                "id": "devices",
                "label": "Devices",
                "icon": "devices"
            });

        return tabs;
    }

    spacing: Theme.spaceLarge
    width: parent ? parent.width : 600
    title: "Bluetooth"
    subtitle: "Manage wireless peripherals, keyboards, audio devices & pairing"
    icon: "bluetooth"
    tabs: root.tabList()

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Theme.spaceLarge
        visible: root.currentTab === "power"

        // Bluetooth Master Power Card
        Rectangle {
            id: masterPowerCard

            Layout.fillWidth: true
            height: 64
            radius: Theme.radiusMedium
            color: powerCardHover.containsMouse ? (root.powered ? Qt.alpha(Colors.primary, 0.12) : Colors.surfaceContainerHigh) : Colors.surfaceContainer
            border.color: root.powered ? Qt.alpha(Colors.primary, 0.4) : Theme.borderSubtle
            border.width: 1

            MouseArea {
                id: powerCardHover

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (!root.testMode && typeof BluetoothService !== "undefined")
                        BluetoothService.togglePower();
                    else
                        root.testPowered = !root.testPowered;
                }
            }

            RowLayout {
                anchors.fill: parent
                anchors.margins: Theme.padLarge
                spacing: Theme.spaceMedium

                MaterialIcon {
                    text: root.powered ? "bluetooth" : "bluetooth_disabled"
                    size: 24
                    color: root.powered ? Colors.primary : Colors.m3onSurfaceVariant
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        text: "Bluetooth"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontTitleSmall
                        font.weight: Font.DemiBold
                        color: Colors.m3onSurface
                    }

                    Text {
                        text: root.powered ? "Discoverable as Astral Plasma Desktop" : "Turned Off"
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
                    color: root.powered ? Colors.primary : Colors.surfaceContainerHighest
                    border.color: Theme.borderSubtle
                    border.width: 1

                    Rectangle {
                        width: 20
                        height: 20
                        radius: 10
                        anchors.verticalCenter: parent.verticalCenter
                        x: root.powered ? parent.width - width - 3 : 3
                        color: root.powered ? Colors.onPrimary : Colors.m3onSurfaceVariant

                        Behavior on x {
                            NumberAnimation {
                                duration: 150
                                easing.type: Easing.OutQuad
                            }

                        }

                    }

                }

            }

        }

    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Theme.spaceLarge
        visible: root.currentTab === "devices"

        // Paired Devices List
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: root.powered

            SectionHeader {
                id: devicesHeader

                title: "Paired Devices"
                eyebrow: root.devicesList.length === 0 ? "nothing paired yet" : (root.devicesList.length + (root.devicesList.length === 1 ? " device" : " devices"))
            }

            Column {
                Layout.fillWidth: true
                spacing: 6

                Repeater {
                    model: root.devicesList

                    delegate: Rectangle {
                        required property var modelData
                        required property int index

                        width: parent.width
                        height: 52
                        radius: Theme.radiusSmall
                        color: modelData.connected ? Qt.alpha(Colors.primary, 0.15) : (devRowHover.containsMouse ? Colors.pillHover : Colors.surfaceContainer)
                        border.color: modelData.connected ? Colors.primary : Theme.borderSubtle
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.padLarge
                            anchors.rightMargin: Theme.padLarge
                            spacing: Theme.spaceMedium

                            MaterialIcon {
                                text: {
                                    const n = (modelData.name || "").toLowerCase();
                                    if (n.includes("key") || n.includes("pop"))
                                        return "keyboard";

                                    if (n.includes("mouse"))
                                        return "mouse";

                                    if (n.includes("stadia") || n.includes("pad") || n.includes("game"))
                                        return "sports_esports";

                                    if (n.includes("head") || n.includes("ear") || n.includes("buds"))
                                        return "headphones";

                                    return "bluetooth";
                                }
                                size: 20
                                color: modelData.connected ? Colors.primary : Colors.m3onSurfaceVariant
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1

                                Text {
                                    text: modelData.name || modelData.address || "Bluetooth Device"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 13
                                    font.weight: modelData.connected ? Font.Bold : Font.DemiBold
                                    color: Colors.m3onSurface
                                }

                                Text {
                                    text: modelData.connected ? "Connected" : "Paired"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    color: modelData.connected ? Colors.primary : Colors.m3onSurfaceVariant
                                }

                            }

                            // Connect / Disconnect Action
                            Rectangle {
                                height: 28
                                implicitWidth: actionLabel.implicitWidth + 20
                                radius: 14
                                color: actionHover.containsMouse ? (modelData.connected ? Colors.errorContainer : Colors.primary) : Colors.surfaceContainerHighest
                                border.color: Theme.borderSubtle
                                border.width: 1

                                Text {
                                    id: actionLabel

                                    anchors.centerIn: parent
                                    text: modelData.connected ? "Disconnect" : "Connect"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    color: actionHover.containsMouse ? (modelData.connected ? Colors.onErrorContainer : Colors.onPrimary) : Colors.m3onSurface
                                }

                                MouseArea {
                                    id: actionHover

                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        const addr = modelData.mac || modelData.address || "";
                                        if (modelData.connected) {
                                            if (modelData.disconnect)
                                                modelData.disconnect();
                                            else if (typeof BluetoothService !== "undefined")
                                                BluetoothService.disconnectDevice(addr);
                                        } else {
                                            if (modelData.connect)
                                                modelData.connect();
                                            else if (typeof BluetoothService !== "undefined")
                                                BluetoothService.connectDevice(addr);
                                        }
                                    }
                                }

                            }

                        }

                        MouseArea {
                            id: devRowHover

                            anchors.fill: parent
                            hoverEnabled: true
                        }

                    }

                }

            }

        }

    }

}
