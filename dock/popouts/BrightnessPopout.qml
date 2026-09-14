import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../components"
import "../../services"

Card {
    id: root

    width: 260
    height: 140
    radius: Theme.radiusLarge

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.padLarge
        spacing: Theme.spaceMedium

        // Header
        RowLayout {
            Layout.fillWidth: true

            MaterialIcon {
                text: "brightness"
                size: 20
                color: Colors.primary
            }

            Text {
                text: "Display Brightness"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontTitleSmall
                font.weight: Font.DemiBold
                color: Colors.m3onSurface
                Layout.fillWidth: true
            }

            Text {
                text: Math.round(BrightnessService.normalized * 100) + "%"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontBodyMedium
                font.weight: Font.DemiBold
                color: Colors.primary
            }
        }

        // Brightness Slider Track
        Rectangle {
            id: sliderTrack
            Layout.fillWidth: true
            height: 12
            radius: Theme.radiusFull
            color: Colors.surfaceContainerHigh

            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: parent.width * Math.min(1.0, Math.max(0.0, BrightnessService.normalized))
                radius: Theme.radiusFull
                color: Colors.primary
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor

                function update(mouseX) {
                    const norm = Math.max(0.05, Math.min(1.0, mouseX / sliderTrack.width));
                    BrightnessService.setBrightness(norm);
                }

                onPressed: mouse => update(mouse.x)
                onPositionChanged: mouse => { if (pressed) update(mouse.x); }
            }
        }
    }
}
