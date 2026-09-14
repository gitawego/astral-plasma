import QtQuick
import Quickshell
import "../config"

Scope {
    id: root

    required property ShellScreen screen

    // Left Dock Exclusive Zone
    PanelWindow {
        screen: root.screen
        anchors {
            left: true
            top: true
            bottom: true
        }
        exclusiveZone: (Config.settings.dock && Config.settings.dock.enabled && Config.settings.dock.exclusiveZone)
            ? Config.dockWidth
            : 0
        mask: Region {}
        implicitWidth: 1
        color: "transparent"
    }

    // Top Border / Bar Exclusive Zone
    PanelWindow {
        screen: root.screen
        anchors {
            top: true
            left: true
            right: true
        }
        exclusiveZone: Config.topBarEnabled ? Config.topBarHeight : Config.borderThickness
        mask: Region {}
        implicitHeight: 1
        color: "transparent"
    }

    // Right Border Exclusive Zone
    PanelWindow {
        screen: root.screen
        anchors {
            right: true
            top: true
            bottom: true
        }
        exclusiveZone: Config.borderThickness
        mask: Region {}
        implicitWidth: 1
        color: "transparent"
    }

    // Bottom Border Exclusive Zone
    PanelWindow {
        screen: root.screen
        anchors {
            bottom: true
            left: true
            right: true
        }
        exclusiveZone: Config.borderThickness
        mask: Region {}
        implicitHeight: 1
        color: "transparent"
    }
}
