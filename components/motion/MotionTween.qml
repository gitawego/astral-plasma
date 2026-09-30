import QtQuick

// ============================================================================
// MotionTween — one-shot transition on the shared decorative clock
// ============================================================================
// MotionPacer covers *cyclic* decoration (pulses, travelling light, ambient
// rotation). Data-driven surfaces need the other shape: a transition that runs
// once per new sample and then rests.
//
// A Qt animation cannot be rate-limited, and `Behavior`/`NumberAnimation` advance
// at display refresh. When the sample interval is shorter than the animation's
// duration the animation is restarted before it can finish, so it is *never idle*
// and every frame repaints its host: the performance tab's telemetry slide and
// usage bars held the shell at 43.8 % of the iGPU for as long as the tab was open.
//
// This tween advances from `from` to `to` over `duration` on MotionClock ticks,
// so it costs at most `decorativeMaxFps` frames per second, is wall-clock accurate
// (a coalesced tick never slows it down), lands exactly on `to`, and releases the
// clock when it finishes - an idle shell keeps rendering nothing.
//
// Usage
// -----
//     MotionTween {
//         id: slide
//         duration: Theme.animExpressiveFastEffects
//         bezier: Theme.curveExpressiveFastEffects
//         from: 0.0
//         to: 1.0
//         onAdvanced: canvas.requestPaint()
//     }
//     onSampleChanged: slide.restart()
//
// Non-visual (0×0 Item, matching MotionPacer) so it can be declared as a child of
// any visual item without affecting layout or rendering.
Item {
    id: root

    width: 0
    height: 0

    // Transition endpoints. `to` may be re-bound while running: the next tick
    // eases towards the new value.
    property real from: 0.0
    property real to: 1.0

    // Duration of one transition, in milliseconds. 0 finishes on the next tick.
    property int duration: 250

    // Cubic bezier control points [x1, y1, x2, y2], as `Theme.curve*` tokens are
    // shaped (a trailing end point is ignored). Falsy means linear.
    property var bezier: null

    // Whether the transition is in flight. Set through `restart()`/`stop()`.
    property bool running: false

    // Emitted for every advanced frame while running, and once when a transition
    // starts, so a host can paint from a single place.
    signal advanced()
    signal finished()

    // Clock time at which the current transition started.
    property double _startMs: 0
    // Eased progress in [0, 1].
    property real progress: 0.0

    // Interpolated value; this is what hosts bind to.
    readonly property real value: root.from + (root.to - root.from) * root.progress

    // The clock only ticks while something holds it, so a finished tween costs
    // nothing at all - not even a timer.
    onRunningChanged: {
        if (root.running) {
            MotionClock.acquire();
        } else {
            MotionClock.release();
        }
    }

    Component.onDestruction: {
        if (root.running) {
            root.running = false;
        }
    }

    // Restart from the current `from`/`to`, whether or not a transition is in
    // flight. Restarting never takes a second clock reference.
    function restart(): void {
        root._startMs = MotionClock.elapsedMs;
        if (root.duration <= 0) {
            root.progress = 1.0;
            root.running = false;
            root.advanced();
            root.finished();
            return;
        }
        root.progress = 0.0;
        root.running = true;
        root.advanced();
    }

    // Jump to the end immediately (used when a host is hidden: the value must
    // still be correct when it comes back).
    function complete(): void {
        root.progress = 1.0;
        if (root.running) {
            root.running = false;
        }
        root.advanced();
        root.finished();
    }

    function stop(): void {
        if (root.running) {
            root.running = false;
        }
    }

    Connections {
        target: MotionClock
        function onTickChanged() {
            if (root.running) {
                root._advance();
            }
        }
    }

    function _advance(): void {
        const elapsed = MotionClock.elapsedMs - root._startMs;
        const t = root.duration <= 0 ? 1.0 : Math.min(1.0, elapsed / root.duration);
        root.progress = root._ease(t);
        if (t >= 1.0) {
            root.progress = 1.0;
            root.running = false;
            root.advanced();
            root.finished();
            return;
        }
        root.advanced();
    }

    // CGFloat-style cubic bezier easing: solve x(u) = t, return y(u).
    function _ease(t: real): real {
        const c = root.bezier;
        if (!c || c.length < 4) {
            return t;
        }
        const x1 = c[0];
        const y1 = c[1];
        const x2 = c[2];
        const y2 = c[3];
        let u = t;
        for (let i = 0; i < 8; ++i) {
            const x = root._bezierAxis(u, x1, x2) - t;
            if (Math.abs(x) < 1e-4) {
                break;
            }
            const d = root._bezierSlope(u, x1, x2);
            if (Math.abs(d) < 1e-6) {
                break;
            }
            u -= x / d;
        }
        u = Math.min(1.0, Math.max(0.0, u));
        return root._bezierAxis(u, y1, y2);
    }

    function _bezierAxis(u: real, a1: real, a2: real): real {
        const v = 1.0 - u;
        return 3.0 * v * v * u * a1 + 3.0 * v * u * u * a2 + u * u * u;
    }

    function _bezierSlope(u: real, a1: real, a2: real): real {
        const v = 1.0 - u;
        return 3.0 * v * v * a1 + 6.0 * v * u * (a2 - a1) + 3.0 * u * u * (1.0 - a2);
    }
}
