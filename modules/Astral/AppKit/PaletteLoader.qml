import QtQuick
import Quickshell
import Quickshell.Io

// ============================================================================
// PaletteLoader — reads the host palette into AppPalette
// ============================================================================
// A **type**, not a singleton: it is compiled only when an app (or its AppWindow)
// instantiates it, so `import Astral.AppKit 1.0` stays free of Quickshell API and the
// qml6 suites can load the module (spec C.14).
//
// `FileView.text()` + `JSON.parse`: `data()` returns an empty object for these files
// (spec C.7), so the text is the contract.
Item {
    id: root

    /// Overridable for tests; defaults to the launcher's variable, then the kernel's
    /// own location.
    property string palettePath: ""

    Component.onCompleted: {
        const explicit = root.palettePath.length > 0
            ? root.palettePath
            : Quickshell.env("ASTRAL_APPKIT_PALETTE");
        const xdg = Quickshell.env("XDG_CONFIG_HOME");
        const home = Quickshell.env("HOME");
        const base = (xdg && xdg.length > 0) ? xdg : ((home || "") + "/.config");
        const path = (explicit && explicit.length > 0)
            ? explicit
            : base + "/astral-plasma/current-palette.json";
        reader.path = path;
        apply(path);
    }

    function apply(path) {
        const text = reader.text();
        AppPalette.path = path;
        try {
            const parsed = JSON.parse(text);
            if (parsed && typeof parsed === "object" && parsed.mode !== undefined) {
                AppPalette.tokens = parsed;
                AppPalette.source = "palette";
                return;
            }
        } catch (error) {
            // Fall through to the defaults below.
        }
        AppPalette.tokens = ({});
        AppPalette.source = "defaults";
    }

    FileView {
        id: reader
        blockLoading: true
        printErrors: false
    }
}
