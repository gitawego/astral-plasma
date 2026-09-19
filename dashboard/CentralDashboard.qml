import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../theme"
import "../components"
import "../config"
import "tabs"

PanelWindow {
    id: root

    property ShellScreen targetScreen: Quickshell.screens[0]
    screen: targetScreen

    visible: Config.dashboardVisible

    anchors {
        top: true
    }

    margins {
        top: Config.topBarEnabled ? (Config.topBarHeight + 6) : 16
    }

    implicitWidth: 720
    implicitHeight: mainCard.implicitHeight

    color: "transparent"

    LiquidGlassCard {
        id: mainCard
        anchors.horizontalCenter: parent.horizontalCenter
        width: 720
        implicitHeight: layout.implicitHeight + ((typeof Theme !== "undefined" && Theme.padLarge) ? Theme.padLarge : 16) * 2

        focus: true
        Keys.onEscapePressed: Config.dashboardVisible = false

        radius: (typeof Theme !== "undefined" && Theme.radiusLarge) ? Theme.radiusLarge : 16
        elevation: 12
        showShadow: true

        ColumnLayout {
            id: layout
            anchors.fill: parent
            anchors.margins: Theme.padLarge
            spacing: Theme.spaceLarge

            // Top TabBar matching Screenshot 1 & 3
            TabBar {
                id: tabNav
                Layout.fillWidth: true
                activeTab: Config.activeDashboardTab
                tabs: [
                    { id: "dashboard", label: "Dashboard", icon: "dashboard" },
                    { id: "media", label: "Media", icon: "media" },
                    { id: "performance", label: "Performance", icon: "performance" },
                    { id: "workspaces", label: "Workspaces", icon: "workspaces" }
                ]
                onTabSelected: tabId => Config.activeDashboardTab = tabId
            }

            // Tab Content
            Loader {
                Layout.fillWidth: true
                Layout.preferredHeight: 320

                sourceComponent: {
                    switch (Config.activeDashboardTab) {
                        case "dashboard": return dashboardTabComp;
                        case "media": return mediaTabComp;
                        case "performance": return perfTabComp;
                        case "workspaces": return wsTabComp;
                        default: return dashboardTabComp;
                    }
                }
            }
        }

        Component { id: dashboardTabComp; DashboardTab {} }
        Component { id: mediaTabComp; MediaTab {} }
        Component { id: perfTabComp; PerformanceTab {} }
        Component { id: wsTabComp; WorkspacesTab {} }
    }
}
