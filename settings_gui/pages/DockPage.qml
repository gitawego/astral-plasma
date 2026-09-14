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
        checked: Config.settings.dock ? Config.settings.dock.enabled : true
        onToggled: val => {
            Config.settings.dock.enabled = val;
            Config.saveSettings();
        }
    }

    SettingToggle {
        Layout.fillWidth: true
        title: "Exclusive Screen Zone"
        description: "Reserve screen edge space so maximized/fullscreen windows dock cleanly beside the bar"
        checked: Config.settings.dock ? Config.settings.dock.exclusiveZone : true
        onToggled: val => {
            Config.settings.dock.exclusiveZone = val;
            Config.saveSettings();
        }
    }

    SettingSlider {
        Layout.fillWidth: true
        title: "Dock Width"
        min: 44
        max: 80
        suffix: "px"
        value: Config.settings.dock ? Config.settings.dock.width : 56
        onValueModified: val => {
            Config.settings.dock.width = Math.round(val);
            Config.saveSettings();
        }
    }

    SettingSlider {
        Layout.fillWidth: true
        title: "Screen Margin"
        min: 0
        max: 32
        suffix: "px"
        value: Config.settings.dock ? Config.settings.dock.margin : 12
        onValueModified: val => {
            Config.settings.dock.margin = Math.round(val);
            Config.saveSettings();
        }
    }

    SettingToggle {
        Layout.fillWidth: true
        title: "System Tray"
        description: "Display icons for running background apps (Discord, Steam, etc.)"
        checked: Config.settings.dock && Config.settings.dock.tray ? Config.settings.dock.tray.enabled : true
        onToggled: val => {
            if (!Config.settings.dock.tray) Config.settings.dock.tray = {};
            Config.settings.dock.tray.enabled = val;
            Config.saveSettings();
        }
    }

    SettingToggle {
        Layout.fillWidth: true
        title: "Enable Top Bar"
        description: "Show the integrated bar spanning across the top of the screen"
        checked: Config.settings.topBar ? Config.settings.topBar.enabled : true
        onToggled: val => {
            if (!Config.settings.topBar) Config.settings.topBar = {};
            Config.settings.topBar.enabled = val;
            Config.saveSettings();
        }
    }

    SettingSlider {
        Layout.fillWidth: true
        title: "Top Bar Height"
        min: 28
        max: 56
        suffix: "px"
        value: Config.settings.topBar ? Config.settings.topBar.height : 38
        onValueModified: val => {
            if (!Config.settings.topBar) Config.settings.topBar = {};
            Config.settings.topBar.height = Math.round(val);
            Config.saveSettings();
        }
    }
}
