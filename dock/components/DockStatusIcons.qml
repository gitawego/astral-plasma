import QtQuick
import "../../theme"
import "../../components"
import "../../services"
import "../../config"

Rectangle {
    id: root

    implicitWidth: 42
    implicitHeight: layout.implicitHeight + Theme.padSmall * 2
    radius: Theme.radiusFull
    color: Colors.surfaceContainer
    border.color: Theme.borderSubtle
    border.width: 1

    HoverHandler {
        id: groupHover
        onHoveredChanged: {
            if (hovered) {
                Config.openBottomPopout("default");
            } else {
                Config.scheduleCloseBottomPopout();
            }
        }
    }

    Column {
        id: layout
        anchors.centerIn: parent
        spacing: 4

        // 1. Network / Wi-Fi
        Item {
            implicitWidth: 34
            implicitHeight: 34

            Rectangle {
                anchors.fill: parent
                radius: Theme.radiusFull
                color: (Config.bottomPopoutVisible && Config.bottomPopoutMode === "network") 
                    ? Colors.primaryContainer 
                    : (netHover.hovered ? Colors.surfaceContainerHigh : "transparent")

                MaterialIcon {
                    anchors.centerIn: parent
                    text: NetworkService.getIcon()
                    size: 18
                    color: (Config.bottomPopoutVisible && Config.bottomPopoutMode === "network") 
                        ? Colors.primary 
                        : Colors.onSurfaceVariant
                }

                HoverHandler {
                    id: netHover
                    onHoveredChanged: {
                        if (hovered) Config.openBottomPopout("network");
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Config.openBottomPopout("network")
                }
            }
        }

        // 2. Bluetooth
        Item {
            implicitWidth: 34
            implicitHeight: 34

            Rectangle {
                anchors.fill: parent
                radius: Theme.radiusFull
                color: (Config.bottomPopoutVisible && Config.bottomPopoutMode === "bluetooth") 
                    ? Colors.primaryContainer 
                    : (btHover.hovered ? Colors.surfaceContainerHigh : "transparent")

                MaterialIcon {
                    anchors.centerIn: parent
                    text: BluetoothService.getIcon()
                    size: 18
                    color: (Config.bottomPopoutVisible && Config.bottomPopoutMode === "bluetooth") 
                        ? Colors.primary 
                        : Colors.onSurfaceVariant
                }

                HoverHandler {
                    id: btHover
                    onHoveredChanged: {
                        if (hovered) Config.openBottomPopout("bluetooth");
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Config.openBottomPopout("bluetooth")
                }
            }
        }

        // 3. Power Profile / Rocket
        Item {
            implicitWidth: 34
            implicitHeight: 34

            Rectangle {
                anchors.fill: parent
                radius: Theme.radiusFull
                color: (Config.bottomPopoutVisible && Config.bottomPopoutMode === "default") 
                    ? Colors.primaryContainer 
                    : (profileHover.hovered ? Colors.surfaceContainerHigh : "transparent")

                MaterialIcon {
                    anchors.centerIn: parent
                    text: {
                        switch (PowerService.currentProfile) {
                            case "power-saver": return "energy_savings_leaf";
                            case "balanced": return "balance";
                            default: return "rocket_launch";
                        }
                    }
                    size: 18
                    color: (Config.bottomPopoutVisible && Config.bottomPopoutMode === "default") 
                        ? Colors.primary 
                        : Colors.onSurfaceVariant
                }

                HoverHandler {
                    id: profileHover
                    onHoveredChanged: {
                        if (hovered) Config.openBottomPopout("default");
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Config.openBottomPopout("default")
                }
            }
        }

        // 4. Power Button
        Item {
            implicitWidth: 34
            implicitHeight: 34

            Rectangle {
                anchors.fill: parent
                radius: Theme.radiusFull
                color: (Config.bottomPopoutVisible && Config.bottomPopoutMode === "power") 
                    ? Colors.primaryContainer 
                    : (pwrHover.hovered ? Colors.surfaceContainerHigh : "transparent")

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "power_settings_new"
                    size: 18
                    color: (Config.bottomPopoutVisible && Config.bottomPopoutMode === "power") 
                        ? Colors.primary 
                        : "#C8372D"
                }

                HoverHandler {
                    id: pwrHover
                    onHoveredChanged: {
                        if (hovered) Config.openBottomPopout("power");
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Config.openBottomPopout("power")
                }
            }
        }
    }
}
