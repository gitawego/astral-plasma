// ============================================================================
// Smooth wheel scrolling
// ============================================================================
// Drop this handler inside any Flickable, ListView, or GridView:
//     SmoothFlickable {
//         id: page
//         SmoothWheelHandler { flickable: page }
//     }
// This follows the macOS model rather than a target spring:
//   * each wheel/trackpad delta adds an impulse to the velocity;
//   * velocity decays exponentially, so fast gestures travel farther and then
//     ease out without oscillating around a target;
//   * at an edge the raw position is mapped through the UIScrollView
//     rubber-band curve, and a damped spring returns it.

import QtQuick
import "ScrollPhysics.js" as Physics

// One axis is latched for the duration of a gesture. A same-axis edge bounces
// (macOS latching); a cross-axis wheel is handed to the nearest ancestor so a
// horizontal chip row does not swallow a vertical page scroll. The event is
// always consumed, which keeps Flickable's own jump-by-a-whole-notch
// wheelEvent from running underneath.
WheelHandler {
    id: root

    required property Flickable flickable
    property real speed: 1
    property real velocity: 0
    /// Unbounded position on the active axis. The displayed content offset is
    /// this value mapped through the rubber band at the edges.
    property real rawY: root.flickable ? root.flickable.contentY : 0
    property real rawX: root.flickable ? root.flickable.contentX : 0
    property bool verticalAxis: true
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
    /// Emitted when the momentum/edge spring comes to rest.
    signal scrollEnded()

    function maxX() {
        return root.flickable ? Math.max(0, root.flickable.contentWidth - root.flickable.width) : 0;
    }

    function maxY() {
        return root.flickable ? Math.max(0, root.flickable.contentHeight - root.flickable.height) : 0;
    }

    /// Public seam for tests and for callers that already normalized a delta.
    /// Returns true when this surface latched the gesture, including at an edge
    /// where the impulse becomes a rubber-band bounce.
    function scrollBy(dx, dy) {
        if (!root.flickable)
            return false;

        if (root.canScrollVertically && dy !== 0) {
            root.verticalAxis = true;
            if (!root.animating)
                root.rawY = root.flickable.contentY;

            root.velocity = Physics.clamp(root.velocity - dy * root.speed * Physics.SCROLL_IMPULSE, -Physics.SCROLL_MAX_VELOCITY, Physics.SCROLL_MAX_VELOCITY);
            root.scrollStarted();
            root.physicsFrame.running = true;
            return true;
        }
        if (root.canScrollHorizontally && dx !== 0) {
            root.verticalAxis = false;
            if (!root.animating)
                root.rawX = root.flickable.contentX;

            root.velocity = Physics.clamp(root.velocity - dx * root.speed * Physics.SCROLL_IMPULSE, -Physics.SCROLL_MAX_VELOCITY, Physics.SCROLL_MAX_VELOCITY);
            root.scrollStarted();
            root.physicsFrame.running = true;
            return true;
        }
        return false;
    }

    /// Hand a cross-axis wheel to the nearest ancestor that can use it. A
    /// horizontal chip row does not swallow a vertical page scroll.
    function scrollAncestor(dx, dy) {
        let node = root.flickable ? root.flickable.parent : null;
        while (node) {
            const handler = node.wheelHandler;
            if (handler && typeof handler.scrollBy === "function" && handler.scrollBy(dx, dy))
                return true;

            node = node.parent;
        }
        return false;
    }

    function syncPosition() {
        if (!root.flickable)
            return ;

        root.rawX = root.flickable.contentX;
        root.rawY = root.flickable.contentY;
        root.velocity = 0;
    }

    function stopPhysics() {
        const wasRunning = root.physicsFrame.running;
        root.physicsFrame.running = false;
        root.velocity = 0;
        if (wasRunning)
            root.scrollEnded();
    }

    /// One frame of momentum + edge return. `dt` comes from FrameAnimation,
    /// clamped so a stalled frame cannot fling the content.
    function step(dt) {
        if (!root.flickable) {
            root.stopPhysics();
            return ;
        }
        const stepDt = Math.max(1 / 240, Math.min(dt > 0 ? dt : 1 / 60, 1 / 30));
        if (root.verticalAxis && root.canScrollVertically) {
            const maximum = root.maxY();
            const free = Physics.advance(root.rawY, root.velocity, stepDt);
            const raw = free.position;
            const velocity = Physics.applyEdge(raw, free.velocity, 0, maximum, stepDt);
            root.rawY = raw;
            root.velocity = velocity;
            root.flickable.contentY = Physics.displayed(raw, 0, maximum, root.flickable.height);
            if (Physics.settled(raw, velocity, 0, maximum)) {
                root.flickable.contentY = Physics.snapped(raw, 0, maximum);
                root.stopPhysics();
            }
            return ;
        }
        if (!root.verticalAxis && root.canScrollHorizontally) {
            const maximum = root.maxX();
            const free = Physics.advance(root.rawX, root.velocity, stepDt);
            const raw = free.position;
            const velocity = Physics.applyEdge(raw, free.velocity, 0, maximum, stepDt);
            root.rawX = raw;
            root.velocity = velocity;
            root.flickable.contentX = Physics.displayed(raw, 0, maximum, root.flickable.width);
            if (Physics.settled(raw, velocity, 0, maximum)) {
                root.flickable.contentX = Physics.snapped(raw, 0, maximum);
                root.stopPhysics();
            }
            return ;
        }
        root.stopPhysics();
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

    /// A drag or a native flick owns the position; stop fighting it.
    flickableConnections: Connections {
        function onMovementStarted() {
            root.stopPhysics();
            root.syncPosition();
        }

        function onContentYChanged() {
            if (!root.animating)
                root.rawY = root.flickable.contentY;

        }

        function onContentXChanged() {
            if (!root.animating)
                root.rawX = root.flickable.contentX;

        }

        target: root.flickable
    }

    /// Frame-synced physics. It only runs while a wheel gesture is settling.
    physicsFrame: FrameAnimation {
        running: false
        onTriggered: root.step(frameTime)
    }

}
