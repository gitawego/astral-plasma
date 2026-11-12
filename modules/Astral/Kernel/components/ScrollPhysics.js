.pragma library

// ============================================================================
// Scroll physics
// ============================================================================
// One place for the numbers every scrollable surface uses. The wheel handler is
// intentionally thin: it asks this file how far a wheel event should move, how
// far that is allowed to go, and which motion token the animation takes.

/// One mouse-wheel notch is 120 angle units. Treat it as 60 px of content, so a
/// notch glides instead of jumping a whole screen line.
var ANGLE_TO_PIXELS = 0.5;

/// Shared drag/flick physics. A flick keeps gliding long enough to read as
/// motion, and the velocity ceiling is high enough for a trackpad flick without
/// letting a mouse notch throw the content across the page.
var FLICK_DECELERATION = 1500;
var MAXIMUM_FLICK_VELOCITY = 4000;

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

/// The animation token for one wheel step. Wheel scrolling is an effect, not a
/// spatial page transition, so it uses the fast effects token. Returns null when
/// the theme is not available; the caller then jumps rather than inventing a
/// duration that is not in the design system.
function motionFor(theme) {
    if (!theme || theme.animExpressiveFastEffects === undefined
            || !theme.curveExpressiveFastEffects) {
        return null;
    }
    return {
        duration: theme.animExpressiveFastEffects,
        curve: theme.curveExpressiveFastEffects
    };
}
