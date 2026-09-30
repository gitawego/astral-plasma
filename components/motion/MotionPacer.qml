import QtQuick

// ============================================================================
// MotionPacer — phase generator for decorative motion, on the shared clock
// ============================================================================
// Decorative effects (AI/download border activity, ambient visualizers, slow
// cover rotations) must advance their phase on MotionClock rather than with a
// NumberAnimation/SequentialAnimation. See MotionClock.qml for why.
//
// The phase is derived from the clock's monotonic elapsed time, so it is
// wall-clock accurate: a late or coalesced tick never slows the motion down,
// it only reduces the sampling density. While `running` is false the pacer
// releases the clock and rests at phase 0, so an idle shell renders nothing.
//
// Usage
// -----
//     MotionPacer {
//         id: motion
//         running: root.active && root.growthProgress > 0.01
//         period: 2 * root.pulseDurationMs      // full cycle, in ms
//     }
//     property real pulse: motion.breath        // 0 → 1 → 0 cosine breath
//     property real travel: motion.phase        // linear 0 → 1 sweep
//
// Non-visual (0×0 Item, matching PreviewCycle) so it can be declared as a child
// of any visual item without affecting layout or rendering.
Item {
    id: root

    width: 0
    height: 0

    // Whether the phase advances. While false the pacer holds no clock
    // reference and consumes no CPU at all.
    property bool running: false

    // Duration of one full cycle, in milliseconds.
    property real period: 1000

    // Defensive resolution: a consumer may forward a token that the runtime
    // could not instantiate (offscreen tests), in which case `period` may be
    // undefined/NaN. The phase math must never degrade into NaN.
    readonly property real resolvedPeriod: (isFinite(root.period) && root.period > 0)
        ? root.period
        : 1000

    // Clock time at which the current cycle started.
    property double _startMs: 0

    // Current position within the cycle, in [0, 1). Linear in time; rests at 0
    // while stopped.
    readonly property real phase: root.running
        ? root._frac((MotionClock.elapsedMs - root._startMs) / root.resolvedPeriod)
        : 0.0

    // Cosine breath envelope over the cycle: 0 → 1 → 0, identical to two
    // chained InOutSine NumberAnimations spanning `period` together.
    readonly property real breath: (1.0 - Math.cos(2.0 * Math.PI * root.phase)) * 0.5

    // Sine envelope over the cycle: 0 → 1 → 0 → -1, for pendulum-style motion.
    readonly property real wave: Math.sin(2.0 * Math.PI * root.phase)

    function _frac(x) {
        return x - Math.floor(x);
    }

    function _attach() {
        if (root._acquired) return;
        root._acquired = true;
        root._startMs = MotionClock.elapsedMs;
        MotionClock.acquire();
    }

    function _detach() {
        if (!root._acquired) return;
        root._acquired = false;
        MotionClock.release();
    }

    // Guards the acquire/release pairing: `running` may already be true while
    // bindings settle, so onRunningChanged, Component.onCompleted and
    // Component.onDestruction must all be idempotent.
    property bool _acquired: false

    onRunningChanged: {
        if (root.running) root._attach();
        else root._detach();
    }

    Component.onCompleted: {
        if (root.running) root._attach();
    }

    Component.onDestruction: {
        root._detach();
    }
}
