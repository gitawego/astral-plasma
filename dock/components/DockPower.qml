import QtQuick
import Quickshell.Io
import "../../theme"
import "../../components"

Item {
    id: root

    implicitWidth: 36
    implicitHeight: 36

    PillButton {
        anchors.centerIn: parent
        iconText: "power"
        iconSize: 18
        onClicked: {
            logoutProc.running = true;
        }
    }

    Process {
        id: logoutProc
        command: ["qdbus6", "org.kde.LogoutPrompt", "/LogoutPrompt", "org.kde.LogoutPrompt.promptShutDown"]
    }
}
