import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../components"
import "../../services"

Card {
    id: root

    width: 260
    height: 150
    radius: Theme.radiusLarge

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.padLarge
        spacing: Theme.spaceMedium

        // Header
        RowLayout {
            Layout.fillWidth: true

            MaterialIcon {
                text: PowerService.getIcon()
                size: 20
                color: Colors.primary
            }

            Text {
                text: "Battery & Power"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontTitleSmall
                font.weight: Font.DemiBold
                color: Colors.m3onSurface
                Layout.fillWidth: true
            }

            Text {
                text: Math.round(PowerService.percentage * 100) + "%"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontBodyMedium
                font.weight: Font.DemiBold
                color: Colors.primary
            }
        }

        // Battery state card
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Theme.radiusMedium
            color: Colors.surfaceContainer

            RowLayout {
                anchors.centerIn: parent
                spacing: Theme.spaceSmall

                Text {
                    text: PowerService.stateString
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontBodyMedium
                    color: Colors.m3onSurface
                }
            }
        }
    }
}
