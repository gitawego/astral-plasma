import QtQuick
import Quickshell
import "./appimage"

// Quickshell treats the directory of `-p <file>` as the config root. This file
// lives at the package root so the wizard's relative imports of `modules/`
// stay inside that root; launching `appimage/shell.qml` directly would make
// Quickshell reject those modules as external.
ShellRoot {
    SetupWindow {}
}
