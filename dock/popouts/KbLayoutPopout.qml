import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../components"
import "../../services"

Card {
    id: root

    width: 240
    height: 160
    radius: Theme.radiusLarge

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.padLarge
        spacing: Theme.spaceMedium

        // Header
        RowLayout {
            Layout.fillWidth: true

            MaterialIcon {
                text: "language"
                size: 20
                color: Colors.primary
            }

            Text {
                text: "Keyboard Layout"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontTitleSmall
                font.weight: Font.DemiBold
                color: Colors.m3onSurface
                Layout.fillWidth: true
            }
        }

        // Active layout card
        Rectangle {
            Layout.fillWidth: true
            height: 48
            radius: Theme.radiusMedium
            color: Colors.primaryContainer

            RowLayout {
                anchors.fill: parent
                anchors.margins: Theme.padSmall

                Text {
                    text: KbLayoutService.currentLayout
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontTitleSmall
                    font.weight: Font.Bold
                    color: Colors.m3onPrimaryContainer
                    Layout.fillWidth: true
                }

                PillButton {
                    label: "Cycle"
                    onClicked: KbLayoutService.nextLayout()
                }
            }
        }
    }
}
