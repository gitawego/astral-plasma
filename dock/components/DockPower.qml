import QtQuick
import "../../modules/Astral/Kernel/theme"
import "../../modules/Astral/Kernel/components"
import "../../modules/Astral/Kernel/services"

Item {
    id: root

    implicitWidth: 36
    implicitHeight: 36

    PillButton {
        anchors.centerIn: parent
        iconText: "power"
        iconSize: 18
        onClicked: {
            PowerService.requestPoweroff();
        }
    }
}
