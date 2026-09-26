import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../components"
import "../../services"

Item {
    id: root

    implicitHeight: 38
    Layout.fillWidth: true

    signal chipClicked(string prompt)

    readonly property var chips: [
        { "label": "Diagnose Errors", "icon": "bug_report", "prompt": "Diagnose recent system errors and crash logs using journalctl and coredumpctl." },
        { "label": "Check High CPU", "icon": "speed", "prompt": "Check high CPU and memory processes and identify any runaway or zombie tasks." },
        { "label": "Fix Audio", "icon": "volume_up", "prompt": "Inspect PipeWire and WirePlumber status and diagnose any audio glitches or muted devices." },
        { "label": "Clean Cache", "icon": "delete", "prompt": "Check disk usage, orphaned packages, and package cache size to suggest cleanup." }
    ]

    Flickable {
        anchors.fill: parent
        contentWidth: row.implicitWidth + Theme.padLarge * 2
        contentHeight: height
        flickableDirection: Flickable.HorizontalFlick
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        RowLayout {
            id: row
            anchors.left: parent.left
            anchors.leftMargin: Theme.padLarge
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spaceSmall

            Repeater {
                model: root.chips
                delegate: Rectangle {
                    implicitHeight: 28
                    implicitWidth: chipContent.implicitWidth + 16
                    radius: 14
                    color: chipMouse.containsMouse ? Colors.glassCardHover : Colors.glassCard
                    border.width: 1
                    border.color: Colors.glassBorderSpecular

                    RowLayout {
                        id: chipContent
                        anchors.centerIn: parent
                        spacing: 6

                        MaterialIcon {
                            iconName: modelData.icon
                            size: 14
                            color: Colors.primary
                        }

                        Text {
                            text: modelData.label
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.weight: Font.Medium
                            color: Colors.m3onSurface
                        }
                    }

                    MouseArea {
                        id: chipMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (typeof AssistantService !== "undefined") {
                                AssistantService.sendMessage(modelData.prompt);
                            }
                            root.chipClicked(modelData.prompt);
                        }
                    }
                }
            }
        }
    }
}
