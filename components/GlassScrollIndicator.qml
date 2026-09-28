import QtQuick
import "../theme"

// The shell's scroll affordance: a draggable capsule on the trailing edge of a
// Flickable.
//
// It exists because a scrollable surface that draws nothing reads as a *clipped*
// one - the Copilot chat looked cut off with no hint that there was more, and a
// bar you cannot grab is only half an affordance. One implementation, so the
// dock's popout menu and the chat stream cannot drift apart.
Item {
    id: root

    /// The flickable this indicator tracks.
    required property Flickable flickable
    /// Bar colour; defaults to the palette's primary.
    property color color: (typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#9bcbfb"
    /// Opacity when idle. A stream keeps its bar faintly visible so the reader
    /// knows more content exists; a transient menu sets 0 so the bar only
    /// appears while the menu is actually being scrolled.
    property real restingOpacity: 0.35
    /// Opacity while the flickable moves or the bar is being dragged.
    property real activeOpacity: 0.85
    /// Never shrink the bar below this, or a very long document becomes a dot.
    property real minimumBarHeight: 24
    /// Track thickness of the visible bar.
    property real barWidth: 3
    /// Width of the interactive strip. Wider than the bar on purpose: a 3px
    /// capsule is not a pointer target.
    property real hitWidth: 12

    readonly property real trackHeight: flickable ? Math.max(0, flickable.height) : 0
    readonly property real contentHeight: flickable ? Math.max(0, flickable.contentHeight) : 0
    readonly property real scrollRange: Math.max(0, contentHeight - trackHeight)
    readonly property bool scrollable: contentHeight > trackHeight + 1
    readonly property real barHeight: scrollable
        ? Math.max(minimumBarHeight, trackHeight * trackHeight / contentHeight)
        : 0
    /// Travel available to the bar, and how far through the content we are.
    readonly property real travel: Math.max(0, trackHeight - barHeight)
    readonly property real progress: {
        if (!scrollable) return 0;
        const offset = flickable.contentY - flickable.originY;
        return Math.max(0, Math.min(1, offset / scrollRange));
    }

    /// Content offset that puts the bar's top edge at `barTop`.
    function contentYForBarTop(barTop) {
        if (!flickable) return 0;
        if (!scrollable || travel <= 0) return flickable.originY;
        const clamped = Math.max(0, Math.min(travel, barTop));
        return flickable.originY + (clamped / travel) * scrollRange;
    }

    /// The interactive strip; exposed so tests can drive a drag.
    property alias dragAreaItem: dragArea

    visible: scrollable
    width: hitWidth
    implicitHeight: trackHeight

    Rectangle {
        id: bar
        anchors.right: parent.right
        width: root.barWidth
        height: root.barHeight
        radius: width / 2
        color: root.color
        y: root.progress * root.travel
        opacity: ((root.flickable && (root.flickable.moving || root.flickable.dragging)) || dragArea.pressed)
            ? root.activeOpacity
            : root.restingOpacity

        Behavior on opacity {
            NumberAnimation { duration: (typeof Theme !== "undefined") ? Theme.animExpressiveFastEffects : 150 }
        }
    }

    // Dragging the bar scrolls the flickable. Pressing the track grabs the bar
    // under the pointer instead of paging, so a click jumps and the same press
    // can be dragged straight on into a scrub.
    MouseArea {
        id: dragArea
        // Exposed for the drag contract test; the shell never reaches for it.
        anchors.fill: parent
        enabled: root.scrollable
        hoverEnabled: true
        // Never a resize cursor: this strip scrolls the content, and the window's
        // own resize handles live further out on the card's edge.
        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.ArrowCursor

        property real grabOffset: 0

        function beginDrag(pointerY) {
            const barTop = root.progress * root.travel;
            const onBar = pointerY >= barTop && pointerY <= barTop + root.barHeight;
            grabOffset = onBar ? (pointerY - barTop) : root.barHeight / 2;
            dragTo(pointerY);
        }

        /// Move the grabbed bar to follow the pointer.
        function dragTo(pointerY) {
            root.flickable.contentY = root.contentYForBarTop(pointerY - grabOffset);
        }

        onPressed: mouse => beginDrag(mouse.y)
        onPositionChanged: mouse => {
            if (pressed) dragTo(mouse.y);
        }
    }
}
