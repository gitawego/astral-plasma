import QtQuick
import "../../theme"
import "../../components"
import "../../config"

Item {
    id: root

    implicitWidth: 36
    implicitHeight: 36

    PillButton {
        anchors.centerIn: parent
        iconText: "settings"
        iconSize: 18
        active: Config.settingsVisible
        onClicked: Config.toggleSettings()
    }
}
