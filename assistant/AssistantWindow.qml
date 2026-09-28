import QtQuick
import Quickshell
import Quickshell.Wayland
import "../theme"
import "../components"
import "../config"
import "../services"

// The AI Copilot is a real desktop window, not a layer-shell overlay.
//
// Alt+Tab - and every other window list - only ever offers application windows:
// KWin hard-codes `skipSwitcher` for layer surfaces, so an overlay can never be
// reached with the system switcher. The copilot is therefore a `FloatingWindow`
// (docs/LESSONS.md §8.9): a normal toplevel that stacks, moves, resizes and
// shows up in the switcher like any other application.
//
// KWin decorates every xdg-toplevel by default, so the daemon installs a
// "no titlebar and frame" window rule for the shell's own toplevel class; the
// card draws its own glass edge.
FloatingWindow {
    id: root

    property ShellScreen targetScreen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
    screen: targetScreen

    property bool testMode: false
    property bool activeVisible: testMode ? true : (typeof Config !== "undefined" ? Config.assistantVisible : false)
    readonly property alias drawerItem: drawer

    // Window identity: this is what the user reads in Alt+Tab and in any
    // window list, so it names the product, not the implementation.
    title: "Astral Copilot"
    color: "transparent"

    // The window is mapped exactly while the chat is open, and switching to
    // another application is ordinary window stacking: the chat drops behind
    // that window and stays in Alt+Tab. Parking it in the dock hides it instead,
    // and that state stays the shell's own - a Wayland client may request a
    // minimize but has no way to ask for a restore again, so a compositor
    // minimize could never be undone from the dock capsule.
    visible: activeVisible

    // The compositor owns position and size once the surface is mapped, and
    // quickshell only forwards implicit size changes while the window is
    // hidden. The drawer therefore publishes the size to open with
    // (screen-aware, and wide enough for the sessions sidebar when it is
    // visible); whatever the user resizes the window to afterwards is what the
    // window keeps.
    implicitWidth: drawer ? drawer.preferredWidth : 740
    implicitHeight: drawer ? drawer.preferredHeight : 840
    minimumSize: Qt.size(drawer ? drawer.minWidth : 480, drawer ? drawer.minHeight : 520)
    maximumSize: Qt.size(drawer ? drawer.maxWidth : 4096, drawer ? drawer.maxHeight : 4096)

    // Compositor backdrop blur behind the floating glass card.
    BackgroundEffect.blurRegion: Region {
        item: drawer ? drawer.cardItem : null
    }

    AssistantDrawer {
        id: drawer
        anchors.fill: parent
        windowHandle: root
        testMode: root.testMode
        isOpen: root.activeVisible
    }
}
