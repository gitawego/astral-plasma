import QtQuick
import "../components"
import "../theme"
import "../config"
import "../dashboard/tabs"

Item {
    id: testRoot
    width: 1000
    height: 800

    // Instantiate MediaTab
    MediaTab {
        id: mediaTab
        visible: false
    }

    // Instantiate Card
    Card {
        id: sampleCard
        visible: false
    }

    // A card nested inside another panel must be able to drop its perimeter ring
    Card {
        id: nestedCard
        visible: false
        showBorder: false
    }

    Timer {
        interval: 50
        running: true
        repeat: false
        onTriggered: runTests()
    }

    function assert(cond, msg) {
        if (!cond) {
            console.error("FAIL: " + msg);
            Qt.exit(1);
            // Qt.exit only schedules the exit: a suite that keeps running would
            // print its PASS line and override the code (docs/LESSONS.md 37).
            throw new Error(msg);
        }
    }

    function runTests() {
        console.log("RUNNING: Top Drawer Visual Fidelity Unit Tests");

        // Test 1: MediaTab root must NOT be a Card with an outer border
        // It must be an Item or have border.width === 0 to avoid double borders
        assert(typeof mediaTab.border === "undefined" || mediaTab.border.width === 0,
               "MediaTab must NOT have an outer border (must be seamless Item or borderless)");

        // Test 2: Card's edge policy (docs/LESSONS.md 9.1 "Clean Glass Materials").
        // A resting card shows one hairline perimeter ring; a card nested in another
        // panel drops the ring instead of drawing a second edge over the host's glass.
        assert(sampleCard.showBorder === true, "Card shows its perimeter ring by default");
        assert(sampleCard.border.width === 1, "Card's default ring is one hairline");
        assert(nestedCard.border.width === 0,
               "showBorder: false drops the ring, so nested cards cannot double an edge");
        assert(sampleCard.selected === false, "Card is not selected by default");
        sampleCard.selected = true;
        assert(sampleCard.border.width === 1.5, "a selected card takes the emphasis ring");
        sampleCard.selected = false;

        // Test 3: Card radius must follow Theme.radiusLarge
        // The radius is inherited from LiquidGlassCard, whose token is the card
        // radius (not the generic large one).
        const expectedRadius = (typeof Theme !== "undefined" && Theme.radiusGlassCard !== undefined)
            ? Theme.radiusGlassCard : 16;
        assert(sampleCard.radius === expectedRadius, "Card radius must follow Theme.radiusGlassCard");

        console.log("PASS: All Top Drawer Visual Fidelity tests passed!");
        Qt.exit(0);
    }
}
