import QtQuick
import QtQuick.Layouts
import "../controls"
import "../../modules/Astral/Kernel/config"
import "../../modules/Astral/Kernel/theme"
import "../../modules/Astral/Kernel/components"

SettingsPage {
    id: root

    title: "Status Icons"
    subtitle: "Which indicators the dock shows, and the popout behind each one"
    zones: [{ id: "icons", label: "Indicators", anchor: iconsHeader }]

    spacing: Theme.spaceMedium

    /// Indicators the dock actually renders. A settings file written before
    /// volume/brightness moved to the right-edge rail can still list them;
    /// showing a switch for an indicator that no longer exists would be a lie,
    /// so those stale ids are filtered out here (they stay in the file, inert,
    /// until the user rewrites it).
    readonly property var knownIconIds: ["kblayout", "network", "bluetooth",
        "battery", "clipboard", "notifications"]

    /// The indicator list, read once so the header's count and the switches
    /// cannot disagree about what is configured.
    readonly property var statusIcons: {
        const all = (typeof Config !== "undefined" && Config.settings
                && Config.settings.dock && Config.settings.dock.statusIcons)
            ? Config.settings.dock.statusIcons : [];
        const out = [];
        for (let i = 0; i < all.length; ++i) {
            if (all[i] && root.knownIconIds.indexOf(all[i].id) !== -1) out.push(all[i]);
        }
        return out;
    }

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
                    case "kblayout": return "Input Methods (fcitx5 / keyboard layouts)";
                    case "network": return "Wi-Fi & Network Manager";
                    case "bluetooth": return "Bluetooth Controller (BlueZ)";
                    case "clipboard": return "Clipboard Manager (KDE Klipper)";
                    case "notifications": return "Notification Center Bell";
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
