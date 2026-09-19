import QtQuick
import QtQuick.Layouts
import "../theme"
import "../components"

Rectangle {
    id: root
    width: 1024
    height: 570
    color: "#EBEBEB"

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 32

        // Master Liquid Glass Button matching user reference
        LiquidGlassButton {
            id: heroButton
            Layout.alignment: Qt.AlignHCenter
            text: "Get Now"
            implicitWidth: 320
            implicitHeight: 120
            paddingHorizontal: 48
            elevation: 10
        }

        // Row of functional buttons (Desktop size)
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 24

            LiquidGlassButton {
                text: "Get Now"
                implicitWidth: 160
                implicitHeight: 48
            }

            LiquidGlassButton {
                text: "Download"
                iconText: "download"
                implicitWidth: 170
                implicitHeight: 48
            }

            LiquidGlassButton {
                text: "Primary Action"
                isPrimary: true
                implicitWidth: 180
                implicitHeight: 48
            }

            PillButton {
                label: "Settings Pill"
                iconText: "settings"
                implicitHeight: 48
            }
        }
    }
}
