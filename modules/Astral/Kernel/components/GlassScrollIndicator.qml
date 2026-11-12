// The shell's scroll affordance: a draggable capsule on the trailing edge of a
// Flickable.

import "../theme"
import QtQuick

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
    readonly property real barHeight: scrollable ? Math.max(minimumBarHeight, trackHeight * trackHeight / contentHeight) : 0
    /// Travel available to the bar, and how far through the content we are.
    readonly property real travel: Math.max(0, trackHeight - barHeight)
    readonly property real progress: {
        if (!scrollable)
            return 0;

        const offset = flickable.contentY - flickable.originY;
        return Math.max(0, Math.min(1, offset / scrollRange));
    }
    /// The interactive strip; exposed so tests can drive a drag.
    property alias dragAreaItem: dragArea
    /// The visible capsule; exposed for the overlay-scroller tests.
    property alias barItem: bar
    /// The shared wheel handler, when this flickable has one. A wheel-driven
    /// scroll does not set Flickable.moving, so the bar must follow the
    /// handler's animating state to fade in while the content glides.
    readonly property var scrollHandler: (flickable && flickable.wheelHandler) ? flickable.wheelHandler : null
    readonly property bool wheelAnimating: scrollHandler ? scrollHandler.animating : false
    /// Keep the bar visible briefly after the momentum stops, like macOS's
    /// overlay scrollers, instead of blinking out on the last frame.
    property bool scrollHold: false
    readonly property bool active: (flickable && (flickable.moving || flickable.dragging)) || wheelAnimating || scrollHold || dragArea.pressed || dragArea.containsMouse

    /// Content offset that puts the bar's top edge at `barTop`.
    function contentYForBarTop(barTop) {
        if (!flickable)
            return 0;

        if (!scrollable || travel <= 0)
            return flickable.originY;

        const clamped = Math.max(0, Math.min(travel, barTop));
        return flickable.originY + (clamped / travel) * scrollRange;
    }

    visible: scrollable
    width: hitWidth
    implicitHeight: trackHeight

    Connections {
        function onScrollStarted() {
            root.scrollHold = true;
            scrollHoldTimer.restart();
        }

        function onScrollEnded() {
            root.scrollHold = true;
            scrollHoldTimer.restart();
        }

        target: root.scrollHandler
    }

    Timer {
        id: scrollHoldTimer

        interval: 700
        onTriggered: root.scrollHold = false
    }

    Rectangle {
        id: bar

        readonly property real expandedWidth: root.barWidth * 2.4

        anchors.right: parent.right
        width: (dragArea.containsMouse || dragArea.pressed) ? expandedWidth : root.barWidth
        height: root.barHeight
        radius: width / 2
        color: root.color
        y: root.progress * root.travel
        opacity: root.active ? root.activeOpacity : root.restingOpacity

        Behavior on opacity {
            NumberAnimation {
                duration: (typeof Theme !== "undefined") ? Theme.animExpressiveFastEffects : 150
            }

        }

        Behavior on width {
            NumberAnimation {
                duration: (typeof Theme !== "undefined") ? Theme.animExpressiveFastEffects : 150
                easing.type: Easing.BezierSpline
                easing.bezierCurve: (typeof Theme !== "undefined" && Theme.curveExpressiveFastEffects) ? Theme.curveExpressiveFastEffects : [0.31, 0.94, 0.34, 1, 1, 1]
            }

        }

    }

    // Dragging the bar scrolls the flickable. Pressing the track grabs the bar
    // under the pointer instead of paging, so a click jumps and the same press
    // can be dragged straight on into a scrub.
    MouseArea {
        id: dragArea

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

        // Exposed for the drag contract test; the shell never reaches for it.
        anchors.fill: parent
        enabled: root.scrollable
        hoverEnabled: true
        // Never a resize cursor: this strip scrolls the content, and the window's
        // own resize handles live further out on the card's edge.
        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.ArrowCursor
        onPressed: (mouse) => {
            return beginDrag(mouse.y);
        }
        onPositionChanged: (mouse) => {
            if (pressed)
                dragTo(mouse.y);

        }
    }

}
