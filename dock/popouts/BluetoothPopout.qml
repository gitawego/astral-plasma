import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../components"
import "../../services"

Card {
    id: root

    width: 260
    height: 220
    radius: Theme.radiusLarge

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.padLarge
        spacing: Theme.spaceMedium

        // Header
        RowLayout {
            Layout.fillWidth: true

            MaterialIcon {
                text: "bluetooth"
                size: 20
                color: Colors.primary
            }

            Text {
                text: "Bluetooth"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontTitleSmall
                font.weight: Font.DemiBold
                color: Colors.m3onSurface
                Layout.fillWidth: true
            }

            PillButton {
                label: BluetoothService.powered ? "On" : "Off"
                active: BluetoothService.powered
                onClicked: BluetoothService.togglePower()
            }
        }

        // Status Card
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Theme.radiusMedium
            color: Colors.surfaceContainer

            Column {
                anchors.centerIn: parent
                spacing: Theme.spaceSmall

                MaterialIcon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: BluetoothService.getIcon()
                    size: 32
                    color: BluetoothService.powered ? Colors.primary : Colors.outline
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: BluetoothService.powered ? "Bluetooth is On" : "Bluetooth is Off"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontBodyMedium
                    color: Colors.m3onSurface
                }
            }
        }
    }
}
