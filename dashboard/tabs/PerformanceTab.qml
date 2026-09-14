import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../components"
import "../../services"

Item {
    id: root

    implicitWidth: 680
    implicitHeight: 320

    GridLayout {
        anchors.fill: parent
        columns: 2
        columnSpacing: Theme.spaceMedium
        rowSpacing: Theme.spaceMedium

        // RAM Card
        Card {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.padLarge
                spacing: Theme.spaceMedium

                RowLayout {
                    MaterialIcon { text: "performance"; size: 22; color: Colors.primary }
                    Text { text: "Memory Usage"; font.family: Theme.fontFamily; font.pixelSize: Theme.fontTitleSmall; font.weight: Font.DemiBold; color: Colors.m3onSurface; Layout.fillWidth: true }
                    Text { text: Math.round(SystemService.ramUsage * 100) + "%"; font.family: Theme.fontFamily; font.pixelSize: Theme.fontTitleMedium; font.weight: Font.Bold; color: Colors.primary }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 14
                    radius: Theme.radiusFull
                    color: Colors.surfaceContainerHigh

                    Rectangle {
                        anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                        width: parent.width * SystemService.ramUsage
                        radius: Theme.radiusFull
                        color: Colors.primary
                    }
                }
            }
        }

        // Battery Card
        Card {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.padLarge
                spacing: Theme.spaceMedium

                RowLayout {
                    MaterialIcon { text: PowerService.getIcon(); size: 22; color: Colors.primary }
                    Text { text: "Battery Status"; font.family: Theme.fontFamily; font.pixelSize: Theme.fontTitleSmall; font.weight: Font.DemiBold; color: Colors.m3onSurface; Layout.fillWidth: true }
                    Text { text: Math.round(PowerService.percentage * 100) + "%"; font.family: Theme.fontFamily; font.pixelSize: Theme.fontTitleMedium; font.weight: Font.Bold; color: Colors.primary }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 14
                    radius: Theme.radiusFull
                    color: Colors.surfaceContainerHigh

                    Rectangle {
                        anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                        width: parent.width * PowerService.percentage
                        radius: Theme.radiusFull
                        color: Colors.primary
                    }
                }
            }
        }

        // Audio Output Card
        Card {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.padLarge
                spacing: Theme.spaceMedium

                RowLayout {
                    MaterialIcon { text: PipewireAudio.getVolumeIcon(); size: 22; color: Colors.primary }
                    Text { text: "Volume Output"; font.family: Theme.fontFamily; font.pixelSize: Theme.fontTitleSmall; font.weight: Font.DemiBold; color: Colors.m3onSurface; Layout.fillWidth: true }
                    Text { text: Math.round(PipewireAudio.volume * 100) + "%"; font.family: Theme.fontFamily; font.pixelSize: Theme.fontTitleMedium; font.weight: Font.Bold; color: Colors.primary }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 14
                    radius: Theme.radiusFull
                    color: Colors.surfaceContainerHigh

                    Rectangle {
                        anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                        width: parent.width * PipewireAudio.volume
                        radius: Theme.radiusFull
                        color: Colors.primary
                    }
                }
            }
        }

        // Brightness Card
        Card {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.padLarge
                spacing: Theme.spaceMedium

                RowLayout {
                    MaterialIcon { text: "brightness"; size: 22; color: Colors.primary }
                    Text { text: "Display Brightness"; font.family: Theme.fontFamily; font.pixelSize: Theme.fontTitleSmall; font.weight: Font.DemiBold; color: Colors.m3onSurface; Layout.fillWidth: true }
                    Text { text: Math.round(BrightnessService.normalized * 100) + "%"; font.family: Theme.fontFamily; font.pixelSize: Theme.fontTitleMedium; font.weight: Font.Bold; color: Colors.primary }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 14
                    radius: Theme.radiusFull
                    color: Colors.surfaceContainerHigh

                    Rectangle {
                        anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                        width: parent.width * BrightnessService.normalized
                        radius: Theme.radiusFull
                        color: Colors.primary
                    }
                }
            }
        }
    }
}
