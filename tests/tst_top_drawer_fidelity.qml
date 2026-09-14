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
        }
    }

    function runTests() {
        console.log("RUNNING: Top Drawer Visual Fidelity Unit Tests");

        // Test 1: MediaTab root must NOT be a Card with an outer border
        // It must be an Item or have border.width === 0 to avoid double borders
        assert(typeof mediaTab.border === "undefined" || mediaTab.border.width === 0,
               "MediaTab must NOT have an outer border (must be seamless Item or borderless)");

        // Test 2: Card component must have border.width === 0 to prevent double borders on nested cards
        assert(sampleCard.border.width === 0,
               "Card component default border.width must be 0 to prevent double borders");

        // Test 3: Card radius must follow Theme.radiusLarge
        assert(sampleCard.radius === Theme.radiusLarge,
               "Card radius must match Theme.radiusLarge");

        console.log("PASS: All Top Drawer Visual Fidelity tests passed!");
        Qt.exit(0);
    }
}
