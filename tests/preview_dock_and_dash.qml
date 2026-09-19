import QtQuick
import QtQuick.Layouts
import "../theme"
import "../config"
import "../components"
import "../dashboard/tabs"

Rectangle {
    id: root
    width: 1280
    height: 720
    color: "#2B4C5F"

    RowLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 32

        // Left Dock simulation showing appsContainer and wsContainer
        ColumnLayout {
            Layout.preferredWidth: 64
            Layout.fillHeight: true
            spacing: 16

            // Workspaces Pill
            LiquidGlassCard {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: 32
                implicitHeight: 140
                radius: 16

                Column {
                    anchors.centerIn: parent
                    spacing: 8
                    Repeater {
                        model: 4
                        Rectangle {
                            width: 18
                            height: 18
                            radius: 9
                            color: index === 0 ? Colors.primary : Qt.rgba(1, 1, 1, 0.4)
                        }
                    }
                }
            }

            // Apps Container (Taskbar)
            LiquidGlassCard {
                id: testAppsContainer
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: 48
                implicitHeight: 220
                radius: 24

                Column {
                    anchors.centerIn: parent
                    spacing: 10
                    Repeater {
                        model: 3
                        Rectangle {
                            width: 32
                            height: 32
                            radius: 8
                            color: index === 0 ? Colors.primaryContainer : Qt.rgba(1, 1, 1, 0.15)
                            MaterialIcon {
                                anchors.centerIn: parent
                                text: index === 0 ? "terminal" : (index === 1 ? "folder" : "settings")
                                size: 18
                                color: "#FFFFFF"
                            }
                        }
                    }
                }
            }
        }

        // Center Dashboard simulation
        LiquidGlassCard {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 20
            elevation: 12

            DashboardTab {
                anchors.fill: parent
                anchors.margins: 16
            }
        }
    }
}
