import QtQuick
import QtQuick.Layouts
import "../controls"
import "../../config"
import "../../theme"
import "../../components"

SettingsPage {
    id: root

    title: "Status Icons"
    subtitle: "Which indicators the dock shows, and the popout behind each one"
    zones: [{ id: "icons", label: "Indicators", anchor: iconsHeader }]

    spacing: Theme.spaceMedium

    /// The indicator list, read once so the header's count and the switches
    /// cannot disagree about what is configured.
    readonly property var statusIcons: (typeof Config !== "undefined" && Config.settings
            && Config.settings.dock && Config.settings.dock.statusIcons)
        ? Config.settings.dock.statusIcons : []

    readonly property int enabledIconCount: {
        let n = 0;
        for (let i = 0; i < root.statusIcons.length; ++i) {
            if (root.statusIcons[i] && root.statusIcons[i].enabled) ++n;
        }
        return n;
    }

    SectionHeader {
        id: iconsHeader
        title: "Dock Indicators"
        eyebrow: root.statusIcons.length === 0
            ? "none configured"
            : (root.enabledIconCount + " of " + root.statusIcons.length + " shown")
    }

    Repeater {
        model: root.statusIcons

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
