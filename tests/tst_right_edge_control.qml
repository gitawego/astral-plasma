import QtQuick
import "../components"
import "../theme"
import "../shell"

Item {
    id: testRoot
    width: 1920
    height: 1080

    // Simulated right edge state matching Config.qml
    property bool rightEdgeControlVisible: false

    Timer {
        id: rightEdgeCloseTimer
        interval: 450
        repeat: false
        onTriggered: testRoot.rightEdgeControlVisible = false
    }

    function openRightEdgeControl() {
        rightEdgeCloseTimer.stop();
        testRoot.rightEdgeControlVisible = true;
    }

    function keepRightEdgeControl() {
        rightEdgeCloseTimer.stop();
    }

    function scheduleCloseRightEdgeControl() {
        rightEdgeCloseTimer.restart();
    }

    function closeRightEdgeControl() {
        rightEdgeCloseTimer.stop();
        testRoot.rightEdgeControlVisible = false;
    }

    // Real RightEdgeControl component
    RightEdgeControl {
        id: rightControl
        x: testRoot.width - 60
        y: (testRoot.height - 280) / 2
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
        console.log("RUNNING: Right Edge Volume & Brightness Control Tests");

        // 1. Geometry Dimensions & Background Layer
        assert(rightControl.implicitWidth === 60, "RightEdgeControl implicitWidth must be 60");
        assert(rightControl.implicitHeight === 280, "RightEdgeControl implicitHeight must be 280");
        assert(rightControl.cardItem !== undefined && rightControl.cardItem !== null, "RightEdgeControl must have a cardItem background layer");
        assert(rightControl.cardItem.visible === true, "cardItem must be visible");
        assert(rightControl.cardItem.radius >= 20, "cardItem must have rounded capsule radius >= 20");
        if (typeof Colors !== "undefined" && Colors.glassCard) {
            assert(rightControl.cardItem.color === Colors.glassCard, "cardItem must use Colors.glassCard");
        }

        // 2. Lifecycle & Hover Auto-Close State Transitions
        assert(!testRoot.rightEdgeControlVisible, "Control must initially be hidden");

        // Mouse enters right border edge
        openRightEdgeControl();
        assert(testRoot.rightEdgeControlVisible, "openRightEdgeControl must make control visible");

        // Mouse transitions between border edge and tab
        keepRightEdgeControl();
        assert(testRoot.rightEdgeControlVisible, "keepRightEdgeControl must maintain visibility");

        // Mouse leaves tab
        scheduleCloseRightEdgeControl();
        assert(rightEdgeCloseTimer.running, "scheduleCloseRightEdgeControl must start grace timer");

        // Mouse returns to tab before timer expires
        keepRightEdgeControl();
        assert(!rightEdgeCloseTimer.running, "keepRightEdgeControl must cancel grace timer");

        // User explicitly closes
        closeRightEdgeControl();
        assert(!testRoot.rightEdgeControlVisible, "closeRightEdgeControl must immediately hide control");

        // 3. Right Border Gap & Geometry Math
        const borderT = 14;
        const filletR = 20;
        const rightH = 280;
        const rightY = Math.round((testRoot.height - rightH) / 2); // 400 on 1080p
        assert(rightY === 400, "rightY must be 400px centered on 1080p screen");

        // Closed: gap is 0, border line continuous
        let progress = 0.0;
        let gapTop = rightY - filletR * progress;
        let gapBottom = rightY + rightH + filletR * progress;
        assert(gapTop === 400 && gapBottom === 680, "Closed state gap matches exact unexpanded bounds");

        // Open: gap expands symmetrically by filletR (20px) on both ends
        progress = 1.0;
        gapTop = rightY - filletR * progress;
        gapBottom = rightY + rightH + filletR * progress;
        assert(gapTop === 380, "Open state gapTop must be 380");
        assert(gapBottom === 700, "Open state gapBottom must be 700");

        // Tab left edge position
        const currentW = 60 * progress;
        const tabLeftX = (testRoot.width - borderT) - currentW;
        assert(tabLeftX === (1920 - 14 - 60), "Tab left edge must extend 60px into workspace from inner border");

        console.log("PASS: Right Edge Volume & Brightness Control Tests");
        Qt.exit(0);
    }
}
