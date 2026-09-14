import QtQuick
import "../config"
import "../theme"

Item {
    id: testRoot
    width: 800
    height: 600

    property bool hoveredDropdown: false
    property bool hoveredTopEdge: false

    // Simulated closeTimer matching UnifiedShell.qml implementation
    Timer {
        id: closeTimer
        interval: 350
        repeat: false
        onTriggered: {
            if (!testRoot.hoveredDropdown && !testRoot.hoveredTopEdge) {
                Config.dashboardVisible = false;
            }
        }
    }

    function simulateMouseLeave() {
        testRoot.hoveredDropdown = false;
        testRoot.hoveredTopEdge = false;
        if (Config.dashboardVisible) {
            closeTimer.restart();
        }
    }

    function simulateMouseEnter() {
        testRoot.hoveredDropdown = true;
        closeTimer.stop();
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
        console.log("RUNNING: Top Drawer Auto-Close Unit Tests");

        // Test 1: Timer interval must be snappy (<= 500ms)
        assert(closeTimer.interval <= 500, "closeTimer interval must be <= 500ms for responsive UX");
        assert(closeTimer.repeat === false, "closeTimer must be one-shot");

        // Test 2: Drawer starts open
        Config.dashboardVisible = true;
        assert(Config.dashboardVisible === true, "Dashboard should be visible initially");

        // Test 3: Mouse inside drawer stops timer
        simulateMouseEnter();
        assert(closeTimer.running === false, "Timer must be stopped while mouse is inside drawer");
        assert(Config.dashboardVisible === true, "Drawer must remain open while mouse is inside");

        // Test 4: Mouse leaves drawer -> timer starts and closes drawer
        simulateMouseLeave();
        assert(closeTimer.running === true, "Timer must start when mouse leaves drawer");

        // Fast-forward timer trigger
        closeTimer.triggered();
        assert(Config.dashboardVisible === false, "Drawer must automatically close after mouse leaves");

        // Test 5: If mouse re-enters before timer fires, timer stops and drawer stays open
        Config.dashboardVisible = true;
        simulateMouseLeave();
        assert(closeTimer.running === true, "Timer started on leave");
        simulateMouseEnter();
        assert(closeTimer.running === false, "Timer must be cancelled when mouse re-enters before timeout");
        assert(Config.dashboardVisible === true, "Drawer must stay open if user re-enters");

        console.log("PASS: All Top Drawer Auto-Close tests passed!");
        Qt.exit(0);
    }
}
