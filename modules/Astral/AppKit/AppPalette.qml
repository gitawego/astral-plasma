pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// ============================================================================
// AppPalette — the theme the host lends to an app
// ============================================================================
// A hosted app runs in its own sandbox: it cannot import `Astral.Kernel` and it
// cannot read the user's settings. What it *can* read is the palette file the
// kernel already exports for terminals, Omarchy, and AI agents
// (`ThemeExportService` -> `current-palette.json`). That file is the contract:
// wallpaper-derived colours, the archetype's radii, and the typeface.
//
// When the file is absent (first run, an unsandboxed dev loop, a machine with no
// wallpaper palette yet) the Material 3 defaults below are used, and `source`
// says which happened — an app that needs to explain a plain-looking window can
// read it instead of guessing.
QtObject {
    id: root

    /// Env override first (the sandbox binds the file and names it), then the
    /// kernel's own location.
    readonly property string path: {
        const explicit = Quickshell.env("ASTRAL_APPKIT_PALETTE");
        if (explicit && explicit.length > 0) {
            return explicit;
        }
        const xdg = Quickshell.env("XDG_CONFIG_HOME");
        const home = Quickshell.env("HOME");
        const base = (xdg && xdg.length > 0) ? xdg : ((home || "") + "/.config");
        return base + "/astral-plasma/current-palette.json";
    }

    /// The file's text, read synchronously once. `FileView.data()` returned an
    /// empty object for this file, so parsing is done here with `JSON.parse`:
    /// one less documented-but-unproven path.
    readonly property string contents: reader.text()

    readonly property var tokens: {
        try {
            const parsed = JSON.parse(root.contents);
            return (parsed && typeof parsed === "object") ? parsed : ({});
        } catch (error) {
            return ({});
        }
    }

    /// "palette" when the host's file was read, "defaults" when it was not.
    readonly property string source: root.tokens.mode !== undefined ? "palette" : "defaults"

    function color(key, fallback) {
        const value = root.tokens[key];
        if (typeof value === "string" && value.length > 0) {
            return value;
        }
        return fallback;
    }

    function number(key, fallback) {
        const value = root.tokens[key];
        return (typeof value === "number" && isFinite(value)) ? value : fallback;
    }

    // `QtObject` has no default property, so the reader is a named child.
    readonly property FileView reader: FileView {
        path: root.path
        blockLoading: true
        printErrors: false
    }
}
