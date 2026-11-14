import QtQuick
import "../theme"

// FusedPanel is the legacy entry point: the fused panel geometry plus the
// original progress Behavior. FusedEdgePanel itself is geometry-only so the
// shell can drive offsetProgress with its own motion tokens (the dashboard
// already animates it); this wrapper preserves the behavior existing consumers
// (notifications, tests) rely on.
FusedEdgePanel {
    Behavior on offsetProgress {
        NumberAnimation {
            duration: (typeof Theme !== "undefined" && Theme.animExpressiveDefaultSpatial) ? Theme.animExpressiveDefaultSpatial : 500
            easing.type: Easing.BezierSpline
            easing.bezierCurve: (typeof Theme !== "undefined" && Theme.curveExpressiveDefaultSpatial) ? Theme.curveExpressiveDefaultSpatial : [0.38, 1.21, 0.22, 1.0, 1.0, 1.0]
        }
    }
}
