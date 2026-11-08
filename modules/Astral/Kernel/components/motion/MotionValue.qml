import QtQuick

// ============================================================================
// MotionValue — a number that eases towards its target on the shared clock
// ============================================================================
// The companion to MotionTween for the common data-driven case: a meter, bar or
// readout that should follow a metric value smoothly. A `Behavior on width`
// cannot do this within a budget - it advances at display refresh, and when the
// metric arrives faster than the animation's duration it is restarted before it
// ever finishes, so the host is repainted at every display frame for as long as
// the surface is open (measured: 43.8 % of the iGPU for the performance tab).
//
// The value eases on MotionClock ticks (≤ `decorativeMaxFps` per second), takes
// over from wherever it currently is when the target moves mid-flight, and
// releases the clock on arrival. While `animated` is false it tracks the target
// exactly and holds nothing at all, which is what a hidden surface wants.
//
// Usage
// -----
//     MotionValue {
//         id: cpuBar
//         animated: root.isTargetVisible
//         duration: Theme.animExpressiveFastSpatial
//         bezier: Theme.curveExpressiveFastSpatial
//         target: SystemService.cpuUsage
//     }
//     width: parent.width * cpuBar.value
//
// Non-visual (0×0 Item, matching MotionPacer/MotionTween), so declaring it as a
// child of a layout costs nothing - but keep it out of one to be safe.
Item {
    id: root

    width: 0
    height: 0

    // The value to settle on.
    property real target: 0.0

    // While false the value tracks `target` exactly (a hidden surface still shows
    // the right thing when it comes back, without ever running an animation).
    property bool animated: true

    // Duration of one ease, in milliseconds.
    property int duration: 250

    // Cubic bezier control points [x1, y1, x2, y2], as `Theme.curve*` tokens are
    // shaped. Falsy means linear.
    property var bezier: null

    // Emitted for every advanced frame, so a Canvas host can repaint from one
    // place instead of binding to the value.
    signal advanced()

    // The eased value to render.
    readonly property real value: tween.value

    MotionTween {
        id: tween
        from: root.target
        to: root.target
        duration: root.duration
        bezier: root.bezier
        onAdvanced: root.advanced()
    }

    onTargetChanged: root._retarget()
    onAnimatedChanged: root._retarget()

    Component.onCompleted: root._settle()

    // Ease from where the value currently is, so retargeting mid-flight never
    // jumps. `MotionTween.restart()` keeps a single clock reference, so a fast
    // metric stream cannot leak references either.
    function _retarget(): void {
        if (!root.animated) {
            root._settle();
            return;
        }
        tween.from = tween.value;
        tween.to = root.target;
        tween.restart();
    }

    function _settle(): void {
        tween.stop();
        tween.from = root.target;
        tween.to = root.target;
        tween.complete();
    }
}
