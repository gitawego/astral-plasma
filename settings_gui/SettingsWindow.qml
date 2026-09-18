import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../theme"
import "../components"
import "../config"

PanelWindow {
    id: root

    property ShellScreen targetScreen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
    screen: targetScreen

    visible: Config.settingsVisible

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: Config.settingsVisible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    mask: Region {
        width: Config.settingsVisible ? root.width : 0
        height: Config.settingsVisible ? root.height : 0
    }

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    color: Qt.rgba(0, 0, 0, 0.45) // Dim background overlay

    // Click backdrop to close
    MouseArea {
        anchors.fill: parent
        onClicked: Config.settingsVisible = false
    }

    // Modal dialog box
    Rectangle {
        id: dialogBox
        anchors.centerIn: parent
        width: 860
        height: 580
        radius: Theme.radiusLarge
        color: Colors.surface
        border.color: Theme.borderSubtle
        border.width: 1
        clip: true

        focus: true
        Keys.onEscapePressed: Config.settingsVisible = false

        // Consume clicks inside dialog
        MouseArea {
            anchors.fill: parent
            onClicked: {}
        }

        // Top-right Close Button
        Rectangle {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: Theme.padMedium
            width: 32
            height: 32
            radius: 16
            color: closeMouseArea.containsMouse ? Colors.pillHover : "transparent"
            z: 200

            MaterialIcon {
                anchors.centerIn: parent
                text: "close"
                size: 18
                color: Colors.m3onSurfaceVariant
            }

            MouseArea {
                id: closeMouseArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Config.settingsVisible = false
            }
        }

        // The Modular Nexus Settings Hub
        NexusHub {
            anchors.fill: parent
            onCloseRequested: Config.settingsVisible = false
        }
    }
}
