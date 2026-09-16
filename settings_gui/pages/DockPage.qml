import QtQuick
import QtQuick.Layouts
import "../controls"
import "../../config"
import "../../theme"

ColumnLayout {
    id: root

    spacing: Theme.spaceMedium

    Text {
        text: "Dock Configuration"
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontTitleMedium
        font.weight: Font.Bold
        color: Colors.m3onSurface
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
        checked: Config.settings.dock ? (Config.settings.dock.exclusiveZone ?? true) : true
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
        value: Config.settings.dock ? (Config.settings.dock.margin ?? 12) : 12
        onValueModified: val => Config.setDockMargin(Math.round(val))
    }

    SettingToggle {
        Layout.fillWidth: true
        title: "System Tray"
        description: "Display icons for running background apps (Discord, Steam, etc.)"
        checked: Config.settings.dock && Config.settings.dock.tray ? (Config.settings.dock.tray.enabled ?? true) : true
        onToggled: val => Config.setDockTrayEnabled(val)
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
