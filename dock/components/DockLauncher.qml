import QtQuick
import "../../theme"
import "../../components"
import "../../config"

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
    }
}
