import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../components"
import "../../components/StateColor.js" as StateColor

// ============================================================================
// Setup group
// ============================================================================
// The setup tail of a page, collapsed: engine updates, sign-ins, model
// downloads. Each row states its own condition in one line, and the group opens
// itself exactly when something needs the user - so a healthy machine shows a
// page you can read in one screen, and a broken one opens on the broken part.
//
// Pure state logic, asserted by `tests/tst_ai_page_controls.qml`: a user who has
// opened or closed the group keeps that choice; otherwise `needsAttention` decides.
Rectangle {
    id: root

    Layout.fillWidth: true
    radius: root.flat ? 0 : Theme.radiusMedium
    color: root.flat ? "transparent" : Colors.surfaceContainer
    border.color: Theme.borderSubtle
    border.width: root.flat ? 0 : 1
    implicitHeight: column.implicitHeight + (root.flat ? 0 : Theme.padLarge * 2)

    // Motion tokens, with fallbacks so the offscreen harness (where Theme
    // resolves without an archetype) does not warn on every assignment.
    readonly property int motionFast: (typeof Theme !== "undefined" && Theme.animExpressiveFastEffects !== undefined)
        ? Theme.animExpressiveFastEffects : 150
    readonly property int motionSpatial: (typeof Theme !== "undefined" && Theme.animExpressiveDefaultSpatial !== undefined)
        ? Theme.animExpressiveDefaultSpatial : 400
    readonly property var motionSpatialCurve: (typeof Theme !== "undefined" && Theme.curveExpressiveDefaultSpatial !== undefined)
        ? Theme.curveExpressiveDefaultSpatial : [0.2, 0.0, 0.0, 1.0]

    /// Plain-language row name ("Pi harness", "Sign-ins", "Voice input").
    property string title: ""
    /// One line of state in the interface's voice ("pi 1.0.0, up to date").
    property string summary: ""
    /// "ok" | "attention" | "busy" | "unknown"
    property string state: "ok"
    /// Nesting mode: no surface of its own, for use inside another card.
    property bool flat: false
    /// State-driven opening: true when this group has something for the user.
    property bool needsAttention: false
    /// The user's own choice, once they make one (sticky either way).
    property bool userOpen: false
    property bool userClosed: false

    readonly property bool expanded: root.userClosed ? false : (root.userOpen || root.needsAttention)

    /// The group's content.
    default property alias body: bodySlot.data

    signal toggled(bool open)

    function toggle() {
        if (root.expanded) {
            root.userOpen = false;
            root.userClosed = true;
        } else {
            root.userOpen = true;
            root.userClosed = false;
        }
        root.toggled(root.expanded);
    }

    /// Test / introspection surface.
    property alias headerItem: header
    property alias summaryItem: summaryText
    property alias stateDotItem: dot
    property alias bodyItem: bodySlot
    property alias bodyContainerItem: bodyContainer

    /// Colour of the state dot, through the shell's shared state vocabulary
    /// (`components/StateColor.js`), so every reporting control agrees.
    readonly property color stateColor: StateColor.colorFor(root.state, Colors)
    /// The `Colors` role this state maps to (test / introspection surface).
    readonly property string stateRole: StateColor.roleFor(root.state)

    ColumnLayout {
        id: column
        anchors.fill: parent
        anchors.margins: root.flat ? 0 : Theme.padLarge
        spacing: Theme.spaceSmall

        RowLayout {
            id: header
            Layout.fillWidth: true
            spacing: Theme.spaceSmall

            Rectangle {
                id: dot
                width: 8
                height: 8
                radius: 4
                color: root.stateColor
            }

            Text {
                text: root.title
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontBodyMedium
                font.weight: Font.DemiBold
                color: Colors.m3onSurface
            }

            Text {
                id: summaryText
                Layout.fillWidth: true
                text: root.summary
                font.family: Theme.fontFamily
                font.pixelSize: 12
                color: Colors.m3onSurfaceVariant
                elide: Text.ElideRight
            }

            MaterialIcon {
                text: root.expanded ? "expand_less" : "expand_more"
                size: 18
                color: Colors.m3onSurfaceVariant

                Behavior on rotation {
                    NumberAnimation { duration: root.motionFast }
                }
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggle()
            }
        }

        // Collapsed body: clipped and height-animated, so opening a group reads as
        // the same surface growing rather than a new card appearing.
        Item {
            id: bodyContainer
            Layout.fillWidth: true
            implicitHeight: root.expanded ? (bodySlot.implicitHeight + (bodySlot.implicitHeight > 0 ? Theme.spaceSmall : 0)) : 0
            clip: true

            Behavior on implicitHeight {
                NumberAnimation {
                    duration: root.motionSpatial
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: root.motionSpatialCurve
                }
            }

            ColumnLayout {
                id: bodySlot
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.topMargin: Theme.spaceSmall
                spacing: Theme.spaceSmall
            }
        }
    }
}
