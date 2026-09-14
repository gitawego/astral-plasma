import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../theme"
import "../config"
import "popouts"

PanelWindow {
    id: root

    property ShellScreen targetScreen: Quickshell.screens[0]
    screen: targetScreen

    visible: Config.settings.dock ? Config.settings.dock.enabled : true

    anchors {
        left: true
        top: true
        bottom: true
    }

    margins {
        left: 0
        top: 0
        bottom: 0
    }

    exclusiveZone: (Config.settings.dock && Config.settings.dock.exclusiveZone) 
        ? (Config.settings.dock.width || 56)
        : 0

    implicitWidth: dockPill.width + (Config.activePopout !== "" ? 300 : 0)

    color: "transparent"

    Item {
        anchors.fill: parent

        // The Dock Container (Flush against left screen edge)
        Rectangle {
            id: dockPill
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: Config.settings.dock ? Config.settings.dock.width : 56

            color: Colors.surface
            border.color: Theme.borderSubtle
            border.width: 1

            // Right border separator only when docked
            Rectangle {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 1
                color: Theme.borderSubtle
            }

            // The modules inside the dock
            Flickable {
                anchors.fill: parent
                anchors.topMargin: Theme.padMedium
                anchors.bottomMargin: Theme.padMedium
                contentWidth: width
                contentHeight: repeater.implicitHeight
                boundsBehavior: Flickable.StopAtBounds

                BarRepeater {
                    id: repeater
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }

        // Popout Container Anchor right next to the dock
        Item {
            id: popoutContainer
            anchors.left: dockPill.right
            anchors.leftMargin: Theme.spaceMedium
            anchors.verticalCenter: parent.verticalCenter
            visible: Config.activePopout !== ""
            opacity: visible ? 1.0 : 0.0

            Behavior on opacity {
                NumberAnimation { duration: Theme.animDurationNormal }
            }

            Loader {
                anchors.centerIn: parent
                active: Config.activePopout !== ""
                sourceComponent: {
                    switch (Config.activePopout) {
                        case "network": return wifiPopoutComp;
                        case "bluetooth": return btPopoutComp;
                        case "audio": return audioPopoutComp;
                        case "brightness": return brightPopoutComp;
                        case "kblayout": return kbPopoutComp;
                        case "battery": return battPopoutComp;
                        case "activewindow": return activeWinPopoutComp;
                        default: return null;
                    }
                }
            }

            Component { id: wifiPopoutComp; WifiPopout {} }
            Component { id: btPopoutComp; BluetoothPopout {} }
            Component { id: audioPopoutComp; AudioPopout {} }
            Component { id: brightPopoutComp; BrightnessPopout {} }
            Component { id: kbPopoutComp; KbLayoutPopout {} }
            Component { id: battPopoutComp; BatteryPopout {} }
            Component { id: activeWinPopoutComp; ActiveWindowPopout {} }
        }
    }
}
