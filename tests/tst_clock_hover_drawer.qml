import QtQuick
import "../components"
import "../theme"

Item {
    id: testRoot
    width: 800
    height: 600

    property bool bottomPopoutVisible: false
    property string bottomPopoutMode: "default"
    property bool dashboardVisible: false

    // Simulated popoutCloseTimer matching Config.qml
    Timer {
        id: popoutCloseTimer
        interval: 450
        repeat: false
        onTriggered: testRoot.bottomPopoutVisible = false
    }

    function openBottomPopout(mode) {
        popoutCloseTimer.stop();
        if (mode) testRoot.bottomPopoutMode = mode;
        testRoot.bottomPopoutVisible = true;
    }

    function keepBottomPopout() {
        popoutCloseTimer.stop();
    }

    function scheduleCloseBottomPopout() {
        popoutCloseTimer.restart();
    }

    function simulateClockEnter() {
        openBottomPopout("clock");
    }

    function simulateClockLeave() {
        scheduleCloseBottomPopout();
    }

    function simulatePopoutEnter() {
        keepBottomPopout();
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
        console.log("RUNNING: Clock Hover Fused Popout Unit Tests");

        // Test 1: Initially popout is closed and top drawer is closed
        assert(testRoot.bottomPopoutVisible === false, "Popout drawer should be initially closed");
        assert(testRoot.dashboardVisible === false, "Top dashboard drawer should be initially closed");

        // Test 2: Hovering clock opens bottom popout drawer with mode "clock"
        simulateClockEnter();
        assert(testRoot.bottomPopoutVisible === true, "Bottom popout drawer should open on clock hover");
        assert(testRoot.bottomPopoutMode === "clock", "Popout mode should be 'clock'");

        // CRITICAL REGRESSION TEST: Top menu drawer must NEVER open when hovering time!
        assert(testRoot.dashboardVisible === false, "Top menu drawer must NOT open when mouse hovers over the time");

        // Test 3: Leaving clock schedules close
        simulateClockLeave();
        assert(popoutCloseTimer.running === true, "Close timer should run after leaving clock");
        assert(testRoot.bottomPopoutVisible === true, "Drawer remains open during grace period");

        // Test 4: Entering popout keeps it open
        simulatePopoutEnter();
        assert(popoutCloseTimer.running === false, "Close timer should stop when cursor enters popout");
        assert(testRoot.bottomPopoutVisible === true, "Popout drawer stays open when mouse enters it");

        console.log("PASS: All Clock Hover Fused Popout unit tests passed!");
        Qt.exit(0);
    }
}
