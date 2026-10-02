import QtQuick
import QtQuick.Layouts
import "../controls"
import "../../config"
import "../../theme"
import "../../components"

SettingsPage {
    id: root

    title: "Dock & Layout"
    subtitle: "The left dock, its system tray, and the top bar it lives beside"
    // Three groups, three zones: dock geometry, the tray it hosts, and the bar
    // along the top edge.
    zones: [
        { id: "dock", label: "Dock", anchor: dockHeader },
        { id: "tray", label: "Tray", anchor: trayHeader },
        { id: "topbar", label: "Top Bar", anchor: topBarHeader }
    ]

    spacing: Theme.spaceMedium

    /// Tray visibility, read from the same place the toggle writes, so the
    /// header's line and the switch cannot disagree.
    readonly property bool trayEnabled: (typeof Config !== "undefined" && Config.settings
            && Config.settings.dock && Config.settings.dock.tray)
        ? (Config.settings.dock.tray.enabled ?? true) : true

    SectionHeader {
        id: dockHeader
        title: "Dock"
        eyebrow: (typeof Config !== "undefined" && Config.dockEnabled)
            ? "shown on the left edge"
            : "hidden"
    }

    SettingToggle {
        Layout.fillWidth: true
        title: "Enable Left Dock"
        description: "Show the floating vertical dock on the left side of the screen"
        checked: Config.dockEnabled
        onToggled: val => Config.setDockEnabled(val)
    }

    SettingToggle {
        Layout.fillWidth: true
        title: "Exclusive Screen Zone"
        description: "Reserve screen edge space so maximized/fullscreen windows dock cleanly beside the bar"
        checked: (typeof Config !== "undefined" && Config.settings && Config.settings.dock) ? (Config.settings.dock.exclusiveZone ?? true) : true
        onToggled: val => Config.setDockExclusiveZone(val)
    }

    SettingSlider {
        Layout.fillWidth: true
        title: "Icon Size"
        min: 20
        max: 56
        suffix: "px"
        value: Config.dockIconSize
        onValueModified: val => Config.setDockIconSize(Math.round(val))
    }

    SettingSlider {
        Layout.fillWidth: true
        title: "Dock Width"
        min: 48
        max: 96
        suffix: "px"
        value: Config.dockWidth
        onValueModified: val => Config.setDockWidth(Math.round(val))
    }

    SettingSlider {
        Layout.fillWidth: true
        title: "Screen Margin"
        min: 0
        max: 32
        suffix: "px"
        value: (typeof Config !== "undefined" && Config.settings && Config.settings.dock) ? (Config.settings.dock.margin ?? 12) : 12
        onValueModified: val => Config.setDockMargin(Math.round(val))
    }

    SectionHeader {
        id: trayHeader
        title: "System Tray"
        eyebrow: root.trayEnabled ? "icons shown" : "icons hidden"
    }

    SettingToggle {
        Layout.fillWidth: true
        title: "System Tray"
        description: "Display icons for running background apps (Discord, Steam, etc.)"
        checked: root.trayEnabled
        onToggled: val => Config.setDockTrayEnabled(val)
    }

    SectionHeader {
        id: topBarHeader
        title: "Top Bar"
        eyebrow: (typeof Config !== "undefined" && Config.topBarEnabled)
            ? ("shown · " + ((typeof Config !== "undefined" && Config.topBarHeight) ? Config.topBarHeight : 28) + "px")
            : "hidden"
    }

    SettingToggle {
        Layout.fillWidth: true
        title: "Enable Top Bar"
        description: "Show the integrated bar spanning across the top of the screen"
        checked: Config.topBarEnabled
        onToggled: val => Config.setTopBarEnabled(val)
    }

    SettingSlider {
        Layout.fillWidth: true
        title: "Top Bar Height"
        min: 28
        max: 56
        suffix: "px"
        value: Config.topBarHeight
        onValueModified: val => Config.setTopBarHeight(Math.round(val))
    }
}
