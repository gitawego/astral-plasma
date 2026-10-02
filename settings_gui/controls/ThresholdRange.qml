import QtQuick
import QtQuick.Layouts
import "../../theme"

// ============================================================================
// Threshold range
// ============================================================================
// The amber and rose quota warnings as **one** control instead of two sliders.
// Their relationship is the information: a warning threshold that is allowed to
// cross its own critical threshold is a configuration bug the user cannot see
// when the two values live in separate widgets. Here the gap is enforced and
// drawn (the span between the handles is the warning band), and one drag moves
// the boundary the user grabbed without disturbing the other.
//
// Interaction: click or drag a handle, or focus the control and use Left/Right
// (Shift for 5% steps), Tab or Up/Down to switch handles. Clamping rules are pure
// and asserted by `tests/tst_ai_page_controls.qml`.
Item {
    id: root

    implicitHeight: 56
    Layout.fillWidth: true

    property real warning: 80
    property real critical: 95
    property real min: 50
    property real max: 100
    /// Smallest allowed gap, so the band never collapses into a single line.
    property real minGap: 5
    /// "warning" | "critical" - the handle a keyboard nudge or a click targets.
    property string activeHandle: "warning"
    /// The band's own name, for the caption.
    property string title: "Warning thresholds"

    signal rangeModified(real warning, real critical)

    /// Handle diameter, and the track geometry derived from it. The track is
    /// inset by half a handle so the end positions are reachable instead of
    /// hanging over the edges.
    readonly property real knobSize: 14
    readonly property real trackLeft: root.knobSize / 2
    readonly property real trackWidth: Math.max(1, root.width - root.knobSize)

    function fractionFor(value) {
        const span = root.max - root.min;
        if (span <= 0) return 0;
        return Math.max(0, Math.min(1, (value - root.min) / span));
    }

    /// Set the amber handle, keeping it below the rose one.
    function setWarning(value) {
        const next = Math.max(root.min, Math.min(root.critical - root.minGap, Math.round(value)));
        if (next === root.warning) return;
        root.warning = next;
        root.rangeModified(root.warning, root.critical);
    }

    /// Set the rose handle, keeping it above the amber one.
    function setCritical(value) {
        const next = Math.min(root.max, Math.max(root.warning + root.minGap, Math.round(value)));
        if (next === root.critical) return;
        root.critical = next;
        root.rangeModified(root.warning, root.critical);
    }

    function nudge(delta) {
        if (root.activeHandle === "warning") root.setWarning(root.warning + delta);
        else root.setCritical(root.critical + delta);
    }

    function pickHandle(x) {
        const warningX = root.trackLeft + root.trackWidth * root.fractionFor(root.warning);
        const criticalX = root.trackLeft + root.trackWidth * root.fractionFor(root.critical);
        return Math.abs(x - warningX) <= Math.abs(x - criticalX) ? "warning" : "critical";
    }

    property alias warningKnobItem: warningKnob
    property alias criticalKnobItem: criticalKnob
    property alias trackItem: track
    property alias captionItem: caption

    focus: true
    activeFocusOnTab: true
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Left) { root.nudge(event.modifiers & Qt.ShiftModifier ? -5 : -1); event.accepted = true; }
        else if (event.key === Qt.Key_Right) { root.nudge(event.modifiers & Qt.ShiftModifier ? 5 : 1); event.accepted = true; }
        else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Up || event.key === Qt.Key_Down) {
            root.activeHandle = root.activeHandle === "warning" ? "critical" : "warning";
            event.accepted = true;
        }
    }

    Text {
        id: caption
        anchors.left: parent.left
        anchors.top: parent.top
        text: root.title + " · warn at " + Math.round(root.warning) + "%, critical at " + Math.round(root.critical) + "%"
        font.family: Theme.fontFamily
        font.pixelSize: 12
        color: Colors.m3onSurface
    }

    // Track: the whole range, with the warning band drawn between the handles.
    Rectangle {
        id: track
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 6
        height: 6
        radius: Theme.radiusFull
        color: Qt.alpha(Colors.outlineVariant, 0.35)

        // The band between the two thresholds: amber at the warning edge, rose at
        // the critical edge, so the control shows the ramp it configures.
        Rectangle {
            x: warningKnob.x
            width: Math.max(0, criticalKnob.x - warningKnob.x)
            height: parent.height
            radius: Theme.radiusFull
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: Colors.warning }
                GradientStop { position: 1.0; color: Colors.error }
            }
        }
    }

    Rectangle {
        id: warningKnob
        width: root.knobSize
        height: root.knobSize
        radius: root.knobSize / 2
        x: root.trackLeft + root.trackWidth * root.fractionFor(root.warning) - width / 2
        anchors.verticalCenter: track.verticalCenter
        color: Colors.warning
        border.width: root.activeHandle === "warning" && root.activeFocus ? 2 : 0
        border.color: Colors.m3onSurface
    }

    Rectangle {
        id: criticalKnob
        width: root.knobSize
        height: root.knobSize
        radius: root.knobSize / 2
        x: root.trackLeft + root.trackWidth * root.fractionFor(root.critical) - width / 2
        anchors.verticalCenter: track.verticalCenter
        color: Colors.error
        border.width: root.activeHandle === "critical" && root.activeFocus ? 2 : 0
        border.color: Colors.m3onSurface
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPressed: mouse => {
            root.forceActiveFocus();
            root.activeHandle = root.pickHandle(mouse.x);
            root.dragHandle(mouse.x);
        }
        onPositionChanged: mouse => {
            if (mouse.pressed) root.dragHandle(mouse.x);
        }
    }

    /// Drag the active handle to a track position.
    function dragHandle(x) {
        const fraction = Math.max(0, Math.min(1, (x - root.trackLeft) / root.trackWidth));
        const value = root.min + fraction * (root.max - root.min);
        if (root.activeHandle === "warning") root.setWarning(value);
        else root.setCritical(value);
    }
}
