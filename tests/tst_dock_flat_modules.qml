import QtQuick
import "../components"
import "../theme"

// ============================================================================
// Flat Dock Modules Contract
// ============================================================================
// The system-tray group and the clock are secondary dock modules. They must not
// look like another pair of cards:
//
//   - the tray capsule drew an INNER RIM (a rounded rectangle inset 3px inside
//     the glass), which reads as a box drawn inside the panel - the same defect
//     docs/LESSONS.md 9.1 calls out for resting containers, and
//   - the clock pill drew a 1px border on top of its translucent fill.
//
// Both are gone, and neither module may render a resting card background at all:
// the tray is a bare column of icons and the clock is bare text, with hover /
// active states as the only feedback.
Item {
    id: testRoot
    width: 800
    height: 600

    // A bare card: no fill, no shadow, no caustic, no specular, no rim.
    LiquidGlassCard {
        id: bareCard
        width: 100
        height: 100
        bare: true
    }

    // The same card without `bare`, as the taskbar capsule uses it.
    LiquidGlassCard {
        id: glassCard
        width: 100
        height: 100
    }

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

        // 2. No border on the clock pill, and no resting card background.
        const clock = dock.match(/id: clockPill[\s\S]{0,700}/);
        assert(clock !== null, "UnifiedDock must declare the clock pill");
        assert(!/border\.width/.test(clock[0]),
            "the clock card must not draw a border (it is a translucent pill, not a card)");
        assert(!/border\.color/.test(clock[0]),
            "the clock card must not draw a border colour");
        assert(/"transparent"/.test(clock[0]),
            "the clock must have no resting card background: only hover/active may tint it");

        // 3. The tray group is a bare capsule: icons, no card.
        const tray = dock.match(/id: trayContainer[\s\S]{0,500}/);
        assert(tray !== null, "UnifiedDock must declare the tray container");
        assert(/bare:\s*true/.test(tray[0]),
            "the tray capsule must be `bare`: the tray is a column of icons, not another card");

        // 4. A bare card really renders nothing (behavioural, not just source).
        assert(bareCard.bare === true, "LiquidGlassCard must expose `bare`");
        assert(bareCard.color.a === 0,
            "a bare card must be fully transparent, got alpha " + bareCard.color.a);
        assert(bareCard.border.width === 0, "a bare card must not draw a border");
        assert(bareCard.shadowItem.visible === false, "a bare card must not draw its shadow");
        assert(bareCard.causticItem.visible === false, "a bare card must not draw the caustic glow");
        assert(bareCard.topGlareItem.visible === false, "a bare card must not draw the specular hairline");
        assert(bareCard.bottomRimItem.visible === false, "a bare card must not draw the bottom rim");

        // The glass card keeps its material: `bare` must not leak into other users.
        assert(glassCard.color.a > 0, "a normal card keeps its translucent fill");
        assert(glassCard.topGlareItem.visible === true, "a normal card keeps its specular hairline");

        console.log("PASS: Flat Dock Modules Contract (no tray inner rim, no clock border, "
            + "tray and clock render no resting card, glass card unaffected)");
        Qt.exit(0);
    }
}
