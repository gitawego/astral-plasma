import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.theme
import qs.components
import qs.config
import qs.services

PanelWindow {
    id: root

    property ShellScreen targetScreen: Quickshell.screens[0]
    screen: targetScreen

    visible: Config.topBarEnabled

    anchors {
        top: true
        left: true
        right: true
    }

    // Left margin starts after the docked left sidebar
    margins {
        top: 0
        left: (Config.settings.dock && Config.settings.dock.enabled) ? (Config.settings.dock.width || 56) : 0
        right: 0
    }

    exclusiveZone: Config.topBarExclusiveZone ? Config.topBarHeight : 0

    implicitHeight: Config.topBarHeight

    color: "transparent"

    Rectangle {
        anchors.fill: parent
        color: Colors.surface
        border.color: Theme.borderSubtle
        border.width: 0

        // Bottom border separating top bar from client windows
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: Theme.borderSubtle
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.padLarge
            anchors.rightMargin: Theme.padLarge
            spacing: Theme.spaceMedium

            // Left Section: Active Window Breadcrumb / Title
            RowLayout {
                Layout.preferredWidth: 280
                Layout.fillHeight: true
                spacing: Theme.spaceSmall
                visible: Config.topBarShowTitle

                MaterialIcon {
                    text: "laptop_mac"
                    size: 16
                    color: Colors.primary
                }

                Text {
                    Layout.fillWidth: true
                    text: (WindowService.activeTitle && WindowService.activeTitle.length > 0) ? WindowService.activeTitle : "KDE Plasma 6 (Wayland)"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontBodySmall
                    font.weight: Font.Medium
                    color: Colors.m3onSurface
                    elide: Text.ElideRight
                }
            }

            Item { Layout.fillWidth: true }

            // Center Section: Interactive Dashboard Tabs Pills
            Row {
                Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
                spacing: 6
                visible: Config.topBarShowTabs

                readonly property var tabs: [
                    { id: "dashboard", label: "Dashboard", icon: "grid_view" },
                    { id: "media", label: "Media", icon: "music_note" },
                    { id: "performance", label: "Performance", icon: "speed" },
                    { id: "workspaces", label: "Workspaces", icon: "workspaces" }
                ]

                Repeater {
                    model: parent.tabs

                    delegate: Rectangle {
                        id: tabPill
                        width: tabRow.implicitWidth + 24
                        height: 28
                        radius: Theme.radiusFull

                        readonly property bool isSelected: Config.dashboardVisible && Config.activeDashboardTab === modelData.id
                        readonly property bool isHovered: tabMouseArea.containsMouse

                        color: isSelected 
                            ? Colors.primaryContainer 
                            : (isHovered ? Colors.pillHover : "transparent")

                        border.color: isSelected ? Qt.alpha(Colors.primary, 0.4) : "transparent"
                        border.width: 1

                        Row {
                            id: tabRow
                            anchors.centerIn: parent
                            spacing: 6

                            MaterialIcon {
                                text: modelData.icon
                                size: 14
                                color: tabPill.isSelected ? Colors.m3onPrimaryContainer : Colors.m3onSurfaceVariant
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Text {
                                text: modelData.label
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontBodySmall
                                font.weight: tabPill.isSelected ? Font.Bold : Font.Normal
                                color: tabPill.isSelected ? Colors.m3onPrimaryContainer : Colors.m3onSurface
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        MouseArea {
                            id: tabMouseArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor

                            onClicked: {
                                if (Config.dashboardVisible && Config.activeDashboardTab === modelData.id) {
                                    Config.dashboardVisible = false;
                                } else {
                                    Config.activeDashboardTab = modelData.id;
                                    Config.dashboardVisible = true;
                                }
                            }
                        }
                    }
                }
            }

            Item { Layout.fillWidth: true }

            // Right Section: Weather Badge & Quick Actions
            RowLayout {
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                spacing: Theme.spaceMedium

                // Weather badge
                Rectangle {
                    height: 26
                    width: weatherRow.implicitWidth + 16
                    radius: Theme.radiusFull
                    color: Colors.surfaceContainer
                    border.color: Theme.borderSubtle
                    border.width: 1

                    Row {
                        id: weatherRow
                        anchors.centerIn: parent
                        spacing: 4

                        MaterialIcon {
                            text: WeatherService.weatherIcon
                            size: 14
                            color: Colors.primary
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            text: WeatherService.temp
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontLabelSmall
                            font.weight: Font.Medium
                            color: Colors.m3onSurface
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Config.activeDashboardTab = 0;
                            Config.dashboardVisible = !Config.dashboardVisible;
                        }
                    }
                }

                // Settings icon button
                Rectangle {
                    width: 28
                    height: 28
                    radius: 14
                    color: settingsArea.containsMouse ? Colors.pillHover : "transparent"

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: "tune"
                        size: 16
                        color: Colors.m3onSurfaceVariant
                    }

                    MouseArea {
                        id: settingsArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Config.toggleSettings()
                    }
                }
            }
        }
    }
}
