.pragma library

// ============================================================================
// Scroll physics
// ============================================================================
// macOS-style scrolling, not a target spring:
//
//   * a wheel/trackpad delta adds an impulse to the velocity;
//   * velocity decays exponentially (momentum), so fast input goes farther and
//     then eases out instead of oscillating around a target;
//   * at an edge the raw position is mapped through the UIScrollView
//     rubber-band curve, and a damped spring returns it when the gesture ends.
//
// One place for the numbers every scrollable surface uses.

/// One mouse-wheel notch is 120 angle units. Treat it as 60 px of content, so a
/// notch glides instead of jumping a whole screen line.
var ANGLE_TO_PIXELS = 0.5;

/// Shared drag/flick physics. A flick keeps gliding long enough to read as
/// motion, and the velocity ceiling is high enough for a trackpad flick without
/// letting a mouse notch throw the content across the page.
var FLICK_DECELERATION = 1500;
var MAXIMUM_FLICK_VELOCITY = 4000;

/// Momentum. A 60 px notch gives a 1440 px/s impulse, which travels about
/// 120 px with a 12/s decay and settles in roughly half a second. Fast gestures
/// accumulate velocity up to the ceiling, so they travel farther without
/// becoming unstable.
var SCROLL_IMPULSE = 24;
var SCROLL_DECELERATION = 12;
var SCROLL_MAX_VELOCITY = 6000;

/// Edge return. The raw position may sit outside the bounds; this spring pulls
/// it back after the momentum has decayed.
var EDGE_STIFFNESS = 240;
var EDGE_DAMPING = 15;
var EDGE_STOP_DISTANCE = 0.5;
var EDGE_STOP_VELOCITY = 1;

/// UIScrollView's rubber-band constant. `displayed = raw` inside the bounds;
/// outside, the overshoot is compressed by
/// `f(x) = (x * d * c) / (d + c * x)`.
var RUBBER_BAND_CONSTANT = 0.55;

/// The wheel delta along one axis. High-resolution trackpads report pixelDelta;
/// a classic wheel reports angleDelta. Never mix them in one event.
function axisDelta(event, axis) {
    if (!event) return 0;
    const pixel = axis === "x" ? event.pixelDelta.x : event.pixelDelta.y;
    if (pixel !== 0) return pixel;
    const angle = axis === "x" ? event.angleDelta.x : event.angleDelta.y;
    return angle * ANGLE_TO_PIXELS;
}

/// Clamp a value to a range.
function clamp(value, minimum, maximum) {
    return Math.max(minimum, Math.min(maximum, value));
}

/// Exponential momentum decay for one frame.
function decay(velocity, dt) {
    return velocity * Math.exp(-SCROLL_DECELERATION * dt);
}

/// Compress an overshoot by the UIScrollView rubber-band curve.
function rubberBand(overshoot, dimension) {
    if (overshoot <= 0 || dimension <= 0) return 0;
    return (overshoot * dimension * RUBBER_BAND_CONSTANT)
        / (dimension + RUBBER_BAND_CONSTANT * overshoot);
}

/// Map an unbounded raw position to the displayed content offset.
function displayed(position, minimum, maximum, dimension) {
    if (position < minimum) return minimum - rubberBand(minimum - position, dimension);
    if (position > maximum) return maximum + rubberBand(position - maximum, dimension);
    return position;
}

/// One frame of free momentum, integrated exactly. The naive `position +=
/// velocity * dt` over-travels because it holds the start-of-frame velocity for
/// the whole frame; the exact integral of an exponential is
/// `v * (1 - exp(-k dt)) / k`.
function advance(position, velocity, dt) {
    const factor = Math.exp(-SCROLL_DECELERATION * dt);
    return {
        position: position + velocity * (1 - factor) / SCROLL_DECELERATION,
        velocity: velocity * factor
    };
}

/// Add the edge spring when the raw position is outside the bounds. This is the
/// only spring in the model: normal scrolling is pure momentum.
function applyEdge(position, velocity, minimum, maximum, dt) {
    let next = velocity;
    if (position < minimum) {
        next += (minimum - position) * EDGE_STIFFNESS * dt;
        next -= next * EDGE_DAMPING * dt;
    } else if (position > maximum) {
        next += (maximum - position) * EDGE_STIFFNESS * dt;
        next -= next * EDGE_DAMPING * dt;
    }
    return clamp(next, -SCROLL_MAX_VELOCITY, SCROLL_MAX_VELOCITY);
}

/// How close to a bound a settled position may be before it snaps flush. The
/// edge spring can cross back inside with a few pixels left; leaving that gap
/// would show a sliver of blank content at rest.
var SNAP_DISTANCE = 4;

/// Snap a settled position to a nearby bound, otherwise clamp it.
function snapped(position, minimum, maximum) {
    const clamped = clamp(position, minimum, maximum);
    if (clamped < minimum + SNAP_DISTANCE) return minimum;
    if (clamped > maximum - SNAP_DISTANCE) return maximum;
    return clamped;
}

/// Has the raw position come back inside the bounds and stopped?
function settled(position, velocity, minimum, maximum) {
    return Math.abs(velocity) < EDGE_STOP_VELOCITY
        && position >= minimum - EDGE_STOP_DISTANCE
        && position <= maximum + EDGE_STOP_DISTANCE;
}
