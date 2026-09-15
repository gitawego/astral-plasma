import QtQuick
import "../../theme"
import "../../components"
import "../../services"

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
