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
                            active: navState.currentPage === "dock"
                            onClicked: navState.currentPage = "dock"
                        }
                        PillButton {
                            width: parent.width
                            label: "Status Icons"
                            iconText: "wifi"
                            active: navState.currentPage === "status"
                            onClicked: navState.currentPage = "status"
                        }
                        PillButton {
                            width: parent.width
                            label: "Appearance"
                            iconText: "weather_clear"
                            active: navState.currentPage === "theme"
                            onClicked: navState.currentPage = "theme"
                        }
                        PillButton {
                            width: parent.width
                            label: "Dashboard"
                            iconText: "calendar"
                            active: navState.currentPage === "dashboard"
                            onClicked: navState.currentPage = "dashboard"
                        }
                    }

                    Item { Layout.fillHeight: true }

                    // Close button
                    PillButton {
                        Layout.fillWidth: true
                        label: "Done"
                        active: true
                        onClicked: {
                            Config.saveSettings();
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

                Item { id: navState; property string currentPage: "dock" }

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
                            switch (navState.currentPage) {
                                case "dock": return dockPageComp;
                                case "status": return statusPageComp;
                                case "theme": return themePageComp;
                                case "dashboard": return dashPageComp;
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
    }
}
