.pragma library

// ============================================================================
// Scroll physics
// ============================================================================
// One place for the numbers every scrollable surface uses. The wheel handler is
// intentionally thin: it asks this file how far a wheel event should move, how
// the spring-damper should integrate the next frame, and how to clamp the target.

/// One mouse-wheel notch is 120 angle units. Treat it as 60 px of content, so a
/// notch glides instead of jumping a whole screen line.
var ANGLE_TO_PIXELS = 0.5;

/// Shared drag/flick physics. A flick keeps gliding long enough to read as
/// motion, and the velocity ceiling is high enough for a trackpad flick without
/// letting a mouse notch throw the content across the page.
var FLICK_DECELERATION = 1500;
var MAXIMUM_FLICK_VELOCITY = 4000;

/// Spring-damper for wheel scrolling. The spring pulls the viewport toward the
/// accumulated wheel target; the damper lets it overshoot slightly and settle
/// instead of stopping on a fixed-duration tween. A 60 px notch peaks around
/// 5 px past its target and settles in roughly 0.45 s - responsive, with a
/// visible elastic tail.
var SCROLL_STIFFNESS = 240;
var SCROLL_DAMPING = 17;
var SCROLL_IMPULSE = 10;
var SCROLL_STOP_VELOCITY = 3;
var SCROLL_STOP_DISTANCE = 0.5;

/// The wheel delta along one axis. High-resolution trackpads report pixelDelta;
/// a classic wheel reports angleDelta. Never mix them in one event.
function axisDelta(event, axis) {
    if (!event) return 0;
    const pixel = axis === "x" ? event.pixelDelta.x : event.pixelDelta.y;
    if (pixel !== 0) return pixel;
    const angle = axis === "x" ? event.angleDelta.x : event.angleDelta.y;
    return angle * ANGLE_TO_PIXELS;
}

/// Clamp a content offset to the flickable's scrollable range.
function clamp(value, minimum, maximum) {
    return Math.max(minimum, Math.min(maximum, value));
}

/// The next target for a content offset after a wheel delta. Positive delta
/// means "scroll up/left", which reduces the content offset.
function targetFor(current, delta, maximum) {
    return clamp(current - delta, 0, maximum);
}

/// One spring-damper step. `position` and `velocity` are the current content
/// offset and px/s; `target` is the accumulated wheel goal. Returns the next
/// position/velocity. The target is clamped by the caller, while the position is
/// allowed past the bounds so the spring can produce a rubber-band overscroll.
function step(position, velocity, target, dt) {
    const force = (target - position) * SCROLL_STIFFNESS - velocity * SCROLL_DAMPING;
    const nextVelocity = velocity + force * dt;
    return {
        position: position + nextVelocity * dt,
        velocity: nextVelocity
    };
}

/// Has the spring come to rest at its target?
function settled(position, velocity, target) {
    return Math.abs(velocity) < SCROLL_STOP_VELOCITY
        && Math.abs(target - position) < SCROLL_STOP_DISTANCE;
}
