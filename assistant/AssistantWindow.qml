import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../theme"
import "../components"
import "../config"
import "../services"

PanelWindow {
    id: root

    property ShellScreen targetScreen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
    screen: targetScreen

    property bool testMode: false
    property bool activeVisible: testMode ? true : (typeof Config !== "undefined" ? Config.assistantVisible : false)
    readonly property alias drawerItem: drawer

    visible: activeVisible

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: activeVisible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    // Non-modal floating surface: no underlay scrim, allowing viewing and interacting with underlying desktop windows
    color: "transparent"

    // Input mask restricts pointer & touch interaction strictly to the floating card,
    // allowing direct clicks to pass through to underlying desktop windows without closing the assistant.
    mask: Region {
        x: drawer ? drawer.x : 0
        y: drawer ? drawer.y : 0
        width: root.activeVisible && drawer ? drawer.width : 0
        height: root.activeVisible && drawer ? drawer.height : 0
    }

    // Compositor backdrop blur behind the floating modal card
    BackgroundEffect.blurRegion: Region {
        x: drawer ? drawer.x : 0
        y: drawer ? drawer.y : 0
        width: root.activeVisible && drawer ? drawer.width : 0
        height: root.activeVisible && drawer ? drawer.height : 0
    }

    // User-dragged position tracking and boundary clamping
    property bool userMoved: false

    function resetPosition() {
        userMoved = false;
        if (drawer && typeof drawer.resetPosition === "function") {
            drawer.resetPosition();
        }
    }

    function clampPosition() {
        if (!drawer || root.width <= 0 || root.height <= 0) return;
        const minX = 16;
        const maxX = Math.max(minX, root.width - drawer.width - 16);
        const minY = 16;
        const maxY = Math.max(minY, root.height - drawer.height - 16);
        drawer.x = Math.max(minX, Math.min(drawer.x, maxX));
        drawer.y = Math.max(minY, Math.min(drawer.y, maxY));
    }

    onWidthChanged: if (userMoved) clampPosition()
    onHeightChanged: if (userMoved) clampPosition()

    onActiveVisibleChanged: {
        if (activeVisible && !userMoved) {
            resetPosition();
        }
    }

    AssistantDrawer {
        id: drawer
        isFloating: true
        isOpen: root.activeVisible

        onUserDragged: {
            root.userMoved = true;
        }

        onResetRequested: {
            root.resetPosition();
        }
    }
}
