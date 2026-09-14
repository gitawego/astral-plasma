import QtQuick
import "../config"
import "../theme"

Item {
    id: testRoot
    width: 800
    height: 600

    property bool hoveredDropdown: false
    property bool hoveredTopEdge: false
    property bool hoveredClock: false

    // Simulated closeTimer matching UnifiedShell.qml implementation
    Timer {
        id: closeTimer
        interval: 350
        repeat: false
        onTriggered: {
            if (!testRoot.hoveredDropdown && !testRoot.hoveredTopEdge && !testRoot.hoveredClock) {
                Config.dashboardVisible = false;
            }
        }
    }

    function simulateClockEnter() {
        testRoot.hoveredClock = true;
        closeTimer.stop();
        Config.activeDashboardTab = "dashboard";
        Config.dashboardVisible = true;
    }

    function simulateClockLeave() {
        testRoot.hoveredClock = false;
        if (Config.dashboardVisible && !testRoot.hoveredDropdown && !testRoot.hoveredTopEdge) {
            closeTimer.restart();
        }
    }

    function simulateDropdownEnter() {
        testRoot.hoveredDropdown = true;
        closeTimer.stop();
    }

    function simulateDropdownLeave() {
        testRoot.hoveredDropdown = false;
        if (Config.dashboardVisible && !testRoot.hoveredTopEdge && !testRoot.hoveredClock) {
            closeTimer.restart();
        }
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
        console.log("RUNNING: Clock Hover Drawer Unit Tests");

        // Test 1: Initially drawer is closed
        Config.dashboardVisible = false;
        assert(Config.dashboardVisible === false, "Dashboard should be initially closed");

        // Test 2: Hovering clock opens drawer with "dashboard" tab
        simulateClockEnter();
        assert(Config.dashboardVisible === true, "Dashboard should open when clock is hovered");
        assert(Config.activeDashboardTab === "dashboard", "Active tab should be 'dashboard' when clock is hovered");
        assert(closeTimer.running === false, "closeTimer should be stopped while clock is hovered");

        // Test 3: Moving mouse from clock towards drawer starts grace timer
        simulateClockLeave();
        assert(closeTimer.running === true, "closeTimer should run grace period when mouse leaves clock");
        assert(Config.dashboardVisible === true, "Drawer remains open during grace period");

        // Test 4: Entering dropdown cancels grace timer
        simulateDropdownEnter();
        assert(closeTimer.running === false, "closeTimer should stop once mouse enters dropdown");
        assert(Config.dashboardVisible === true, "Drawer remains open while inside dropdown");

        // Test 5: Leaving dropdown restarts grace timer
        simulateDropdownLeave();
        assert(closeTimer.running === true, "closeTimer should run when mouse leaves dropdown");

        console.log("PASS: All Clock Hover Drawer unit tests passed!");
        Qt.exit(0);
    }
}
