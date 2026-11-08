import QtQuick
import QtQuick.Layouts
import "../theme"

// ============================================================================
// Section header
// ============================================================================
// The page's hierarchy in one control: an eyebrow that carries the section's live
// state, the section's plain-language name, and a slot for the controls that
// belong to it.
//
// The eyebrow is deliberately *not* a decorative index ("01 / 02"): this page has
// no sequence, it has state. So the small caps line is where the count, the
// next deadline or the readiness lives, which is what makes a section header
// worth reading at a glance - and what lets a collapsed section still inform.
Item {
    id: root

    Layout.fillWidth: true

    /// Live state line, uppercase by the control ("3 providers · next reset in 3h 40m").
    property string eyebrow: ""
    /// Plain-language section name ("Quotas", "Copilot", "Setup").
    property string title: ""
    /// Optional slot for the section's own controls (a switch, a button).
    default property alias actions: actionSlot.data

    implicitHeight: column.implicitHeight

    /// Test / introspection surface.
    property alias eyebrowItem: eyebrowText
    property alias titleItem: titleText

    ColumnLayout {
        id: column
        width: parent.width
        spacing: 2

        Text {
            id: eyebrowText
            Layout.fillWidth: true
            visible: root.eyebrow !== ""
            text: root.eyebrow.toUpperCase()
            font.family: Theme.fontFamily
            font.pixelSize: 10
            font.weight: Font.DemiBold
            // Tracking on the eyebrow is what separates it from body text at a
            // glance; the value is the shell's small-caps convention.
            font.letterSpacing: 1.2
            color: Colors.m3onSurfaceVariant
            opacity: 0.85
            elide: Text.ElideRight
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spaceSmall

            Text {
                id: titleText
                text: root.title
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontTitleMedium
                font.weight: Font.Bold
                color: Colors.m3onSurface
            }

            Item { Layout.fillWidth: true }

            RowLayout {
                id: actionSlot
                spacing: Theme.spaceSmall
            }
        }
    }
}
