.pragma library

// Which bottom-dock drawers exist, and which were retired.
//
// The dock popout host (`FusedBottomPopout`) renders one section per mode, and
// `Config` sizes the sliding wrapper from the active section's height. A mode
// with no section is not "an empty drawer" - it is a glass card that slides out
// with nothing in it. Volume and display brightness moved to the right-edge
// rail (`RightEdgeControl`), so those two modes are retired: asking for one must
// be a no-op, whether the request comes from a stale IPC script or a leftover
// shortcut.
//
// Kept as a pure module so the rule is unit-testable without instantiating the
// Quickshell `Config` singleton.

/// Retired drawer modes, in the order they were removed.
var RETIRED = ["audio", "brightness"];

/// True when `mode` names a drawer that no longer has a section.
function isRetired(mode) {
    if (!mode) return false;
    return RETIRED.indexOf(String(mode).trim().toLowerCase()) !== -1;
}

/// The mode a drawer request should actually use: the requested one when it is
/// live, otherwise the mode that is already showing (so a stray retired request
/// cannot hijack an open drawer), otherwise `fallback`.
function resolveOpenMode(requested, current, fallback) {
    const mode = requested ? String(requested).trim().toLowerCase() : "";
    if (mode === "") return fallback;
    if (isRetired(mode)) return current ? current : fallback;
    return requested;
}
