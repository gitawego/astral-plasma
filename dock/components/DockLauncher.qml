import QtQuick
import "../../modules/Astral/Kernel/theme"
import "../../modules/Astral/Kernel/components"
import "../../modules/Astral/Kernel/config"
import "../../modules/Astral/Kernel/services"

Item {
    id: root

    implicitWidth: 40
    implicitHeight: 40

    PillButton {
        anchors.centerIn: parent
        iconText: "dashboard"
        iconSize: 20
        active: Config.dashboardVisible
        onClicked: Config.toggleDashboard()
        onRightClicked: WindowService.launchTerminal()
        onMiddleClicked: {
            if (typeof Config !== "undefined" && Config.toggleCommandLauncher) {
                Config.toggleCommandLauncher();
            }
        }
    }
}
