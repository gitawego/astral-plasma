import QtQuick
import Quickshell.Io
import "../../theme"
import "../../components"

Rectangle {
    id: root

    implicitWidth: 42
    implicitHeight: layout.implicitHeight + Theme.padSmall * 2
    radius: Theme.radiusFull
    color: Colors.surfaceContainer
    border.color: Theme.borderSubtle
    border.width: 1

    property var apps: [
        { name: "Terminal", icon: "utilities-terminal", exec: "ghostty || foot || alacritty || konsole" },
        { name: "Browser", icon: "browser", exec: "xdg-open https://" },
        { name: "Files", icon: "system-file-manager", exec: "dolphin" },
        { name: "Editor", icon: "accessories-text-editor", exec: "code || kate" }
    ]

    Column {
        id: layout
        anchors.centerIn: parent
        spacing: 3

        // Mini workspace dots indicator
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 3
            Rectangle { width: 4; height: 4; radius: 2; color: Colors.primary }
            Rectangle { width: 4; height: 4; radius: 2; color: Colors.outlineVariant }
            Rectangle { width: 4; height: 4; radius: 2; color: Colors.outlineVariant }
        }

        Item { width: 1; height: 2 }

        Repeater {
            model: root.apps

            delegate: Item {
                implicitWidth: 34
                implicitHeight: 34

            PillButton {
                anchors.centerIn: parent
                iconName: modelData.icon
                iconSize: 20
                onClicked: {
                    launchProc.command = ["sh", "-c", modelData.exec + " &"];
                    launchProc.running = true;
                }
            }
        }
    }

    Process {
        id: launchProc
    }
}
}
