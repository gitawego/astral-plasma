import QtQuick
import "../components/motion"

// ============================================================================
// MotionClock / MotionPacer — decorative frame-budget unit tests
// ============================================================================
// Verifies:
// 1. Idle contract: stopped pacers hold no clock reference and rest at phase 0.
// 2. Wall-clock accuracy: phases advance with real time, not tick count.
// 3. A single shared clock: N running pacers still tick the clock at ≤ frameBudget
//    per second, so updates coalesce into one frame instead of N interleaved ones
//    (the regression that made two 30 Hz pacers render at 60 fps).
// 4. Envelope math: breath is a 0 → 1 → 0 cosine wave over the cycle.
// 5. Degenerate periods never produce a NaN phase.
//
// Note: Theme deliberately is not imported here. Theme's root type comes from
// Quickshell, which the offscreen qml6 runtime cannot instantiate, so runtime
// token reads are undefined there; MotionClock must fall back to 30 fps.
Item {
    id: testRoot
    width: 200
    height: 200

    MotionPacer { id: pacerA; period: 1000 }
    MotionPacer { id: pacerB; period: 700 }

    property int phaseAChanges: 0

    Connections {
        target: pacerA
        function onPhaseChanged() { testRoot.phaseAChanges++; }
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

    Timer {
        interval: 40
        running: true
        repeat: false
        onTriggered: stageIdle()
    }

    // ---- 1. Idle contract -------------------------------------------------
    function stageIdle() {
        assert(MotionClock.frameBudget === 30,
            "MotionClock frameBudget must fall back to 30 fps (got " + MotionClock.frameBudget + ")");
        assert(MotionClock.consumers === 0,
            "no pacer may hold a clock reference while idle (got " + MotionClock.consumers + ")");
        assert(pacerA.phase === 0.0 && pacerB.phase === 0.0,
            "stopped pacers must rest at phase 0");
        assert(pacerA.breath === 0.0, "stopped pacer must rest at breath 0");
        assert(MotionClock.tick === 0, "clock must not tick while no pacer runs (got " + MotionClock.tick + ")");

        // Degenerate period must resolve, not poison the phase math.
        pacerA.period = NaN;
        assert(pacerA.resolvedPeriod === 1000, "resolvedPeriod must reject NaN");
        pacerA.period = 0;
        assert(pacerA.resolvedPeriod === 1000, "resolvedPeriod must reject 0");
        pacerA.period = 1000;

        pacerA.running = true;
        pacerB.running = true;
        assert(MotionClock.consumers === 2,
            "two running pacers must hold two clock references (got " + MotionClock.consumers + ")");
        verifyTimer.start();
    }

    // ---- 2. Running: wall-clock accuracy + shared-clock cap ---------------
    Timer {
        id: verifyTimer
        interval: 600
        repeat: false
        onTriggered: verifyRunning()
    }

    function verifyRunning() {
        const p = pacerA.phase;
        // 600 ms of a 1000 ms cycle ⇒ ≈ 0.6 expected. Generous tolerance so the
        // assertion stays valid when the suite runs in a loaded parallel batch,
        // while still failing a stopped or wildly mis-rated clock.
        assert(p > 0.2 && p < 0.95,
            "phase must track wall-clock time (~0.6 after 600ms), got " + p);
        assert(phaseAChanges >= 3,
            "running pacer must actually update the phase, got " + phaseAChanges + " updates");
        // The shared clock ticks once per frame, no matter how many pacers run:
        // 600 ms at 30 fps ⇒ ≈ 18 ticks, never the ~36 two interleaved timers
        // would produce.
        assert(MotionClock.tick >= 5 && MotionClock.tick <= 24,
            "shared clock must tick at ≤ 30 fps with 2 pacers, got " + MotionClock.tick + " in 600ms");

        // ---- 3. Stop releases every reference and freezes ----------------
        pacerA.running = false;
        pacerB.running = false;
        assert(MotionClock.consumers === 0,
            "stopping every pacer must release the clock (got " + MotionClock.consumers + ")");
        assert(pacerA.phase === 0.0 && pacerB.phase === 0.0,
            "stopped pacers must rest at phase 0");
        const tickAtStop = MotionClock.tick;
        pacerA.period = 1000;
        freezeCheck.tickAtStop = tickAtStop;
        freezeCheck.start();
    }

    Timer {
        id: freezeCheck
        interval: 250
        repeat: false
        property int tickAtStop: 0
        onTriggered: {
            assert(MotionClock.tick === freezeCheck.tickAtStop,
                "clock must stop ticking once every pacer is idle ("
                + freezeCheck.tickAtStop + " → " + MotionClock.tick + ")");

            // ---- 4. Envelope math (deterministic: drive the clock directly) ---
            // phase is derived from MotionClock.elapsedMs, so seed both freely
            // while every pacer is stopped and the clock is not ticking.
            pacerA.running = true;
            const base = MotionClock.elapsedMs;
            pacerA._startMs = base;
            pacerA.period = 1000;

            MotionClock.elapsedMs = base + 0;
            assert(Math.abs(pacerA.breath - 0.0) < 1e-6, "breath(0) must be 0");
            MotionClock.elapsedMs = base + 250;
            assert(Math.abs(pacerA.phase - 0.25) < 1e-6, "phase(t) must be t/period, got " + pacerA.phase);
            assert(Math.abs(pacerA.breath - 0.5) < 1e-6, "breath(0.25) must be 0.5");
            MotionClock.elapsedMs = base + 500;
            assert(Math.abs(pacerA.breath - 1.0) < 1e-6, "breath(0.5) must be 1");
            MotionClock.elapsedMs = base + 750;
            assert(Math.abs(pacerA.breath - 0.5) < 1e-6, "breath(0.75) must be 0.5");
            MotionClock.elapsedMs = base + 1000;
            assert(Math.abs(pacerA.phase) < 1e-6, "phase must wrap at the period boundary");
            pacerA.running = false;

            console.log("PASS: MotionClock/MotionPacer shared-clock, frame-cap and idle tests passed");
            Qt.exit(0);
        }
    }
}
