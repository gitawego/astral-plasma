import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../components"
import "../../services"
import "../../config"

Card {
    id: root

    width: 280
    height: 320
    radius: Theme.radiusLarge

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.padLarge
        spacing: Theme.spaceMedium

        // Header
        RowLayout {
            Layout.fillWidth: true

            MaterialIcon {
                text: "wifi"
                size: 20
                color: Colors.primary
            }

            Text {
                text: "Wi-Fi Networks"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontTitleSmall
                font.weight: Font.DemiBold
                color: Colors.m3onSurface
                Layout.fillWidth: true
            }

            PillButton {
                label: NetworkService.wifiEnabled ? "On" : "Off"
                active: NetworkService.wifiEnabled
                onClicked: NetworkService.toggleWifi()
            }
        }

        // Active Connection
        Rectangle {
            Layout.fillWidth: true
            height: 44
            radius: Theme.radiusMedium
            color: Colors.primaryContainer
            visible: NetworkService.connected && NetworkService.activeSsid !== ""

            RowLayout {
                anchors.fill: parent
                anchors.margins: Theme.padSmall

                MaterialIcon {
                    text: "wifi"
                    size: 18
                    color: Colors.m3onPrimaryContainer
                }

                Column {
                    Layout.fillWidth: true
                    Text {
                        text: NetworkService.activeSsid
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontBodyMedium
                        font.weight: Font.DemiBold
                        color: Colors.m3onPrimaryContainer
                    }
                    Text {
                        text: "Connected • " + NetworkService.signalStrength + "%"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontLabelSmall
                        color: Colors.m3onPrimaryContainer
                    }
                }
            }
        }

        // Scanned Network List
        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: NetworkService.scannedNetworks

            delegate: Rectangle {
                width: ListView.view.width
                height: 38
                radius: Theme.radiusSmall
                color: itemMouse.containsMouse ? Colors.pillHover : "transparent"

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.padSmall
                    anchors.rightMargin: Theme.padSmall

                    Text {
                        text: modelData.ssid
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontBodySmall
                        color: Colors.m3onSurface
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }

                    Text {
                        text: modelData.signal + "%"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontLabelSmall
                        color: Colors.m3onSurfaceVariant
                    }
                }

                MouseArea {
                    id: itemMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                }
            }
        }

        // Rescan button
        PillButton {
            Layout.fillWidth: true
            label: "Rescan"
            iconText: "search"
            onClicked: NetworkService.rescan()
        }
    }
}
