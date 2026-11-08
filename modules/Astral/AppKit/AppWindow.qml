import QtQuick
import Quickshell
import Quickshell.Wayland

// ============================================================================
// AppWindow — the glass toplevel a hosted app owns
// ============================================================================
// Self-contained on purpose: a hosted app's sandbox mounts `Astral/AppKit` and
// nothing else, so the glass is drawn here rather than imported from the kernel.
// It uses the host's palette (radii, accent) so a community window reads as part
// of the same desktop, and falls back to the Material roles when no palette exists.
//
// Usage:
//   AppWindow {
//       width: 420; height: 240
//       Text { anchors.centerIn: parent; text: "Hello" }
//   }
//
// `screen`, `anchors`, and `margins` come from `PanelWindow`. Layer-shell knobs
// that are attached rather than declared (`WlrLayershell.layer`,
// `.exclusionMode`, `.keyboardFocus`) stay available to the app.
PanelWindow {
    id: window

    /// Space between the window edge and the glass.
    property int padding: 0
    /// Draw the glass card at all (false for fully custom painting).
    property bool glass: true
    /// Elevation in pixels: the drop shadow's offset and blur.
    property int elevation: 8

    default property alias content: surface.data

    color: "transparent"
    implicitWidth: 420
    implicitHeight: 240

    Rectangle {
        id: shadow
        anchors.fill: surface
        anchors.topMargin: -Math.round(window.elevation * 0.5)
        anchors.bottomMargin: Math.round(window.elevation * 0.9)
        anchors.leftMargin: -Math.round(window.elevation * 0.5)
        anchors.rightMargin: -Math.round(window.elevation * 0.5)
        radius: surface.radius
        visible: window.glass
        color: Qt.rgba(0, 0, 0, Colors.isDarkMode ? 0.34 : 0.16)

        // Soften the edge instead of drawing a second hard rectangle.
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: parent.radius
            color: "transparent"
            border.width: window.elevation
            border.color: Qt.rgba(0, 0, 0, Colors.isDarkMode ? 0.10 : 0.05)
        }
    }

    Rectangle {
        id: surface
        anchors.fill: parent
        anchors.margins: window.padding
        visible: window.glass
        radius: Theme.radiusLarge

        // Glass: the palette's surface at high-but-not-opaque alpha, so what is
        // behind the window still reads through it (docs/LESSONS.md 9.1).
        color: Qt.rgba(Colors.surface.r, Colors.surface.g, Colors.surface.b,
                       Colors.isDarkMode ? 0.82 : 0.88)

        // A single hairline rim, brightest at the top: a panel, not a box.
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, Colors.isDarkMode ? 0.10 : 0.55)
        }

        // The accent glint the shell's own cards carry, at a fraction of its glow.
        Rectangle {
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                topMargin: 1
                leftMargin: parent.radius
                rightMargin: parent.radius
            }
            height: 1
            color: Qt.rgba(Colors.primary.r, Colors.primary.g, Colors.primary.b, 0.22)
        }
    }
}
