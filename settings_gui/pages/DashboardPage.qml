import QtQuick
import QtQuick.Layouts
import "../controls"
import "../../config"
import "../../theme"

ColumnLayout {
    id: root

    spacing: Theme.spaceMedium

    Text {
        text: "Dashboard & Widgets"
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontTitleMedium
        font.weight: Font.Bold
        color: Colors.m3onSurface
    }

    SettingToggle {
        Layout.fillWidth: true
        title: "Central Popout Dashboard"
        description: "Enable the top-center modal overlay (toggled via dock clock or shortcut)"
        checked: Config.settings.dashboard ? (Config.settings.dashboard.enabled ?? true) : true
        onToggled: val => Config.setDashboardEnabled(val)
    }

    Repeater {
        model: Config.settings.dashboard && Config.settings.dashboard.tabs ? Config.settings.dashboard.tabs : []

        delegate: SettingToggle {
            Layout.fillWidth: true
            title: modelData.label + " Tab"
            description: "Show " + modelData.label + " tab inside the Central Dashboard"
            checked: modelData.enabled
            onToggled: val => Config.setDashboardTabEnabled(modelData.id, val)
        }
    }
}
