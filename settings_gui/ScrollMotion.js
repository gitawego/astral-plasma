.pragma library

// ============================================================================
// Scroll motion
// ============================================================================
// A programmatic scroll (clicking a zone pill in a settings page's rail) is a
// *spatial* transition, so it uses the shell's expressive spatial token - never a
// linear ease and never a hardcoded duration (DESIGN.md).
//
// One adjustment, and only one: those spatial curves carry a spring overshoot
// (21-67% of the control points), which is designed for micro-jumps. Applied to a
// 2000px jump the spring would fling the view ~400px past the section it was
// asked to show. The overshoot is therefore damped by distance: near jumps keep
// the expressive spring, long jumps settle smoothly into the anchor. Same curve
// family, same duration ladder, no invented easing.
//
// `motionFor` is the whole motion in one call, and it returns nothing when the
// tokens are not there to read (the offscreen harness has no Quickshell, so no
// Theme) - a scroll then jumps rather than borrowing a duration this file made
// up. Pure: asserted by `tests/tst_settings_sticky_header.qml`; the tween itself
// by `tests/tst_settings_hub_rail.qml`.

/// Where damping is complete: at or beyond this distance the curve has no
/// overshoot left (a section jump across a long settings page).
var FULL_DAMP_DISTANCE = 1200;

/// At or beyond this distance the jump is long enough to take the default
/// spatial step instead of the snappy one.
var SHORT_JUMP_DISTANCE = 600;

/// Blend a spatial curve's *overshoot* away as the distance grows.
///
/// The array is `[x1, y1, x2, y2, x3, y3]`. The x controls carry the rhythm and
/// stay exactly as the token defines them; only the y controls - which is where
/// the spring lives - move toward the settled token's values. At `t = 0` the
/// spatial spring is untouched, at `t = 1` the spring is gone, which is what a
/// long jump needs: it should arrive at the section, not fly past it.
function dampedCurve(spatialCurve, settledCurve, distance) {
    if (!spatialCurve || spatialCurve.length < 6) return spatialCurve;
    if (!settledCurve || settledCurve.length !== spatialCurve.length) return spatialCurve;
    var t = Math.min(1, Math.abs(distance) / FULL_DAMP_DISTANCE);
    var out = [];
    for (var i = 0; i < spatialCurve.length; ++i) {
        var isOvershootControl = (i % 2) === 1;
        out.push(isOvershootControl
            ? spatialCurve[i] + (settledCurve[i] - spatialCurve[i]) * t
            : spatialCurve[i]);
    }
    return out;
}

/// The complete motion for a scroll of `distance`: the duration and the curve,
/// picked from the shell's token ladder (`theme` is the Theme singleton, the
/// single source of truth for both).
///
/// Returns `null` when there are no tokens to honour - the offscreen harness has
/// no Quickshell, so no Theme singleton. Nothing is invented in that case: a
/// scroll with no motion tokens is a jump, which is exactly what the caller does.
/// A second, hardcoded duration here would be a second source of truth for the
/// design's motion.
function motionFor(theme, distance) {
    if (!theme || theme.animExpressiveFastSpatial === undefined
            || theme.animExpressiveDefaultSpatial === undefined) {
        return null;
    }
    var fast = Math.abs(distance) < SHORT_JUMP_DISTANCE;
    var spatial = fast ? theme.curveExpressiveFastSpatial : theme.curveExpressiveDefaultSpatial;
    var settled = theme.curveExpressiveDefaultEffects;
    if (!spatial || spatial.length < 6) return null;
    return {
        duration: fast ? theme.animExpressiveFastSpatial : theme.animExpressiveDefaultSpatial,
        curve: dampedCurve(spatial, settled, distance)
    };
}
