import QtQuick
import "../../modules/Astral/Kernel/theme"
import "../../modules/Astral/Kernel/components"
import "../../modules/Astral/Kernel/config"

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
