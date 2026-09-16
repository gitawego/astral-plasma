import QtQuick
import QtQuick.Layouts
import "../controls"
import "../../config"
import "../../theme"

ColumnLayout {
    id: root

    spacing: Theme.spaceMedium

    Text {
        text: "Status Components"
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontTitleMedium
        font.weight: Font.Bold
        color: Colors.m3onSurface
    }

    Repeater {
        model: Config.settings.dock && Config.settings.dock.statusIcons ? Config.settings.dock.statusIcons : []

        delegate: SettingToggle {
            Layout.fillWidth: true
            title: {
                switch (modelData.id) {
                    case "kblayout": return "Keyboard Language Switcher (KDE DBus)";
                    case "network": return "Wi-Fi & Network Manager";
                    case "bluetooth": return "Bluetooth Controller (BlueZ)";
                    case "brightness": return "Display Brightness (KDE Solid)";
                    case "audio": return "Audio Volume (PipeWire)";
                    case "battery": return "Battery & Power Profiles (UPower)";
                    default: return modelData.id;
                }
            }
            description: "Show " + modelData.id + " icon and interactive popout in the dock"
            checked: modelData.enabled
            onToggled: val => Config.setStatusIconEnabled(modelData.id, val)
        }
    }
}
