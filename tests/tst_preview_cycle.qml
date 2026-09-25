import QtQuick
import "../components"

// Serial thumbnail-capture cycle contract (active-apps overview).
//
// The cycle exists so N windows are captured ONE AT A TIME through a single
// Process: the runner must never be invoked for the next item until the
// previous invocation reports completion via advance(). The item list is
// re-read at every wrap so windows opened while the overview is visible join
// the rotation without a restart.
Item {
    id: testRoot
    width: 400
    height: 300

    property var calls: []
    property int finishedCycles: 0

    PreviewCycle {
        id: cycle
        interval: 0 // synchronous pumping: deterministic assertions
        runner: key => {
            testRoot.calls.push(key);
        }
        onFinishedCycle: testRoot.finishedCycles++
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
            // Halt: falling through to the final Qt.exit(0) would overwrite
            // the exit code and turn a failing suite green.
            throw new Error(msg);
        }
    }

    function runTests() {
        console.log("RUNNING: Preview Cycle serial rotation tests");

        // 1. Idle state: nothing runs before start().
        assert(cycle.active === false, "cycle must start inactive");
        assert(cycle.calls === undefined, "cycle must not expose runner internals");

        // 2. start() pumps the first item immediately.
        cycle.items = ["a", "b", "c"];
        cycle.start();
        assert(cycle.active === true, "cycle must be active after start with items");
        assert(JSON.stringify(testRoot.calls) === JSON.stringify(["a"]),
            "start must invoke runner with the first item only, got " + JSON.stringify(testRoot.calls));

        // 3. Serial discipline: an extra advance is the ONLY progression driver.
        cycle.advance();
        assert(JSON.stringify(testRoot.calls) === JSON.stringify(["a", "b"]),
            "advance must invoke runner with the second item, got " + JSON.stringify(testRoot.calls));

        // 4. Wrap re-reads items: replace the list before the wrap advance and
        //    the rotation must continue over the NEW list.
        cycle.items = ["b", "c"];
        cycle.advance(); // runs "c" (last of the original queue)
        assert(JSON.stringify(testRoot.calls) === JSON.stringify(["a", "b", "c"]),
            "advance must reach the third item, got " + JSON.stringify(testRoot.calls));

        cycle.advance(); // wraps: queue rebuilt from updated items ["b","c"]
        assert(testRoot.finishedCycles === 1, "wrapping must emit finishedCycle once, got " + testRoot.finishedCycles);
        assert(testRoot.calls[testRoot.calls.length - 1] === "b",
            "wrap must re-read items and pump the new list's first entry, got " + JSON.stringify(testRoot.calls));

        // 5. stop() halts progression: advance() after stop must not call the runner.
        const countBefore = testRoot.calls.length;
        cycle.stop();
        assert(cycle.active === false, "cycle must deactivate on stop");
        cycle.advance();
        assert(testRoot.calls.length === countBefore, "advance after stop must not invoke the runner");

        // 6. An empty item list must never invoke the runner.
        cycle.items = [];
        cycle.start();
        assert(cycle.active === false, "cycle with no items must not go active");
        cycle.advance();
        assert(testRoot.calls.length === countBefore, "empty cycle must never invoke the runner");

        // 7. Restart after stop works with a fresh list.
        cycle.items = ["z"];
        cycle.start();
        assert(testRoot.calls[testRoot.calls.length - 1] === "z",
            "restart after stop must pump the new list, got " + JSON.stringify(testRoot.calls));

        // 8. Items emptied while ACTIVE: the wrap deactivates instead of stalling hot.
        cycle.stop();
        cycle.items = ["only"];
        cycle.start();
        cycle.items = [];
        cycle.advance(); // completes "only", wraps onto an empty list
        assert(cycle.active === false, "wrap onto an empty list must deactivate the cycle");

        // 9. First pass synchronous pumping when firstPassInterval === 0 even with large interval
        cycle.stop();
        cycle.interval = 5000;
        cycle.firstPassInterval = 0;
        cycle.items = ["init1", "init2", "init3"];
        testRoot.calls = [];
        cycle.start();
        assert(testRoot.calls.length === 1 && testRoot.calls[0] === "init1", "first item must pump immediately");
        cycle.advance();
        assert(testRoot.calls.length === 2 && testRoot.calls[1] === "init2", "second item in first pass must pump immediately without waiting for interval");
        cycle.advance();
        assert(testRoot.calls.length === 3 && testRoot.calls[2] === "init3", "third item in first pass must pump immediately");
        cycle.advance();
        assert(testRoot.finishedCycles >= 1, "must finish first pass cycle");
        assert(testRoot.calls.length === 3, "wrap into second pass with interval: 5000 must wait for timer, not pump immediately");
        cycle.stop();

        console.log("PASS: Preview Cycle serial rotation tests passed");
        Qt.exit(0);
    }
}
