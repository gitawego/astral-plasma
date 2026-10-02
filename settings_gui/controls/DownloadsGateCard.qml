import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../components"

// The refusal card for a tab whose dependency is missing.
//
// Shown where the user tried to switch such a tab on. It explains what is
// missing and offers both fixes: install it through the desktop's own password
// dialog, or copy the command for a terminal. Dumb control: it renders and
// reports, the page owns the side effects (and the offscreen harness can
// instantiate it directly).
Rectangle {
    id: card

    Layout.fillWidth: true
    radius: Theme.radiusMedium
    color: Colors.surfaceContainer
    implicitHeight: cardCol.implicitHeight + Theme.padLarge * 2

    /// Explanation shown at the top of the card.
    property string message: ""
    /// Whether the native authentication dialog can be raised.
    property bool installable: true
    /// The command offered as the manual fallback.
    property string installCommand: ""

    signal installRequested()
    signal copyRequested()

    /// Test / introspection surface.
    property alias messageTextItem: gateText
    property alias installButtonItem: installButton
    property alias copyButtonItem: copyButton
    property alias commandTextItem: commandText

    ColumnLayout {
        id: cardCol
        anchors.fill: parent
        anchors.margins: Theme.padLarge
        spacing: 8

        Text {
            id: gateText
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: card.message
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontBodySmall
            color: Colors.m3onSurface
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spaceSmall

            PillButton {
                id: installButton
                visible: card.installable
                label: "Install aria2"
                variant: "filled"
                onClicked: card.installRequested()
            }

            PillButton {
                id: copyButton
                label: "Copy command"
                onClicked: card.copyRequested()
            }

            Text {
                id: commandText
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: card.installCommand
                font.family: Theme.fontFamily
                font.pixelSize: 12
                color: Colors.m3onSurfaceVariant
                opacity: 0.85
            }
        }
    }
}
