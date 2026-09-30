pragma Singleton

import QtQuick
import "../../theme"

// ============================================================================
// MotionClock — single shared tick for every decorative animation
// ============================================================================
// Qt Quick repaints the whole window for every batch of property changes, and a
// QML animation advances at display refresh rate. If each decorative effect owns
// its own timer, N uncorrelated 30 Hz animations still add up to N×30 full-window
// renders per second (measured: two pacers per border effect produced 60 fps on a
// 60 Hz output). A single shared clock makes every decorative update land in the
// same frame instead, so the whole shell is capped at Theme.decorativeMaxFps no
// matter how many effects are running, on any display refresh rate.
//
// The clock only ticks while at least one MotionPacer holds a reference
// (acquire/release), so an idle shell performs zero decorative work and touches
// no timers.
Item {
    id: root

    width: 0
    height: 0

    // Frames per second for all decorative motion. Deliberately far below the
    // 165–240 Hz of modern panels: these are slow pulses, light packets and
    // ambient rotations, not interactive transitions.
    readonly property int frameBudget: (typeof Theme !== "undefined" && Theme.decorativeMaxFps)
        ? Theme.decorativeMaxFps
        : 30

    // Number of active consumers (MotionPacers). The ticker stops at zero.
    property int consumers: 0

    // Monotonic time accumulated while the clock runs, in milliseconds.
    property double elapsedMs: 0

    // Emitted-frame counter. Binding to it is equivalent to binding to elapsedMs
    // but always changes once per emitted frame.
    readonly property int tick: _tick
    property int _tick: 0

    property double _lastMs: 0

    function acquire() {
        root.consumers++;
    }

    function release() {
        root.consumers = Math.max(0, root.consumers - 1);
    }

    Timer {
        id: ticker
        interval: Math.max(1, Math.round(1000 / Math.max(1, root.frameBudget)))
        repeat: true
        running: root.consumers > 0
        onRunningChanged: {
            // Never accumulate the idle gap into elapsedMs: restarting the clock
            // resumes every phase where it stopped instead of jumping ahead.
            if (!ticker.running) root._lastMs = 0;
        }
        onTriggered: {
            const now = Date.now();
            if (root._lastMs > 0) {
                root.elapsedMs += Math.max(0, now - root._lastMs);
            }
            root._lastMs = now;
            root._tick++;
        }
    }
}
