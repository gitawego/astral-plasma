.pragma library

// ============================================================================
// State colour vocabulary
// ============================================================================
// One place decides what a *state* means in this shell, so every control that
// reports one (quota runways, setup rows, provider cards, status dots) agrees -
// and so a page can reuse them without re-deriving "amber means attention".
//
// The vocabulary is severity, not domain: a quota window, a sign-in, an engine
// version and a microphone report all say ok / attention / critical / busy /
// idle / unknown, and `roleFor` maps that to the shell's own colour roles.
//
// Two deliberate rules:
//
//   * `idle` is not a warning. "Nothing is running" and "you are out of quota"
//     are normal conditions, so they stay muted; red is spent on things that are
//     actually wrong.
//   * a missing palette resolves to a real fallback, not to white/undefined, so a
//     component rendered outside the shell (offscreen tests, previews, docs)
//     still looks deliberate.
//
// Pure: asserted by `tests/tst_ai_page_controls.qml`.

/// Every state a control may report.
var STATES = ["ok", "attention", "critical", "busy", "idle", "unknown"];

/// Colour role of a state, in the `Colors` singleton's vocabulary.
var ROLES = {
    "ok": "success",
    "attention": "warning",
    "critical": "error",
    "busy": "primary",
    "idle": "m3onSurfaceVariant",
    "unknown": "m3onSurfaceVariant"
};

/// Fallbacks, used when the palette has no value (bare harness, preview render).
var FALLBACKS = {
    "success": "#6FD08C",
    "warning": "#F59E0B",
    "error": "#E05353",
    "primary": "#9BCBFB",
    "m3onSurfaceVariant": "#A9A6AE"
};

/// Canonical state name; anything unknown is `unknown`.
function normalize(state) {
    return STATES.indexOf(state) >= 0 ? state : "unknown";
}

/// The `Colors` property name for a state.
function roleFor(state) {
    return ROLES[normalize(state)];
}

/// The colour for a state, given a palette (normally the `Colors` singleton).
///
/// `palette` may be undefined or partially resolved: a missing role falls back to
/// the table above instead of rendering as white.
function colorFor(state, palette) {
    var role = roleFor(state);
    var value = palette ? palette[role] : undefined;
    if (value !== undefined && value !== null && String(value) !== "") {
        return value;
    }
    return FALLBACKS[role];
}

/// Is this state something the user has to act on?
///
/// Used to decide which setup rows announce themselves (and to keep "idle" - a
/// finished download queue, an exhausted quota - from opening a group).
function isActionable(state) {
    var normalized = normalize(state);
    return normalized === "attention" || normalized === "critical";
}
