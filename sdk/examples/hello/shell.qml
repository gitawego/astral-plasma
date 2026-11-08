// The smallest possible hosted Astral app.
//
// `quickshell -p .` starts this file. It may import `Astral.AppKit` and Qt; it may
// not import `Astral.Kernel`, and the sandbox does not let it read $HOME.
import QtQuick
import Astral.AppKit 1.0

AppWindow {
    width: 420
    height: 240
    anchors { top: true; left: true }
    margins { top: 120; left: 160 }

    Column {
        anchors.centerIn: parent
        spacing: 10

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Hello Astral"
            color: Colors.textOnSurface
            font.family: Theme.fontFamily
            font.pixelSize: 22
            font.bold: true
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "built against API " + AppApi.level
            color: Colors.primary
            font.pixelSize: 13
        }
    }
}
