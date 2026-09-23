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

    BackgroundEffect.blurRegion: Region {
        x: dialogBox.x
        y: dialogBox.y
        width: Config.settingsVisible ? dialogBox.width : 0
        height: Config.settingsVisible ? dialogBox.height : 0
    }

    mask: Region {
        x: dialogBox.x
        y: dialogBox.y
        width: Config.settingsVisible ? dialogBox.width : 0
        height: Config.settingsVisible ? dialogBox.height : 0
    }

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    color: "transparent" // Non-modal floating surface allows viewing and interacting with underlying windows

    // User-dragged position tracking and boundary clamping
    property bool userMoved: false

    function resetPosition() {
        userMoved = false;
        dialogBox.x = Qt.binding(() => Math.round((root.width - dialogBox.width) / 2));
        dialogBox.y = Qt.binding(() => Math.round((root.height - dialogBox.height) / 2));
    }

    function clampPosition() {
        if (root.width <= 0 || root.height <= 0) return;
        const minX = 16;
        const maxX = Math.max(minX, root.width - dialogBox.width - 16);
        const minY = 16;
        const maxY = Math.max(minY, root.height - dialogBox.height - 16);
        dialogBox.x = Math.max(minX, Math.min(dialogBox.x, maxX));
        dialogBox.y = Math.max(minY, Math.min(dialogBox.y, maxY));
    }

    onWidthChanged: if (userMoved) clampPosition()
    onHeightChanged: if (userMoved) clampPosition()

    // Modal dialog box (Sculpted Liquid Glass)
    Rectangle {
        id: dialogBox
        x: Math.round((root.width - width) / 2)
        y: Math.round((root.height - height) / 2)
        width: root.width > 0 ? Math.min(1240, Math.max(940, Math.round(root.width * 0.52))) : 1100
        height: root.height > 0 ? Math.min(860, Math.max(640, Math.round(root.height * 0.60))) : 750
        radius: Theme.radiusLarge
        color: Colors.glassSurface
        border.color: Colors.glassBorderSpecular
        border.width: 1
        clip: true

        // Top specular hairline glint
        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 24
            anchors.rightMargin: 24
            height: 1
            z: 10
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.5; color: Colors.glassBorderSpecular }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }

        // Inner caustic ambient glow
        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 36
            radius: parent.radius
            color: "transparent"
            z: 9
            gradient: Gradient {
                GradientStop { position: 0.0; color: Colors.glassCausticGlow }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }

        focus: true
        Keys.onEscapePressed: Config.settingsVisible = false

        // Underlying Dialog Drag Area (consumes clicks and supports dragging empty surfaces)
        MouseArea {
            id: dialogDragArea
            anchors.fill: parent

            drag.target: dialogBox
            drag.axis: Drag.XAndYAxis
            drag.minimumX: 16
            drag.maximumX: Math.max(16, root.width - dialogBox.width - 16)
            drag.minimumY: 16
            drag.maximumY: Math.max(16, root.height - dialogBox.height - 16)

            onPositionChanged: {
                if (drag.active) {
                    root.userMoved = true;
                }
            }

            onDoubleClicked: root.resetPosition()
            onClicked: {}
        }

        // Top Header Drag Bar (provides open/closed hand cursor affordance across top header)
        MouseArea {
            id: headerDragBar
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.rightMargin: 48
            height: 52
            z: 1

            hoverEnabled: true
            cursorShape: drag.active ? Qt.ClosedHandCursor : (containsMouse ? Qt.OpenHandCursor : Qt.ArrowCursor)

            drag.target: dialogBox
            drag.axis: Drag.XAndYAxis
            drag.minimumX: 16
            drag.maximumX: Math.max(16, root.width - dialogBox.width - 16)
            drag.minimumY: 16
            drag.maximumY: Math.max(16, root.height - dialogBox.height - 16)

            onPositionChanged: {
                if (drag.active) {
                    root.userMoved = true;
                }
            }

            onDoubleClicked: root.resetPosition()
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
            id: nexusHub
            anchors.fill: parent
            onCloseRequested: Config.settingsVisible = false
        }
    }

    function scrollTo(y) {
        nexusHub.scrollTo(y);
    }
}
