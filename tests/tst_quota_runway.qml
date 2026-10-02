import QtQuick
import "../components"

// ============================================================================
// Quota runway
// ============================================================================
// The AI page's signature element: a rate-limit window as a budget *with a
// deadline* on one axis. These assertions are the mapping rules, because the
// element is only honest if the marker means what it claims:
//
//   * the fill is the remaining allowance;
//   * the tick is the window's roll-over, placed by the window kind the daemon
//     labels ("5h" / "weekly" / "monthly") - a label we cannot size gets no tick,
//     rather than a guessed one;
//   * running out is normal (dimmed empty track), and unknown data is not 0%.
Item {
    id: testRoot
    width: 800
    height: 600

    readonly property real nowMs: 1790956800000 // 2026-10-02T16:00:00Z, fixed for the test

    // A healthy window with plenty left and a reset inside the window.
    QuotaRunway {
        id: healthy
        width: 400
        remainingPercent: 82
        windowLabel: "5h"
        resetAt: "2026-10-02T18:40:00Z"  // 2h40m left of a 5h window -> 140m elapsed
        title: "5-Hour Rolling Limit"
        warningThreshold: 80
        criticalThreshold: 95
        now: testRoot.nowMs
    }

    // Out of quota: normal, not an error.
    QuotaRunway {
        id: empty
        width: 400
        remainingPercent: 0
        windowLabel: "5h"
        resetAt: "2026-10-02T18:00:00Z"
        now: testRoot.nowMs
    }

    // Data we cannot date: no marker, no invented percentage.
    QuotaRunway {
        id: dateless
        width: 400
        remainingPercent: 55
        windowLabel: "5h"
        resetAt: ""
        now: testRoot.nowMs
    }

    // The window is rolling over right now.
    QuotaRunway {
        id: rolling
        width: 400
        remainingPercent: 30
        windowLabel: "5h"
        resetAt: "2026-10-02T16:00:00Z"
        now: testRoot.nowMs
    }

    QuotaRunway {
        id: unknown
        width: 400
        remainingPercent: -1
        windowLabel: "5h"
        now: testRoot.nowMs
    }

    QuotaRunway {
        id: drifting
        width: 400
        remainingPercent: 40
        windowLabel: "5h"
        // A reset two days out cannot belong to a five-hour window.
        resetAt: "2026-10-04T16:00:00Z"
        now: testRoot.nowMs
    }

    function assert(condition, message) {
        if (!condition) {
            console.error("FAIL: " + message);
            Qt.exit(1);
            throw new Error(message);
        }
    }

    Timer {
        interval: 50
        running: true
        repeat: false
        onTriggered: runTests()
    }

    function runTests() {
        console.log("RUNNING: Quota Runway");

        // ------------------------------------------------------------------
        // Window kinds are the only window lengths we trust
        // ------------------------------------------------------------------
        assert(healthy.windowMinutesFor("5h") === 300, "the 5-hour window is 300 minutes");
        assert(healthy.windowMinutesFor("weekly") === 10080, "a week is 10080 minutes");
        assert(healthy.windowMinutesFor("monthly") === 43200, "a month is 43200 minutes");
        assert(healthy.windowMinutesFor("fortnightly") === 0,
            "an unknown label has no length, so it gets no marker");

        // ------------------------------------------------------------------
        // State comes from the user's own thresholds
        // ------------------------------------------------------------------
        assert(healthy.state === "ok", "82% left is healthy, got " + healthy.state);
        assert(healthy.stateFor(100 - 80, 80, 95) === "watch",
            "hitting the amber threshold turns it amber");
        assert(healthy.stateFor(100 - 95, 80, 95) === "critical",
            "hitting the rose threshold turns it rose");
        assert(empty.state === "exhausted", "0% left is exhausted, not an error");
        assert(unknown.state === "unknown", "a missing report is not 0% left");
        assert(empty.fillFraction === 0, "an exhausted window has no fill");
        assert(healthy.fillFraction > 0.81 && healthy.fillFraction < 0.83,
            "the fill is the remaining allowance, got " + healthy.fillFraction);
        assert(unknown.valueText === "—", "an unknown allowance reads as a dash, got " + unknown.valueText);

        // ------------------------------------------------------------------
        // The tick is the roll-over, placed on the window
        // ------------------------------------------------------------------
        assert(healthy.markerFraction > 0.46 && healthy.markerFraction < 0.47,
            "140 of 300 minutes elapsed sits just under the middle, got " + healthy.markerFraction);
        assert(dateless.markerFraction === 0, "no reset time, no tick");
        assert(drifting.markerFraction === 0,
            "a reset outside its own window is drift, not a tick at the far edge");
        assert(rolling.markerFraction === 1, "a window rolling over now sits at the end of the track");

        // ------------------------------------------------------------------
        // Reset text in the interface's voice
        // ------------------------------------------------------------------
        assert(healthy.resetText === "resets in 2h 40m",
            "the reset reads as time remaining, got: " + healthy.resetText);
        assert(dateless.resetText === "", "no reset time, no reset text");
        assert(empty.resetTextFor("2026-10-02T15:59:00Z", testRoot.nowMs) === "resetting now",
            "a past reset is rolling over now");

        const inSixHours = empty.resetTextFor("2026-10-02T22:00:00Z", testRoot.nowMs);
        assert(inSixHours === "resets in 6h", "whole hours drop the minutes, got: " + inSixHours);
        const inFourDays = empty.resetTextFor("2026-10-06T20:00:00Z", testRoot.nowMs);
        assert(inFourDays.indexOf("resets in 4d") === 0, "days lead above 24h, got: " + inFourDays);

        // ------------------------------------------------------------------
        // Geometry: the picture matches the numbers
        // ------------------------------------------------------------------
        const track = healthy.trackItem;
        assert(Math.abs(healthy.fillItem.width - track.width * healthy.fillFraction) <= 1.0,
            "the fill covers the remaining allowance (" + healthy.fillItem.width + " vs " + track.width * healthy.fillFraction + ")");
        assert(Math.abs(healthy.tickItem.x - (track.width * healthy.markerFraction - 1)) <= 1.0,
            "the tick sits at the roll-over (" + healthy.tickItem.x + ")");
        assert(healthy.fillItem.width > 0 && healthy.fillItem.width < track.width,
            "a partly used window is partly filled");
        assert(empty.fillItem.width === 0, "an exhausted window draws no fill at all");
        assert(dateless.tickItem.visible === false, "a window we cannot date shows no tick");

        console.log("PASS: Quota Runway");
        Qt.exit(0);
    }
}
