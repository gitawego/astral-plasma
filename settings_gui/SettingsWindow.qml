import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../theme"
import "../components"
import "../config"
import "pages"

PanelWindow {
    id: root

    property ShellScreen targetScreen: Quickshell.screens[0]
    screen: targetScreen

    visible: Config.settingsVisible

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    color: Qt.rgba(0, 0, 0, 0.35) // Dim background overlay

    // Click backdrop to close
    MouseArea {
        anchors.fill: parent
        onClicked: Config.settingsVisible = false
    }

    // Modal dialog box
    Rectangle {
        id: dialogBox
        anchors.centerIn: parent
        width: 760
        height: 540
        radius: Theme.radiusLarge
        color: Colors.surface
        border.color: Theme.borderSubtle
        border.width: 1

        // Consume clicks inside dialog
        MouseArea {
            anchors.fill: parent
            onClicked: {}
        }

        // Top-right Close Button
        Rectangle {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: Theme.padMedium
            width: 32
            height: 32
            radius: 16
            color: closeMouseArea.containsMouse ? Colors.pillHover : "transparent"
            z: 200

            MaterialIcon {
                anchors.centerIn: parent
                text: "close"
                size: 18
                color: Colors.m3onSurfaceVariant
            }

            MouseArea {
                id: closeMouseArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Config.settingsVisible = false
            }
        }

        RowLayout {
            anchors.fill: parent
            spacing: 0

            // Left Navigation Sidebar
            Rectangle {
                Layout.preferredWidth: 200
                Layout.fillHeight: true
                radius: Theme.radiusLarge
                color: Colors.surfaceContainer

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.padLarge
                    spacing: Theme.spaceSmall

                    // Title
                    RowLayout {
                        spacing: Theme.spaceSmall
                        MaterialIcon { text: "settings"; size: 22; color: Colors.primary }
                        Text {
                            text: "Settings"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontTitleMedium
                            font.weight: Font.Bold
                            color: Colors.m3onSurface
                        }
                    }

                    Item { height: 12 }

                    // Navigation buttons
                    Column {
                        Layout.fillWidth: true
                        spacing: 4

                        PillButton {
                            width: parent.width
                            label: "Dock & Layout"
                            iconText: "dashboard"
                            active: Config.activeSettingsPage === "dock"
                            onClicked: Config.activeSettingsPage = "dock"
                        }
                        PillButton {
                            width: parent.width
                            label: "Status Icons"
                            iconText: "wifi"
                            active: Config.activeSettingsPage === "status"
                            onClicked: Config.activeSettingsPage = "status"
                        }
                        PillButton {
                            width: parent.width
                            label: "Appearance"
                            iconText: "weather_clear"
                            active: Config.activeSettingsPage === "theme"
                            onClicked: Config.activeSettingsPage = "theme"
                        }
                        PillButton {
                            width: parent.width
                            label: "Dashboard"
                            iconText: "calendar"
                            active: Config.activeSettingsPage === "dashboard"
                            onClicked: Config.activeSettingsPage = "dashboard"
                        }
                        PillButton {
                            width: parent.width
                            label: "System & Services"
                            iconText: "memory"
                            active: Config.activeSettingsPage === "system"
                            onClicked: Config.activeSettingsPage = "system"
                        }
                    }

                    Item { Layout.fillHeight: true }

                    Text {
                        Layout.fillWidth: true
                        text: "All changes apply live"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontLabelSmall
                        color: Colors.m3onSurfaceVariant
                        horizontalAlignment: Text.AlignHCenter
                    }

                    // Close button
                    PillButton {
                        Layout.fillWidth: true
                        label: "Close"
                        iconText: "close"
                        active: false
                        onClicked: {
                            Config.settingsVisible = false;
                        }
                    }
                }
            }

            // Right Content Area
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "transparent"

                Flickable {
                    anchors.fill: parent
                    anchors.margins: Theme.padExtraLarge
                    contentWidth: width
                    contentHeight: contentLoader.implicitHeight
                    clip: true

                    Loader {
                        id: contentLoader
                        width: parent.width
                        sourceComponent: {
                            switch (Config.activeSettingsPage) {
                                case "theme":
                                case "appearance": return themePageComp;
                                case "dock": return dockPageComp;
                                case "status": return statusPageComp;
                                case "dashboard": return dashPageComp;
                                case "system": return systemPageComp;
                                default: return dockPageComp;
                            }
                        }
                    }
                }
            }
        }

        Component { id: dockPageComp; DockPage {} }
        Component { id: statusPageComp; StatusIconsPage {} }
        Component { id: themePageComp; ThemePage {} }
        Component { id: dashPageComp; DashboardPage {} }
        Component { id: systemPageComp; SystemPage {} }
    }
}
