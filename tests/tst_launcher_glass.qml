import QtQuick

// ============================================================================
// Launcher Glass Contract
// ============================================================================
// The command launcher is a Liquid Glass modal: a `GlassSurface` sheet over a
// dimmed desktop, with frosted pills inside it.
//
// The search field broke that contract. It is focused the moment the launcher
// opens, and `GlassPill.active` swaps the fill for `Colors.glassPillActive` - a
// 65%-alpha primary-container tint. A focused search box was therefore painted
// in a flat, saturated colour instead of frosted glass, which is exactly what
// LESSONS 9.1 ("Clean Glass Materials") forbids: focus must REFINE the container
// (a specular hairline ring), never replace the material.
Item {
    id: testRoot
    width: 800
    height: 600

    function readLocalFile(relUrl) {
        const xhr = new XMLHttpRequest();
        const bust = (relUrl.indexOf("?") < 0 ? "?v=" : "&v=") + Date.now() + Math.random();
        xhr.open("GET", Qt.resolvedUrl(relUrl) + bust, false);
        xhr.send();
        return xhr.responseText || "";
    }

    function assert(condition, message) {
        if (!condition) {
            console.log("FAIL: " + message);
            console.error("FAIL: " + message);
            Qt.exit(1);
            throw new Error(message);
        }
    }

    Timer {
        interval: 50
        running: true
        repeat: false
        onTriggered: runTests()
    }

    function runTests() {
        console.log("RUNNING: Launcher Glass Contract");

        const launcher = readLocalFile("../shell/CommandLauncher.qml");
        assert(launcher.length > 1000, "CommandLauncher.qml must be readable");

        // The modal itself must stay glass.
        assert(/GlassSurface\s*\{/.test(launcher),
            "the launcher sheet must be a GlassSurface (translucent glass), not an opaque panel");
        assert(/glassColor:\s*Colors\.glassModalSurface/.test(launcher),
            "the launcher sheet must use the modal glass token");

        // The search field: frosted when focused, focus expressed by the ring.
        const search = launcher.match(/id: searchBar[\s\S]{0,900}/);
        assert(search !== null, "CommandLauncher must declare the search bar");
        assert(!/active:\s*searchInput\.activeFocus/.test(search[0]),
            "the search field must not take the `active` fill on focus: `glassPillActive` is a "
            + "saturated 65%-alpha tint, and the field is focused as soon as the launcher opens, "
            + "so the box is permanently painted flat instead of frosted");
        assert(/baseColor:\s*Colors\.glassPill/.test(search[0]),
            "the search field must keep the frosted `glassPill` fill");
        assert(/borderColor:[^\n]*glassBorderSpecular/.test(search[0]),
            "focus must be expressed by the specular hairline ring");
        assert(/borderWidth:[^\n]*activeFocus/.test(search[0]),
            "the focus ring may thicken slightly, which is the allowed refinement");

        console.log("PASS: Launcher Glass Contract (glass sheet, frosted search field, "
            + "focus expressed by the ring)");
        Qt.exit(0);
    }
}
