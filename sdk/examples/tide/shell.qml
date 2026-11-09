// Tide — a hosted Astral panel.
//
// Layer-shell knobs are attached (`WlrLayershell.*`): the window itself is AppKit's.
import QtQuick
import Quickshell
import Quickshell.Wayland
import Astral.AppKit 1.0

AppWindow {
    anchors { top: true; left: true; right: true }
    implicitHeight: 44
    margins { top: 8; left: 240; right: 240 }

    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Text {
        anchors.centerIn: parent
        text: "Tide"
        color: Colors.textOnSurface
        font.family: Theme.fontFamily
        font.pixelSize: 13
    }
}
