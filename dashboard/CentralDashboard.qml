import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../theme"
import "../components"
import "../config"
import "../services"
import "tabs"
import "tabs/DashboardTabs.js" as DashboardTabs

PanelWindow {
    id: root

    property ShellScreen targetScreen: Quickshell.screens[0]
    screen: targetScreen

    visible: Config.dashboardVisible

    /// The tab actually rendered: the configured one when it is available,
    /// otherwise the first one that is. A selected tab can disappear (the user
    /// disabled it, or the download engine went away), and a loader left on a tab
    /// the bar no longer shows is a view with no way back to it.
    /// See shell/CentralDropdown.qml: unknown counts as present.
    readonly property bool ariaAvailable: (typeof DownloadService !== "undefined" && DownloadService
        && DownloadService.ariaAvailable !== undefined) ? Boolean(DownloadService.ariaAvailable) : true

    readonly property var visibleTabs: DashboardTabs.availableTabs(Config.dashboardTabs, root.ariaAvailable)
    readonly property string shownTab: DashboardTabs.fallbackActiveTab(root.visibleTabs, Config.activeDashboardTab)


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
                activeTab: root.shownTab
                // The list is a setting, minus the tabs this machine cannot
                // serve: the Downloads tab needs the aria2 engine, so it is not
                // rendered while the engine is missing even if it is enabled.
                tabs: root.visibleTabs
                onTabSelected: tabId => Config.activeDashboardTab = tabId
            }

            // Tab Content
            Loader {
                Layout.fillWidth: true
                Layout.preferredHeight: 320

                sourceComponent: {
                    switch (root.shownTab) {
                        case "dashboard": return dashboardTabComp;
                        case "media": return mediaTabComp;
                        case "performance": return perfTabComp;
                        case "workspaces": return wsTabComp;
                        case "downloads": return dlTabComp;
                        case "ai": return aiTabComp;
                        default: return dashboardTabComp;
                    }
                }
            }
        }

        Component { id: dashboardTabComp; DashboardTab {} }
        Component { id: mediaTabComp; MediaTab {} }
        Component { id: perfTabComp; PerformanceTab {} }
        Component { id: wsTabComp; WorkspacesTab {} }
        Component { id: dlTabComp; DownloadsTab {} }
        Component { id: aiTabComp; AiTab {} }
    }
}
