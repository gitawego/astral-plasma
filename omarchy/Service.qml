import QtQuick
import "../modules/Astral/Kernel/services"
import "../modules/Astral/Kernel/config"

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
