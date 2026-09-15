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
        popoutTargetY = 500;
        assert(isPopoutFusedBottom === false, "Item in middle of dock must NOT be fused to bottom");
        assert(idealPopoutY === 500 - popoutHeight / 2, "Floating popout centered around target icon");
        assert(idealPopoutY + popoutHeight < testRoot.height - testRoot.borderT, "Floating drawer has space above bottom border");

        console.log("PASS: Bottom Popout Fusion Unit Tests");
        Qt.exit(0);
    }
}
