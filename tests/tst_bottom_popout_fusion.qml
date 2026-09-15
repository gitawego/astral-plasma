import QtQuick
import "../components"
import "../theme"

Item {
    id: testRoot
    width: 1920
    height: 1080

    readonly property real borderT: 14
    readonly property real dockW: 70
    readonly property real filletR: 24

    property string mode: "power"
    property real popoutTargetY: 0
    property real popoutHeight: 200

    readonly property bool isPopoutFusedBottom: {
        if (mode === "power" || mode === "battery" || mode === "default") {
            return true;
        }
        let targetCenter = popoutTargetY;
        if (targetCenter <= 0) return true;
        return (targetCenter >= testRoot.height - testRoot.borderT - 180) || ((targetCenter + popoutHeight / 2) >= (testRoot.height - testRoot.borderT - 2));
    }

    readonly property real idealPopoutY: {
        if (isPopoutFusedBottom) {
            return testRoot.height - testRoot.borderT - popoutHeight;
        }
        let targetCenter = popoutTargetY;
        const desiredY = targetCenter - popoutHeight / 2;
        const minY = testRoot.borderT;
        const maxY = testRoot.height - testRoot.borderT - popoutHeight;
        return Math.max(minY, Math.min(maxY, desiredY));
    }

    // Dynamic in-flight fusion simulation properties matching UnifiedShell.qml
    property bool popoutVisible: true
    property real currentPopoutY: 0
    property real currentOffsetProgress: 1.0
    readonly property real popoutDistToBottom: Math.max(0, (testRoot.height - testRoot.borderT) - (currentPopoutY + popoutHeight))
    readonly property bool isPopoutAtBottom: isPopoutFusedBottom && popoutVisible && ((currentOffsetProgress <= 0.01) || (popoutDistToBottom <= 3.0))

    property bool isFusedToBottom: isPopoutAtBottom

    onIsPopoutAtBottomChanged: {
        if (isPopoutAtBottom) {
            isFusedToBottom = true;
        } else if (!isPopoutFusedBottom || !popoutVisible) {
            isFusedToBottom = false;
        }
    }

    onModeChanged: {
        if (!isPopoutFusedBottom) {
            isFusedToBottom = false;
        }
    }

    onPopoutVisibleChanged: {
        if (!popoutVisible) {
            isFusedToBottom = false;
        }
    }

    readonly property real fusedProgress: isFusedToBottom ? 1.0 : 0.0

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
        console.log("RUNNING: Bottom Popout Fusion Unit Tests");

        // Test 1: Power menu (last item in sidebar, near bottom) must be fused to bottom border
        mode = "power";
        popoutTargetY = testRoot.height - testRoot.borderT - 20;
        assert(isPopoutFusedBottom === true, "Power mode near bottom must be fused to bottom border");
        assert(idealPopoutY === testRoot.height - testRoot.borderT - popoutHeight,
            "Bottom of fused popout must exactly touch bottom border: " + idealPopoutY + " vs " + (testRoot.height - testRoot.borderT - popoutHeight));
        assert(idealPopoutY + popoutHeight === testRoot.height - testRoot.borderT,
            "Zero gap between drawer and bottom border");

        // Test 2: Battery / Profile drawer (2nd to last item, height 102px) must fuse to bottom border
        mode = "default";
        popoutHeight = 102;
        popoutTargetY = testRoot.height - testRoot.borderT - 60;
        assert(isPopoutFusedBottom === true, "Battery near bottom must be fused to bottom border");
        assert(idealPopoutY === testRoot.height - testRoot.borderT - 102,
            "Battery drawer top must be at maxY");
        assert(idealPopoutY + popoutHeight === testRoot.height - testRoot.borderT,
            "Zero gap between battery drawer and bottom border");

        // Test 3: Floating popout (e.g. Clock or mid-dock item at y=500) must NOT be fused to bottom
        mode = "clock";
        popoutHeight = 200;
        popoutTargetY = 500;
        assert(isPopoutFusedBottom === false, "Item in middle of dock must NOT be fused to bottom");
        assert(idealPopoutY === 500 - popoutHeight / 2, "Floating popout centered around target icon");
        assert(idealPopoutY + popoutHeight < testRoot.height - testRoot.borderT, "Floating drawer has space above bottom border");

        // Test 4: REGRESSION CHECK - In-flight drawer moving from floating icon (Wi-Fi) to bottom icon (Power)
        // Must NOT change shape to bottom-fused until it physically arrives at the bottom border!
        mode = "network";
        popoutTargetY = 500;
        currentPopoutY = 400;
        currentOffsetProgress = 1.0;
        popoutVisible = true;
        assert(fusedProgress === 0.0, "Wi-Fi popout in mid-dock must have fusedProgress === 0.0");

        // User hovers bottom icon (Power)
        mode = "power";
        popoutTargetY = testRoot.height - testRoot.borderT - 20;
        assert(isPopoutFusedBottom === true, "Target mode is fused");
        // Still at y=400 (just started moving)
        assert(popoutDistToBottom > 3.0, "Drawer is still in flight (dist: " + popoutDistToBottom + ")");
        assert(fusedProgress === 0.0, "REGRESSION: Drawer shape MUST NOT change to fused before arriving at bottom");

        // Midway down (y=600)
        currentPopoutY = 600;
        assert(fusedProgress === 0.0, "Midway down, fusedProgress must remain 0.0");

        // Near bottom (y=800)
        currentPopoutY = 800;
        assert(fusedProgress === 0.0, "At y=800 (still 66px away), fusedProgress must remain 0.0");

        // Arrival at bottom (y = 866)
        currentPopoutY = testRoot.height - testRoot.borderT - popoutHeight; // 866
        assert(popoutDistToBottom <= 3.0, "Drawer has arrived at bottom (dist: " + popoutDistToBottom + ")");
        assert(fusedProgress === 1.0, "Drawer must fuse into bottom border upon arrival");

        // Test 5: Overshoot & rebound stability (spring easing)
        currentPopoutY = 868; // 2px overshoot down
        assert(fusedProgress === 1.0, "Drawer stays fused during downward overshoot");
        currentPopoutY = 864; // 2px upward rebound
        assert(fusedProgress === 1.0, "Drawer stays fused during spring rebound");

        // Test 6: Undocking - Moving from bottom icon (Power) up to floating icon (Wi-Fi)
        mode = "network";
        popoutTargetY = 500;
        assert(isPopoutFusedBottom === false, "Wi-Fi is not a fused icon");
        assert(fusedProgress === 0.0, "Drawer must undock immediately (fusedProgress === 0.0) when moving to floating icon");

        // Test 7: Direct open from closed state at Power icon
        currentOffsetProgress = 0.0;
        popoutVisible = false;
        assert(fusedProgress === 0.0, "Closed drawer fusedProgress === 0.0");
        mode = "power";
        popoutVisible = true;
        assert(isPopoutFusedBottom === true, "Power mode is fused");
        assert(fusedProgress === 1.0, "Opening directly at bottom icon must have fusedProgress === 1.0 from start");

        console.log("PASS: Bottom Popout Fusion Unit Tests (including in-flight non-regression)");
        Qt.exit(0);
    }
}
