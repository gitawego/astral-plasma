import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../theme"
import "../components"
import "../services"

// ============================================================================
// Update curtain
// ============================================================================
// A short, honest surface for the one moment the shell is not there: while an
// update restarts it. It appears only when the daemon reports that an update is
// being applied, shows the version it was told, and disappears when the new
// shell comes up (this process ends, so the curtain cannot linger).
//
// It is deliberately not a progress bar: the shell cannot observe a download it
// does not perform, and a fake percentage is the one thing this project forbids.
PanelWindow {
    id: root

    property ShellScreen targetScreen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
    screen: targetScreen

    readonly property bool openRequested: (typeof Updates !== "undefined") && Updates.applying

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "astral-plasma-update"
    color: "transparent"
    visible: root.openRequested || root.fade > 0

    property real fade: 0
    Behavior on fade {
        NumberAnimation {
            duration: root.openRequested ? Theme.animExpressiveFastEffects : Theme.animDurationFast
            easing.bezierCurve: Theme.curveStandard
        }
    }
    onOpenRequestedChanged: root.fade = root.openRequested ? 1 : 0
    Component.onCompleted: root.fade = root.openRequested ? 1 : 0

    // Swallow pointer input so the desktop underneath cannot be clicked mid-swap.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        hoverEnabled: true
        onClicked: (mouse) => mouse.accepted = true
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.alpha("#000000", 0.28 * root.fade)

        ColumnLayout {
            anchors.centerIn: parent
            spacing: Theme.spaceMedium

            GlassCard {
                implicitWidth: cardLayout.implicitWidth + Theme.padLarge * 2
                implicitHeight: cardLayout.implicitHeight + Theme.padLarge * 2
                opacity: root.fade

                ColumnLayout {
                    id: cardLayout
                    anchors.centerIn: parent
                    spacing: Theme.spaceSmall

                    RowLayout {
                        spacing: Theme.spaceMedium

                        MaterialIcon {
                            text: "system_update"
                            size: 22
                            color: Colors.primary
                        }

                        Text {
                            text: "Restarting Astral Plasma"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontTitleMedium
                            font.weight: Font.DemiBold
                            color: Colors.m3onSurface
                        }
                    }

                    Text {
                        text: (typeof Updates !== "undefined" && Updates.restartPending !== "")
                            ? "Installing " + Updates.restartPending + ". Your desktop stays as it is."
                            : "Installing the update. Your desktop stays as it is."
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontBodySmall
                        color: Colors.m3onSurfaceVariant
                    }

                    Text {
                        text: "The shell comes back on its own; nothing needs restarting."
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontBodySmall
                        color: Qt.alpha(Colors.m3onSurfaceVariant, 0.8)
                    }
                }
            }
        }
    }
}
