import QtQuick
import QtQuick.Layouts
import "../theme"
import "../config"
import "components"

Column {
    id: root

    spacing: Theme.spaceMedium

    readonly property var entries: {
        if (Config.settings.dock && Config.settings.dock.entries) {
            return Config.settings.dock.entries;
        }
        return ["launcher", "taskbar", "clock", "tray", "statusIcons", "settings", "power"];
    }

    Repeater {
        model: root.entries

        delegate: Loader {
            anchors.horizontalCenter: parent.horizontalCenter
            sourceComponent: {
                switch (modelData) {
                    case "launcher": return launcherComp;
                    case "activeWindow": return activeWindowComp;
                    case "taskbar": return taskbarComp;
                    case "clock": return clockComp;
                    case "tray": return trayComp;
                    case "statusIcons": return statusIconsComp;
                    case "settings": return settingsComp;
                    case "power": return powerComp;
                    default: return null;
                }
            }
        }
    }

    Component { id: launcherComp; DockLauncher {} }
    Component { id: activeWindowComp; ActiveWindow {} }
    Component { id: taskbarComp; DockTaskbar {} }
    Component { id: clockComp; DockClock {} }
    Component { id: trayComp; DockTray {} }
    Component { id: statusIconsComp; DockStatusIcons {} }
    Component { id: settingsComp; DockSettings {} }
    Component { id: powerComp; DockPower {} }
}
