// ============================================================================
// Smooth wheel scrolling
// ============================================================================
// Drop this handler inside any Flickable, ListView, or GridView:
//     SmoothFlickable {
//         id: page
//         SmoothWheelHandler { flickable: page }
//     }

import "../theme"
import QtQuick
import "ScrollPhysics.js" as Physics

// One wheel notch moves a short distance and eases to it with the fast effects
// token; a trackpad's high-resolution pixel deltas accumulate into the same
// target, so a stream of small events reads as one continuous glide. The handler
// accepts the event only when the flickable can actually scroll in that
// direction, so a nested horizontal list cannot trap a page's vertical scroll.
WheelHandler {
    id: root

    required property Flickable flickable
    /// Overridable for tests / reduced motion. Null means "no tokens, jump".
    property var motionTokens: (typeof Theme !== "undefined") ? Theme : null
    property real speed: 1
    readonly property bool scrollable: root.flickable !== null && root.flickable.interactive && root.flickable.enabled
    readonly property bool canScrollVertically: root.scrollable && root.flickable.contentHeight > root.flickable.height + 0.5 && root.flickable.flickableDirection !== Flickable.HorizontalFlick
    readonly property bool canScrollHorizontally: root.scrollable && root.flickable.contentWidth > root.flickable.width + 0.5 && root.flickable.flickableDirection !== Flickable.VerticalFlick
    readonly property bool animating: verticalAnim.running || horizontalAnim.running
    property real targetX: root.flickable ? root.flickable.contentX : 0
    property real targetY: root.flickable ? root.flickable.contentY : 0
    /// Introspection for tests: how many wheel events this handler has seen.
    property int wheelEvents: 0
    /// A drag or a native flick owns the position; stop fighting it.
    property Connections flickableConnections
    property NumberAnimation verticalAnim
    property NumberAnimation horizontalAnim

    /// Emitted when a wheel event takes over. A host with a programmatic scroll
    /// animation (a settings section jump) stops it here instead of fighting.
    signal scrollStarted()

    function maxX() {
        return root.flickable ? Math.max(0, root.flickable.contentWidth - root.flickable.width) : 0;
    }

    function maxY() {
        return root.flickable ? Math.max(0, root.flickable.contentHeight - root.flickable.height) : 0;
    }

    /// Can a wheel step in this direction change the target? At a boundary the
    /// answer is no, so the event is left for an ancestor scrollable instead of
    /// being trapped by a surface that has nowhere left to go.
    function canScrollBy(dx, dy) {
        if (root.canScrollVertically && dy !== 0) {
            const nextY = Physics.targetFor(root.targetY, dy * root.speed, root.maxY());
            return Math.abs(nextY - root.targetY) > 0.01;
        }
        if (root.canScrollHorizontally && dx !== 0) {
            const nextX = Physics.targetFor(root.targetX, dx * root.speed, root.maxX());
            return Math.abs(nextX - root.targetX) > 0.01;
        }
        return false;
    }

    /// Public seam for tests and for callers that already normalized a delta.
    /// Returns true only when this surface actually moved.
    function scrollBy(dx, dy) {
        if (!root.flickable)
            return false;

        if (root.canScrollBy(0, dy)) {
            root.targetY = Physics.targetFor(root.targetY, dy * root.speed, root.maxY());
            root.scrollStarted();
            startVertical();
            return true;
        }
        if (root.canScrollBy(dx, 0)) {
            root.targetX = Physics.targetFor(root.targetX, dx * root.speed, root.maxX());
            root.scrollStarted();
            startHorizontal();
            return true;
        }
        return false;
    }

    /// Hand the wheel to the nearest ancestor that can use it. A nested list at
    /// its top/bottom no longer traps the page's scroll, and a horizontal chip
    /// row does not swallow a vertical wheel.
    function scrollAncestor(dx, dy) {
        let node = root.flickable ? root.flickable.parent : null;
        while (node) {
            const handler = node.wheelHandler;
            if (handler && typeof handler.canScrollBy === "function" && handler.canScrollBy(dx, dy)) {
                handler.scrollBy(dx, dy);
                return true;
            }
            node = node.parent;
        }
        return false;
    }

    function startVertical() {
        const motion = Physics.motionFor(root.motionTokens);
        if (!motion) {
            root.flickable.contentY = root.targetY;
            return ;
        }
        verticalAnim.duration = motion.duration;
        verticalAnim.easing.bezierCurve = motion.curve;
        verticalAnim.to = root.targetY;
        verticalAnim.restart();
    }

    function startHorizontal() {
        const motion = Physics.motionFor(root.motionTokens);
        if (!motion) {
            root.flickable.contentX = root.targetX;
            return ;
        }
        horizontalAnim.duration = motion.duration;
        horizontalAnim.easing.bezierCurve = motion.curve;
        horizontalAnim.to = root.targetX;
        horizontalAnim.restart();
    }

    function syncTargets() {
        if (!root.flickable)
            return ;

        root.targetX = root.flickable.contentX;
        root.targetY = root.flickable.contentY;
    }

    target: root.flickable
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    onWheel: (event) => {
        if (!root.flickable)
            return ;

        root.wheelEvents += 1;
        const dx = Physics.axisDelta(event, "x");
        const dy = Physics.axisDelta(event, "y");
        if (!root.scrollBy(dx, dy))
            root.scrollAncestor(dx, dy);

        // Flickable has its own wheelEvent that jumps by a whole angle delta.
        // The handler is the one scroll path, so consume the event even when
        // this surface (and its ancestors) cannot use it.
        event.accepted = true;
    }

    flickableConnections: Connections {
        function onMovementStarted() {
            root.verticalAnim.stop();
            root.horizontalAnim.stop();
            root.syncTargets();
        }

        function onContentYChanged() {
            if (!root.verticalAnim.running)
                root.targetY = root.flickable.contentY;

        }

        function onContentXChanged() {
            if (!root.horizontalAnim.running)
                root.targetX = root.flickable.contentX;

        }

        target: root.flickable
    }

    verticalAnim: NumberAnimation {
        target: root.flickable
        property: "contentY"
        duration: 150
        easing.type: Easing.BezierSpline
        easing.bezierCurve: [0.31, 0.94, 0.34, 1, 1, 1]
    }

    horizontalAnim: NumberAnimation {
        target: root.flickable
        property: "contentX"
        duration: 150
        easing.type: Easing.BezierSpline
        easing.bezierCurve: [0.31, 0.94, 0.34, 1, 1, 1]
    }

}
