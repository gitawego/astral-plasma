import QtQuick

// ============================================================================
// Flat Dock Modules Contract
// ============================================================================
// The system-tray capsule and the clock are small, secondary dock modules. Both
// grew an extra outline that the design language does not use:
//
//   - the tray capsule drew an INNER RIM (a rounded rectangle inset 3px inside
//     the glass), which reads as a box drawn inside the panel - the same defect
//     docs/LESSONS.md 9.1 calls out for resting containers, and
//   - the clock pill drew a 1px border on top of its translucent fill.
//
// Their glass edge already comes from the LiquidGlassCard specular hairlines, so
// these extra outlines are removed and must not come back.
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
        console.log("RUNNING: Flat Dock Modules Contract");

        const capsule = readLocalFile("../dock/components/DockScrollCapsule.qml");
        const dock = readLocalFile("../shell/UnifiedDock.qml");
        assert(capsule.length > 500 && dock.length > 1000, "sources must be readable");

        // 1. No inner rim inside the secondary capsule.
        assert(!/Inner rim/i.test(capsule),
            "the tray capsule must not draw an inner rim: the glass edge already comes "
            + "from the card's specular hairlines, and an inset outline reads as a box "
            + "drawn inside the panel");

        // 2. No border on the clock pill.
        const clock = dock.match(/id: clockPill[\s\S]{0,600}/);
        assert(clock !== null, "UnifiedDock must declare the clock pill");
        assert(!/border\.width/.test(clock[0]),
            "the clock card must not draw a border (it is a translucent pill, not a card)");
        assert(!/border\.color/.test(clock[0]),
            "the clock card must not draw a border colour");

        console.log("PASS: Flat Dock Modules Contract (no tray inner rim, no clock border)");
        Qt.exit(0);
    }
}
