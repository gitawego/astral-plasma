import QtQuick

// ============================================================================
// MotionTick — hold the decorative clock, emit once per clock frame
// ============================================================================
// A consumer that needs a *sample per frame* rather than a phase (e.g. mirroring
// a fast stream onto the decorative budget) still has to be a clock consumer, or
// nothing ticks at all: MotionClock only runs while at least one of these holds a
// reference.
//
// While `running` it holds one clock reference and emits `ticked()` on every
// clock frame - at most `Theme.decorativeMaxFps` times per second on any display,
// coalesced with every other decorative consumer into a single frame. While false
// it holds nothing and costs nothing.
//
// Usage
// -----
//     MotionTick {
//         running: stream.active
//         onTicked: root.sample = stream.raw        // once per decorative frame
//     }
//
// Non-visual (0×0 Item, matching MotionPacer/MotionTween/MotionValue).
Item {
    id: root

    width: 0
    height: 0

    property bool running: false

    // Emitted once per clock frame while running.
    signal ticked()

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

    Connections {
        target: MotionClock
        function onTickChanged() {
            if (root.running) {
                root.ticked();
            }
        }
    }
}
