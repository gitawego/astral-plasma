pragma Singleton

import QtQuick

// ============================================================================
// AppPalette — the theme the host lends to an app
// ============================================================================
// Pure data on purpose: **no IO and no Quickshell import**. Importing a QML module
// compiles its singleton entries eagerly (spec C.6), so a singleton that read a file
// would make `import Astral.AppKit 1.0` fail anywhere without Quickshell's plugin -
// including every qml6 suite (spec C.14).
//
// The read lives in `PaletteLoader.qml`, a type that is compiled only when an app
// instantiates it (AppWindow does, once). Until then these values are the Material
// defaults below, which is what a layout test expects and what a first run looks like.
//
// When the file is absent (first run, an unsandboxed dev loop, no wallpaper palette
// yet) `source` says "defaults" — an app that needs to explain a plain-looking window
// can read it instead of guessing.
QtObject {
    /// Palette file the loader reads; set by `PaletteLoader`.
    property string path: ""

    /// The host's palette, as published by `ThemeExportService`.
    property var tokens: ({})

    /// "palette" when the host's file was read, "defaults" when it was not.
    property string source: "defaults"

    function color(key, fallback) {
        const value = tokens[key];
        if (typeof value === "string" && value.length > 0) {
            return value;
        }
        return fallback;
    }

    function number(key, fallback) {
        const value = tokens[key];
        return (typeof value === "number" && isFinite(value)) ? value : fallback;
    }
}
