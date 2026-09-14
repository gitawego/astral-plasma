import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../components"
import "../../services"

Card {
    id: root

    width: 260
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
                text: PipewireAudio.getVolumeIcon()
                size: 20
                color: Colors.primary
            }

            Text {
                text: "Volume"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontTitleSmall
                font.weight: Font.DemiBold
                color: Colors.m3onSurface
                Layout.fillWidth: true
            }

            Text {
                text: Math.round(PipewireAudio.volume * 100) + "%"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontBodyMedium
                font.weight: Font.DemiBold
                color: Colors.primary
            }
        }

        // Horizontal Volume Slider Track
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
                width: parent.width * Math.min(1.0, Math.max(0.0, PipewireAudio.volume))
                radius: Theme.radiusFull
                color: PipewireAudio.muted ? Colors.outline : Colors.primary
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor

                function update(mouseX) {
                    const norm = Math.max(0.0, Math.min(1.0, mouseX / sliderTrack.width));
                    PipewireAudio.setVolume(norm);
                }

                onPressed: mouse => update(mouse.x)
                onPositionChanged: mouse => { if (pressed) update(mouse.x); }
            }
        }

        // Mute Button & Sink Name
        RowLayout {
            Layout.fillWidth: true

            Text {
                text: PipewireAudio.sinkName
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontLabelSmall
                color: Colors.m3onSurfaceVariant
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            PillButton {
                label: PipewireAudio.muted ? "Unmute" : "Mute"
                active: PipewireAudio.muted
                onClicked: PipewireAudio.toggleMute()
            }
        }
    }
}
