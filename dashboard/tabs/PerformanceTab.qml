import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../components"
import "../../services"

Item {
    id: root

    implicitWidth: 680
    implicitHeight: 320

    readonly property alias ramCardItem: ramCard

    GridLayout {
        anchors.fill: parent
        columns: 2
        columnSpacing: (typeof Theme !== "undefined" && Theme.spaceMedium) ? Theme.spaceMedium : 12
        rowSpacing: (typeof Theme !== "undefined" && Theme.spaceMedium) ? Theme.spaceMedium : 12

        // RAM Card
        Card {
            id: ramCard
            Layout.fillWidth: true
            Layout.fillHeight: true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: (typeof Theme !== "undefined" && Theme.padLarge) ? Theme.padLarge : 16
                spacing: (typeof Theme !== "undefined" && Theme.spaceMedium) ? Theme.spaceMedium : 12

                RowLayout {
                    MaterialIcon { 
                        text: "performance"
                        size: 22
                        color: (typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#9bcbfb" 
                    }
                    Text { 
                        text: "Memory Usage"
                        font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                        font.pixelSize: (typeof Theme !== "undefined" && Theme.fontTitleSmall) ? Theme.fontTitleSmall : 14
                        font.weight: Font.DemiBold
                        color: (typeof Colors !== "undefined" && Colors.m3onSurface) ? Colors.m3onSurface : "#FFFFFF"
                        Layout.fillWidth: true 
                        style: Text.Outline
                        styleColor: Colors.glassTextHalo
                    }
                    Text { 
                        text: Math.round(((typeof SystemService !== "undefined" && SystemService.ramUsage !== undefined) ? SystemService.ramUsage : 0.45) * 100) + "%"
                        font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                        font.pixelSize: (typeof Theme !== "undefined" && Theme.fontTitleMedium) ? Theme.fontTitleMedium : 16
                        font.weight: Font.Bold
                        color: (typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#9bcbfb" 
                        style: Text.Outline
                        styleColor: Colors.glassTextHalo
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 14
                    radius: (typeof Theme !== "undefined" && Theme.radiusFull) ? Theme.radiusFull : 7
                    color: (typeof Colors !== "undefined" && Colors.surfaceContainerHigh) ? Colors.surfaceContainerHigh : Qt.rgba(1, 1, 1, 0.1)

                    Rectangle {
                        anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                        width: parent.width * ((typeof SystemService !== "undefined" && SystemService.ramUsage !== undefined) ? SystemService.ramUsage : 0.45)
                        radius: parent.radius
                        color: (typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#9bcbfb"
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
                anchors.margins: (typeof Theme !== "undefined" && Theme.padLarge) ? Theme.padLarge : 16
                spacing: (typeof Theme !== "undefined" && Theme.spaceMedium) ? Theme.spaceMedium : 12

                RowLayout {
                    MaterialIcon { 
                        text: (typeof PowerService !== "undefined" && typeof PowerService.getIcon === "function") ? PowerService.getIcon() : "battery_charging_full"
                        size: 22
                        color: (typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#9bcbfb" 
                    }
                    Text { 
                        text: "Battery Status"
                        font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                        font.pixelSize: (typeof Theme !== "undefined" && Theme.fontTitleSmall) ? Theme.fontTitleSmall : 14
                        font.weight: Font.DemiBold
                        color: (typeof Colors !== "undefined" && Colors.m3onSurface) ? Colors.m3onSurface : "#FFFFFF"
                        Layout.fillWidth: true 
                        style: Text.Outline
                        styleColor: Colors.glassTextHalo
                    }
                    Text { 
                        text: Math.round(((typeof PowerService !== "undefined" && PowerService.percentage !== undefined) ? PowerService.percentage : 1.0) * 100) + "%"
                        font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                        font.pixelSize: (typeof Theme !== "undefined" && Theme.fontTitleMedium) ? Theme.fontTitleMedium : 16
                        font.weight: Font.Bold
                        color: (typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#9bcbfb" 
                        style: Text.Outline
                        styleColor: Colors.glassTextHalo
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 14
                    radius: (typeof Theme !== "undefined" && Theme.radiusFull) ? Theme.radiusFull : 7
                    color: (typeof Colors !== "undefined" && Colors.surfaceContainerHigh) ? Colors.surfaceContainerHigh : Qt.rgba(1, 1, 1, 0.1)

                    Rectangle {
                        anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                        width: parent.width * ((typeof PowerService !== "undefined" && PowerService.percentage !== undefined) ? PowerService.percentage : 1.0)
                        radius: parent.radius
                        color: (typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#9bcbfb"
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
                anchors.margins: (typeof Theme !== "undefined" && Theme.padLarge) ? Theme.padLarge : 16
                spacing: (typeof Theme !== "undefined" && Theme.spaceMedium) ? Theme.spaceMedium : 12

                RowLayout {
                    MaterialIcon { 
                        text: (typeof PipewireAudio !== "undefined" && typeof PipewireAudio.getVolumeIcon === "function") ? PipewireAudio.getVolumeIcon() : "volume_up"
                        size: 22
                        color: (typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#9bcbfb" 
                    }
                    Text { 
                        text: "Volume Output"
                        font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                        font.pixelSize: (typeof Theme !== "undefined" && Theme.fontTitleSmall) ? Theme.fontTitleSmall : 14
                        font.weight: Font.DemiBold
                        color: (typeof Colors !== "undefined" && Colors.m3onSurface) ? Colors.m3onSurface : "#FFFFFF"
                        Layout.fillWidth: true 
                        style: Text.Outline
                        styleColor: Colors.glassTextHalo
                    }
                    Text { 
                        text: Math.round(((typeof PipewireAudio !== "undefined" && PipewireAudio.volume !== undefined) ? PipewireAudio.volume : 0.70) * 100) + "%"
                        font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                        font.pixelSize: (typeof Theme !== "undefined" && Theme.fontTitleMedium) ? Theme.fontTitleMedium : 16
                        font.weight: Font.Bold
                        color: (typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#9bcbfb" 
                        style: Text.Outline
                        styleColor: Colors.glassTextHalo
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 14
                    radius: (typeof Theme !== "undefined" && Theme.radiusFull) ? Theme.radiusFull : 7
                    color: (typeof Colors !== "undefined" && Colors.surfaceContainerHigh) ? Colors.surfaceContainerHigh : Qt.rgba(1, 1, 1, 0.1)

                    Rectangle {
                        anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                        width: parent.width * ((typeof PipewireAudio !== "undefined" && PipewireAudio.volume !== undefined) ? PipewireAudio.volume : 0.70)
                        radius: parent.radius
                        color: (typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#9bcbfb"
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
                anchors.margins: (typeof Theme !== "undefined" && Theme.padLarge) ? Theme.padLarge : 16
                spacing: (typeof Theme !== "undefined" && Theme.spaceMedium) ? Theme.spaceMedium : 12

                RowLayout {
                    MaterialIcon { 
                        text: "brightness"
                        size: 22
                        color: (typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#9bcbfb" 
                    }
                    Text { 
                        text: "Display Brightness"
                        font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                        font.pixelSize: (typeof Theme !== "undefined" && Theme.fontTitleSmall) ? Theme.fontTitleSmall : 14
                        font.weight: Font.DemiBold
                        color: (typeof Colors !== "undefined" && Colors.m3onSurface) ? Colors.m3onSurface : "#FFFFFF"
                        Layout.fillWidth: true 
                        style: Text.Outline
                        styleColor: Colors.glassTextHalo
                    }
                    Text { 
                        text: Math.round(((typeof BrightnessService !== "undefined" && BrightnessService.normalized !== undefined) ? BrightnessService.normalized : 0.80) * 100) + "%"
                        font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                        font.pixelSize: (typeof Theme !== "undefined" && Theme.fontTitleMedium) ? Theme.fontTitleMedium : 16
                        font.weight: Font.Bold
                        color: (typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#9bcbfb" 
                        style: Text.Outline
                        styleColor: Colors.glassTextHalo
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 14
                    radius: (typeof Theme !== "undefined" && Theme.radiusFull) ? Theme.radiusFull : 7
                    color: (typeof Colors !== "undefined" && Colors.surfaceContainerHigh) ? Colors.surfaceContainerHigh : Qt.rgba(1, 1, 1, 0.1)

                    Rectangle {
                        anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                        width: parent.width * ((typeof BrightnessService !== "undefined" && BrightnessService.normalized !== undefined) ? BrightnessService.normalized : 0.80)
                        radius: parent.radius
                        color: (typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#9bcbfb"
                    }
                }
            }
        }
    }
}
