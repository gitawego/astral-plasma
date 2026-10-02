pragma Singleton

import QtQuick
import "../config"

// ============================================================================
// Debug facade (legacy name, leveled logger underneath)
// ============================================================================
// `Log` is where diagnostics are printed from; this facade stays for callers
// written against the old API, and for the one thing the old boolean was really
// for: freezing drawer auto-close while inspecting the shell.
//
// `active` is the *behaviour* toggle (freeze on mouse-out), not a verbosity
// switch - verbosity belongs to `logging.level` / `logging.categories`, so a
// category can be verbose without freezing the UI, and the UI can be frozen
// without drowning in per-frame lines.
Item {
    id: root

    /// Freeze drawer auto-close so the shell can be inspected while it is open.
    readonly property bool active: (typeof Config !== "undefined") ? Config.debugMode : false
    readonly property bool freezeAutoClose: active

    /// Print through the leveled logger. The category is lower-cased so it
    /// addresses the same override the modern call sites use.
    function log(category, message) {
        Log.debug(String(category).toLowerCase(), message);
    }
}
