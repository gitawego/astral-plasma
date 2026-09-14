import QtQuick
import QtQuick.Layouts
import "../../theme"

Rectangle {
    id: root

    property string title: ""
    property real value: 0 // current value
    property real min: 0
    property real max: 100
    property string suffix: ""
    signal valueModified(real newVal)

    radius: Theme.radiusMedium
    color: Colors.surfaceContainer
    implicitWidth: 400
    implicitHeight: 64

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.padLarge
        spacing: 4

        RowLayout {
            Layout.fillWidth: true
            Text {
                text: root.title
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontBodyMedium
                font.weight: Font.DemiBold
                color: Colors.m3onSurface
                Layout.fillWidth: true
            }
            Text {
                text: Math.round(root.value) + root.suffix
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontBodySmall
                color: Colors.primary
            }
        }

        Rectangle {
            id: track
            Layout.fillWidth: true
            height: 10
            radius: Theme.radiusFull
            color: Colors.surfaceContainerHigh

            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: parent.width * Math.max(0.0, Math.min(1.0, (root.value - root.min) / (root.max - root.min)))
                radius: Theme.radiusFull
                color: Colors.primary
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor

                function update(mouseX) {
                    const norm = Math.max(0.0, Math.min(1.0, mouseX / track.width));
                    const val = root.min + norm * (root.max - root.min);
                    root.value = val;
                    root.valueModified(val);
                }

                onPressed: mouse => update(mouse.x)
                onPositionChanged: mouse => { if (pressed) update(mouse.x); }
            }
        }
    }
}
