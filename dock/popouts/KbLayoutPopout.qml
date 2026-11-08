import QtQuick
import QtQuick.Layouts
import "../../modules/Astral/Kernel/theme"
import "../../modules/Astral/Kernel/components"
import "../../modules/Astral/Kernel/services"

Card {
    id: root

    width: 280
    implicitHeight: layout.implicitHeight + Theme.padLarge * 2
    height: implicitHeight
    radius: Theme.radiusLarge

    ColumnLayout {
        id: layout
        anchors.fill: parent
        anchors.margins: Theme.padLarge
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            MaterialIcon {
                text: "keyboard"
                size: 20
                color: Colors.primary
            }

            Text {
                text: (typeof InputMethodService !== "undefined") ? InputMethodService.title : "Input Methods"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontTitleSmall
                font.weight: Font.DemiBold
                color: Colors.m3onSurface
                Layout.fillWidth: true
            }
        }

        InputMethodList {
            Layout.fillWidth: true
        }
    }
}
