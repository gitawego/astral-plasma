import QtQuick
import "../services"
import "../config"

Item {
    id: root
    visible: false

    Component.onCompleted: {
        DesktopSessionFacade.profile = "omarchy";
        DesktopSessionFacade.refresh();
    }

    function toggleDashboard() {
        Config.dashboardVisible = !Config.dashboardVisible;
    }

    function toggleLauncher() {
        Config.launcherVisible = !Config.launcherVisible;
    }

    function toggleSettings() {
        Config.settingsVisible = !Config.settingsVisible;
    }
}
