import "../../modules/Astral/Kernel/components"
import "../../modules/Astral/Kernel/config"
import "../../modules/Astral/Kernel/theme"
import "../controls"
import QtQuick
import QtQuick.Layouts

SettingsPage {
    id: root

    /// Tray visibility, read from the same place the toggle writes, so the
    /// header's line and the switch cannot disagree.
    readonly property bool trayEnabled: (typeof Config !== "undefined" && Config.settings && Config.settings.dock && Config.settings.dock.tray) ? (Config.settings.dock.tray.enabled ?? true) : true
    property Component dockTab

    dockTab: Component {
        ColumnLayout {
            spacing: Theme.spaceMedium

            SectionHeader {
                Layout.fillWidth: true
                title: "Dock"
                eyebrow: (typeof Config !== "undefined" && Config.dockEnabled) ? "shown on the left edge" : "hidden"
            }

            SettingToggle {
                Layout.fillWidth: true
                title: "Enable Left Dock"
                description: "Show the floating vertical dock on the left side of the screen"
                checked: Config.dockEnabled
                onToggled: (val) => {
                    return Config.setDockEnabled(val);
                }
            }

            SettingToggle {
                Layout.fillWidth: true
                title: "Exclusive Screen Zone"
                description: "Reserve screen edge space so maximized/fullscreen windows dock cleanly beside the bar"
                checked: (typeof Config !== "undefined" && Config.settings && Config.settings.dock) ? (Config.settings.dock.exclusiveZone ?? true) : true
                onToggled: (val) => {
                    return Config.setDockExclusiveZone(val);
                }
            }

            SettingSlider {
                Layout.fillWidth: true
                title: "Icon Size"
                min: 20
                max: 56
                suffix: "px"
                value: Config.dockIconSize
                onValueModified: (val) => {
                    return Config.setDockIconSize(Math.round(val));
                }
            }

            SettingSlider {
                Layout.fillWidth: true
                title: "Dock Width"
                min: 48
                max: 96
                suffix: "px"
                value: Config.dockWidth
                onValueModified: (val) => {
                    return Config.setDockWidth(Math.round(val));
                }
            }

            SettingSlider {
                Layout.fillWidth: true
                title: "Screen Margin"
                min: 0
                max: 32
                suffix: "px"
                value: (typeof Config !== "undefined" && Config.settings && Config.settings.dock) ? (Config.settings.dock.margin ?? 12) : 12
                onValueModified: (val) => {
                    return Config.setDockMargin(Math.round(val));
                }
            }

            Item {
                Layout.fillHeight: true
            }

        }

    }

    property Component trayTab

    trayTab: Component {
        ColumnLayout {
            spacing: Theme.spaceMedium

            SectionHeader {
                Layout.fillWidth: true
                title: "System Tray"
                eyebrow: root.trayEnabled ? "icons shown" : "icons hidden"
            }

            SettingToggle {
                Layout.fillWidth: true
                title: "System Tray"
                description: "Display icons for running background apps (Discord, Steam, etc.)"
                checked: root.trayEnabled
                onToggled: (val) => {
                    return Config.setDockTrayEnabled(val);
                }
            }

            SettingToggle {
                Layout.fillWidth: true
                title: "Auto-expand Tray"
                description: "Automatically expand tray to display all icons without scrolling"
                visible: root.trayEnabled
                checked: typeof Config !== "undefined" ? Config.dockTrayAutoExpand : true
                onToggled: (val) => {
                    return Config.setDockTrayAutoExpand(val);
                }
            }

            Item {
                Layout.fillHeight: true
            }

        }

    }

    property Component topBarTab

    topBarTab: Component {
        ColumnLayout {
            spacing: Theme.spaceMedium

            SectionHeader {
                Layout.fillWidth: true
                title: "Top Bar"
                eyebrow: (typeof Config !== "undefined" && Config.topBarEnabled) ? ("shown · " + ((typeof Config !== "undefined" && Config.topBarHeight) ? Config.topBarHeight : 28) + "px") : "hidden"
            }

            SettingToggle {
                Layout.fillWidth: true
                title: "Enable Top Bar"
                description: "Show the integrated bar spanning across the top of the screen"
                checked: Config.topBarEnabled
                onToggled: (val) => {
                    return Config.setTopBarEnabled(val);
                }
            }

            SettingSlider {
                Layout.fillWidth: true
                title: "Top Bar Height"
                min: 28
                max: 56
                suffix: "px"
                value: Config.topBarHeight
                onValueModified: (val) => {
                    return Config.setTopBarHeight(Math.round(val));
                }
            }

            Item {
                Layout.fillHeight: true
            }

        }

    }

    title: "Dock & Layout"
    subtitle: "The left dock, its system tray, and the top bar it lives beside"
    icon: "dashboard"
    tabs: [{
        "id": "dock",
        "label": "Dock",
        "icon": "dashboard",
        "component": dockTab
    }, {
        "id": "tray",
        "label": "Tray",
        "icon": "tune",
        "component": trayTab
    }, {
        "id": "topbar",
        "label": "Top Bar",
        "icon": "window",
        "component": topBarTab
    }]
}
