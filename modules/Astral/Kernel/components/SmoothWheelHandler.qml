// ============================================================================
// Smooth wheel scrolling
// ============================================================================
// Drop this handler inside any Flickable, ListView, or GridView:
//     SmoothFlickable {
//         id: page
//         SmoothWheelHandler { flickable: page }
//     }

import QtQuick
import "ScrollPhysics.js" as Physics

// A wheel step adds a velocity impulse and a target offset. A frame-synced
// spring-damper integrates the viewport toward that target, so the content has
// momentum and overshoots its bounds elastically instead of easing on a fixed
// duration. At a boundary the wheel is handed to the nearest ancestor scrollable,
// and the event is always consumed so Flickable's own jump-by-a-whole-notch
// wheelEvent never runs underneath.
WheelHandler {
    id: root

    required property Flickable flickable
    property real speed: 1
    property real velocity: 0
    property real targetX: root.flickable ? root.flickable.contentX : 0
    property real targetY: root.flickable ? root.flickable.contentY : 0
    /// Introspection for tests: how many wheel events this handler has seen.
    property int wheelEvents: 0
    property Connections flickableConnections
    property FrameAnimation physicsFrame
    readonly property bool animating: physicsFrame.running
    readonly property bool scrollable: root.flickable !== null && root.flickable.interactive && root.flickable.enabled
    readonly property bool canScrollVertically: root.scrollable && root.flickable.contentHeight > root.flickable.height + 0.5 && root.flickable.flickableDirection !== Flickable.HorizontalFlick
    readonly property bool canScrollHorizontally: root.scrollable && root.flickable.contentWidth > root.flickable.width + 0.5 && root.flickable.flickableDirection !== Flickable.VerticalFlick

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
    /// Returns true only when this surface actually took the wheel.
    function scrollBy(dx, dy) {
        if (!root.flickable)
            return false;

        if (root.canScrollBy(0, dy)) {
            root.targetY = Physics.targetFor(root.targetY, dy * root.speed, root.maxY());
            root.velocity -= dy * root.speed * Physics.SCROLL_IMPULSE;
            root.scrollStarted();
            root.physicsFrame.running = true;
            return true;
        }
        if (root.canScrollBy(dx, 0)) {
            root.targetX = Physics.targetFor(root.targetX, dx * root.speed, root.maxX());
            root.velocity -= dx * root.speed * Physics.SCROLL_IMPULSE;
            root.scrollStarted();
            root.physicsFrame.running = true;
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

    /// A wheel at a top-level boundary has nowhere to go. Give it a short
    /// rubber-band impulse instead of swallowing it, so the spring pulls the
    /// content back with visible elasticity. A nested surface with a scrollable
    /// ancestor delegates instead and never bounces inside the parent.
    function bounce(dx, dy) {
        if (!root.flickable)
            return false;

        if (root.canScrollVertically && dy !== 0) {
            root.targetY = Physics.clamp(root.flickable.contentY, 0, root.maxY());
            root.velocity -= dy * root.speed * Physics.SCROLL_IMPULSE * 0.6;
            root.scrollStarted();
            root.physicsFrame.running = true;
            return true;
        }
        if (root.canScrollHorizontally && dx !== 0) {
            root.targetX = Physics.clamp(root.flickable.contentX, 0, root.maxX());
            root.velocity -= dx * root.speed * Physics.SCROLL_IMPULSE * 0.6;
            root.scrollStarted();
            root.physicsFrame.running = true;
            return true;
        }
        return false;
    }

    function syncTargets() {
        if (!root.flickable)
            return ;

        root.targetX = root.flickable.contentX;
        root.targetY = root.flickable.contentY;
        root.velocity = 0;
    }

    function stopPhysics() {
        root.physicsFrame.running = false;
        root.velocity = 0;
    }

    /// One frame of the spring-damper. `dt` comes from FrameAnimation, clamped
    /// so a stalled frame cannot fling the content.
    function step(dt) {
        if (!root.flickable) {
            root.stopPhysics();
            return ;
        }
        const stepDt = Math.max(1 / 240, Math.min(dt > 0 ? dt : 1 / 60, 1 / 30));
        if (root.canScrollVertically) {
            const next = Physics.step(root.flickable.contentY, root.velocity, root.targetY, stepDt);
            root.flickable.contentY = next.position;
            root.velocity = next.velocity;
            if (Physics.settled(next.position, next.velocity, root.targetY)) {
                root.flickable.contentY = root.targetY;
                root.stopPhysics();
            }
        } else if (root.canScrollHorizontally) {
            const next = Physics.step(root.flickable.contentX, root.velocity, root.targetX, stepDt);
            root.flickable.contentX = next.position;
            root.velocity = next.velocity;
            if (Physics.settled(next.position, next.velocity, root.targetX)) {
                root.flickable.contentX = root.targetX;
                root.stopPhysics();
            }
        } else {
            root.stopPhysics();
        }
    }

    target: root.flickable
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    onWheel: (event) => {
        if (!root.flickable)
            return ;

        root.wheelEvents += 1;
        const dx = Physics.axisDelta(event, "x");
        const dy = Physics.axisDelta(event, "y");
        if (!root.scrollBy(dx, dy) && !root.scrollAncestor(dx, dy))
            root.bounce(dx, dy);

        // Flickable has its own wheelEvent that jumps by a whole angle delta.
        // The handler is the one scroll path, so consume the event even when
        // this surface (and its ancestors) cannot use it.
        event.accepted = true;
    }

    /// A drag or a native flick owns the position; stop fighting it.
    flickableConnections: Connections {
        function onMovementStarted() {
            root.stopPhysics();
            root.syncTargets();
        }

        function onContentYChanged() {
            if (!root.animating)
                root.targetY = root.flickable.contentY;

        }

        function onContentXChanged() {
            if (!root.animating)
                root.targetX = root.flickable.contentX;

        }

        target: root.flickable
    }

    /// Frame-synced physics. It only runs while a wheel gesture is settling.
    physicsFrame: FrameAnimation {
        running: false
        onTriggered: root.step(frameTime)
    }

}
