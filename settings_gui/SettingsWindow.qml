import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../theme"
import "../components"
import "../config"

// The settings surface is a real desktop window, exactly like the Copilot
// (docs/LESSONS.md §8.9).
//
// It used to be a full-screen layer-shell overlay (the Overlay layer plus a
// card-sized input mask). A layer surface is protocol-pinned above every
// application window - it can never be pushed to the background and Alt+Tab
// can never reach it - so the panel could not be backgrounded the way the chat can. As an xdg-toplevel it stacks, moves and
// shows in Alt+Tab with every other window. KWin's existing frameless rule
// (kwinrulesrc, wmclass=org.quickshell) already covers this second toplevel,
// and the card keeps drawing its own glass edge.
FloatingWindow {
    id: root

    property ShellScreen targetScreen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
    screen: targetScreen

    visible: Config.settingsVisible

    // Identity for Alt+Tab and any window list.
    title: "Astral Settings"
    color: "transparent"

    // Size.
    //
    // A Wayland toplevel cannot resize itself while it is mapped, so the shell
    // publishes the size the window should open with (bound through
    // implicitWidth/implicitHeight) and the compositor owns the geometry from
    // then on. The limits travel as the window's size hints.
    readonly property int referenceWidth: (root.targetScreen && root.targetScreen.width > 0)
        ? root.targetScreen.width
        : ((typeof Window !== "undefined" && Window.window && Window.window.width > 0) ? Window.window.width : 1920)
    readonly property int referenceHeight: (root.targetScreen && root.targetScreen.height > 0)
        ? root.targetScreen.height
        : ((typeof Window !== "undefined" && Window.window && Window.window.height > 0) ? Window.window.height : 1080)
    readonly property int minCardWidth: Math.min(940, Math.max(640, root.referenceWidth - 32))
    readonly property int minCardHeight: Math.min(640, Math.max(480, root.referenceHeight - 32))
    readonly property int maxCardWidth: Math.max(root.minCardWidth, Math.min(1240, root.referenceWidth - 32))
    readonly property int maxCardHeight: Math.max(root.minCardHeight, Math.min(860, root.referenceHeight - 32))
    readonly property int preferredWidth: Math.min(root.maxCardWidth,
        Math.max(root.minCardWidth, Math.round(root.referenceWidth * 0.52)))
    readonly property int preferredHeight: Math.min(root.maxCardHeight,
        Math.max(root.minCardHeight, Math.round(root.referenceHeight * 0.60)))

    implicitWidth: root.preferredWidth
    implicitHeight: root.preferredHeight
    minimumSize: Qt.size(root.minCardWidth, root.minCardHeight)
    maximumSize: Qt.size(root.maxCardWidth, root.maxCardHeight)

    // Compositor backdrop blur behind the glass plate. The window surface is
    // exactly the card, so the card item itself is the region.
    BackgroundEffect.blurRegion: Region {
        item: dialogBox
    }

    function scrollTo(y) {
        nexusHub.scrollTo(y);
    }

    // The card is the whole surface (Sculpted Liquid Glass)
    Rectangle {
        id: dialogBox
        anchors.fill: parent
        radius: Theme.radiusLarge
        // One plate for the whole surface: the rail and the content sit inside
        // this substrate, so no second panel has to be butted against it (which
        // is what put a rounded notch - and the wallpaper behind it - between
        // the two halves of the window).
        color: (typeof Colors !== "undefined") ? Colors.glassPanelSubstrate : Colors.glassSurface
        border.color: Colors.glassBorderSpecular
        border.width: 1
        clip: true

        focus: true
        Keys.onEscapePressed: Config.settingsVisible = false

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

        // Card background drag area: starts a compositor-native window move,
        // exactly like the Copilot card, so the window is repositioned by the
        // compositor instead of by item coordinates.
        MouseArea {
            id: dialogDragArea
            anchors.fill: parent
            z: 0
            cursorShape: containsMouse ? Qt.OpenHandCursor : Qt.ArrowCursor

            onPressed: {
                if (typeof root.startSystemMove === "function") {
                    root.startSystemMove();
                }
            }
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

            cursorShape: containsMouse ? Qt.OpenHandCursor : Qt.ArrowCursor

            onPressed: {
                if (typeof root.startSystemMove === "function") {
                    root.startSystemMove();
                }
            }
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
}
