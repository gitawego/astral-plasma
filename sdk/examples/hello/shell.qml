// The smallest possible hosted Astral app.
//
// `quickshell -p .` starts this file. It may import Astral.AppKit and Qt; it may
// not import Astral.Kernel, and the sandbox will not let it read $HOME.
import QtQuick
import Quickshell
import Quickshell.Wayland
import Astral.AppKit 1.0

ShellRoot {
    PanelWindow {
        screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
        anchors { top: true; left: true }
        margins { top: 120; left: 160 }
        implicitWidth: 420
        implicitHeight: 240
        color: "transparent"

        AppWindow {
            anchors.fill: parent
            Column {
                anchors.centerIn: parent
                spacing: 10
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Hello Astral"
                    color: Theme.textOnSurface
                    font.pixelSize: 22
                    font.bold: true
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "appkit api " + AppApi.level
                    color: Colors.primary
                    font.pixelSize: 13
                }
            }
        }
    }
}
