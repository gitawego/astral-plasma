import QtQuick
import "../components/motion"

// ============================================================================
// Performance tab motion budget
// ============================================================================
// The tab's telemetry slide, the four usage bars and the animated device readout
// used to be `NumberAnimation`/`Behavior` tweens of 450 ms that were restarted by
// every metric sample (CPU: 400 ms). The animation was therefore *never idle*,
// and each of its frames repainted a Canvas and re-rendered the whole tab: the
// shell burned 43.8 % of the iGPU and 45 % of a CPU core for as long as the tab
// stayed open (dashboard closed: 0.3 % / 1.9 %).
//
// Decorative, metric-driven motion belongs on the shared MotionClock like every
// other decorative animation, so the tab costs at most `decorativeMaxFps` frames
// per second no matter how long it is left open.
Item {
    id: testRoot
    width: 600
    height: 400

    property string tabSource: ""
    property string tweenSource: ""
    property int clockTicks: 0
    property int tweenChanges: 0
    property real lastValue: 0

    function readLocalFile(relUrl) {
        const xhr = new XMLHttpRequest();
        const bust = (relUrl.indexOf("?") < 0 ? "?v=" : "&v=") + Date.now() + Math.random();
        xhr.open("GET", Qt.resolvedUrl(relUrl) + bust, false);
        xhr.send();
        return xhr.responseText || "";
    }

    function assert(cond, msg) {
        if (!cond) {
            console.log("FAIL: " + msg);
            console.error("FAIL: " + msg);
            Qt.exit(1);
            throw new Error(msg);
        }
        return true;
    }

    function slice(text, from, to) {
        const start = text.indexOf(from);
        if (start < 0) return "";
        const end = to ? text.indexOf(to, start) : -1;
        return end < 0 ? text.substring(start) : text.substring(start, end);
    }

    Connections {
        target: MotionClock
        function onTickChanged() { testRoot.clockTicks++; }
    }

    MotionTween {
        id: probeTween
        duration: 200
        from: 0.0
        to: 1.0
    }
    Connections {
        target: probeTween
        function onValueChanged() {
            testRoot.tweenChanges++;
            testRoot.lastValue = probeTween.value;
        }
    }

    // ---------------------------------------------------------------- phase 1 --
    // Behavioural: the tween advances only when the shared clock ticks, finishes
    // exactly on `to`, and releases the clock so an idle shell renders nothing.
    Timer {
        interval: 40
        running: true
        repeat: false
        onTriggered: {
            const budget = MotionClock.frameBudget;
            testRoot.clockTicks = 0;
            testRoot.tweenChanges = 0;
            testRoot.assert(MotionClock.consumers === 0, "an idle shell must hold no clock reference");
            testRoot.assert(probeTween.value === 0.0, "a tween rests at `from` before it starts");

            probeTween.restart();
            testRoot.assert(MotionClock.consumers === 1, "a running tween holds exactly one clock reference");

            // Sample well past the tween's duration.
            phase2.start();
        }
    }

    Timer {
        id: phase2
        interval: 420
        running: false
        repeat: false
        onTriggered: {
            const budget = MotionClock.frameBudget;
            const expectedTicks = Math.ceil((budget * 200) / 1000) + 2;
            testRoot.assert(
                testRoot.tweenChanges <= testRoot.clockTicks + 1,
                "the tween must advance on clock ticks, not on display frames (changes=" +
                    testRoot.tweenChanges + ", ticks=" + testRoot.clockTicks + ")"
            );
            testRoot.assert(
                testRoot.clockTicks <= expectedTicks,
                "a " + 200 + "ms tween must not exceed the " + budget + " fps budget (ticks=" +
                    testRoot.clockTicks + ", expected<=" + expectedTicks + ")"
            );
            testRoot.assert(
                Math.abs(testRoot.lastValue - 1.0) < 0.0001,
                "the tween must land exactly on `to`, got " + testRoot.lastValue
            );
            testRoot.assert(
                MotionClock.consumers === 0,
                "a finished tween must release the clock (consumers=" + MotionClock.consumers + ")"
            );
            // Restarting is idempotent and re-reads the endpoints.
            probeTween.from = 0.25;
            probeTween.to = 0.75;
            probeTween.restart();
            testRoot.assert(MotionClock.consumers === 1, "restart must hold a single reference");
            phase3.start();
        }
    }

    Timer {
        id: phase3
        interval: 420
        running: false
        repeat: false
        onTriggered: {
            testRoot.assert(
                Math.abs(probeTween.value - 0.75) < 0.0001,
                "a restarted tween must honour its new endpoints, got " + probeTween.value
            );
            testRoot.assert(MotionClock.consumers === 0, "the clock must be released again");
            sourceContracts();
        }
    }

    // ---------------------------------------------------------------- phase 2 --
    // Source contracts: the tab drives every metric-driven animation through the
    // shared clock and keeps its durations on design tokens.
    function sourceContracts() {
        testRoot.tabSource = readLocalFile("../dashboard/tabs/PerformanceTab.qml");
        testRoot.tweenSource = readLocalFile("../components/motion/MotionTween.qml");

        testRoot.assert(testRoot.tweenSource.length > 0, "MotionTween must exist as a reusable primitive");
        testRoot.assert(
            testRoot.tweenSource.indexOf("MotionClock.acquire") !== -1 &&
                testRoot.tweenSource.indexOf("MotionClock.release") !== -1,
            "MotionTween must hold and release the shared clock"
        );

        const src = testRoot.tabSource;
        testRoot.assert(src.length > 0, "PerformanceTab.qml must be readable");

        // The telemetry slide is a tween on the clock, not a free-running
        // NumberAnimation that each sample restarts.
        testRoot.assert(
            src.indexOf("NumberAnimation on slideProgress") < 0,
            "the telemetry slide must not own a free-running NumberAnimation"
        );
        testRoot.assert(
            src.indexOf("slideTween") !== -1 && src.indexOf("MotionTween") !== -1,
            "the telemetry slide must be driven by MotionTween"
        );
        testRoot.assert(
            src.indexOf("slideAnim") < 0,
            "the restarted slide animation must be gone, not merely renamed"
        );

        // Every usage bar animates through a tween as well. The match includes the
        // opening brace so prose about the removed pattern cannot trip it.
        const behaviors = src.split("Behavior on width {").length - 1;
        testRoot.assert(
            behaviors === 0,
            "usage bars must not animate their width with a Behavior (found " + behaviors + ")"
        );
        const tweenSites = (src.split("MotionTween {").length - 1) + (src.split("MotionValue {").length - 1);
        testRoot.assert(
            tweenSites >= 5,
            "slide, usage bars and the device readout each need their own motion primitive (found " +
                tweenSites + ")"
        );

        // Durations come from the motion tokens and stay below the 400 ms CPU
        // sample interval, so a tween always finishes before it is restarted.
        const durations = src.match(/duration:\s*Theme\.\w+/g) || [];
        testRoot.assert(
            durations.length >= 5,
            "metric-driven tweens must take their duration from Theme, found " + durations.length
        );
        testRoot.assert(
            src.indexOf("duration: 450") < 0,
            "the 450 ms duration that outlived the 400 ms sample interval must be gone"
        );
        testRoot.assert(
            /isTargetVisible/.test(src),
            "the tab must keep gating its motion on visibility"
        );

        console.log("PASS: performance tab motion budget (" + testRoot.clockTicks + " clock ticks for a 200 ms tween)");
        Qt.exit(0);
    }
}
