import QtQuick
import QtQuick.Layouts
import "../../theme"

Rectangle {
    id: root

    property string title: ""
    property string description: ""
    property bool checked: false
    signal toggled(bool newState)

    radius: Theme.radiusMedium
    color: Colors.surfaceContainer
    implicitWidth: 400
    implicitHeight: 52

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.padLarge
        anchors.rightMargin: Theme.padLarge
        spacing: Theme.spaceMedium

        Column {
            Layout.fillWidth: true
            spacing: 2

            Text {
                text: root.title
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontBodyMedium
                font.weight: Font.DemiBold
                color: Colors.m3onSurface
            }

            Text {
                visible: root.description !== ""
                text: root.description
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontLabelSmall
                color: Colors.m3onSurfaceVariant
            }
        }

        // Toggle Switch
        Rectangle {
            width: 44
            height: 24
            radius: Theme.radiusFull
            color: root.checked ? Colors.primary : Colors.surfaceContainerHigh
            border.color: root.checked ? Colors.primary : Colors.outline
            border.width: 1

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                x: root.checked ? parent.width - width - 2 : 2
                width: 20
                height: 20
                radius: Theme.radiusFull
                color: root.checked ? Colors.m3onPrimary : Colors.outline

                Behavior on x {
                    NumberAnimation { duration: Theme.animDurationFast; easing.type: Theme.animEasing }
                }
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root.checked = !root.checked;
                    root.toggled(root.checked);
                }
            }
        }
    }
}
