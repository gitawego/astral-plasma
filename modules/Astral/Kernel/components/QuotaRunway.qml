import QtQuick
import "../theme"
import "StateColor.js" as StateColor
import "QuotaMath.js" as QuotaMath

// ============================================================================
// Quota runway
// ============================================================================
// One rate-limit window on a single axis: what is left, and when it resets.
//
// A quota is not a percentage, it is a budget with a deadline, so both live on the
// same track - the fill is what remains, the tick is where the window rolls over.
// Reading one row answers the only question a user has ("do I have room, and for
// how long?"), which a bare progress bar plus a percentage caption cannot.
//
// Two rules keep it honest:
//
//   * Running out is *normal*, not an error: an exhausted window renders as a
//     dimmed empty track with the reset time promoted - never as a red bar. Red
//     is reserved for a provider that is unavailable or misconfigured.
//   * No reset time on the wire means no marker. A quoted window length is not
//     invented; the label's kind (5h / weekly / monthly) is the window length, and
//     anything else gets no tick at all.
//
// The mapping functions are pure and asserted by `tests/tst_quota_runway.qml`.
Item {
    id: root

    // Motion tokens with fallbacks (the harness resolves Theme without an
    // archetype; the real shell always has them).
    readonly property int motionFast: (typeof Theme !== "undefined" && Theme.animExpressiveFastEffects !== undefined)
        ? Theme.animExpressiveFastEffects : 150
    readonly property var motionFastCurve: (typeof Theme !== "undefined" && Theme.curveExpressiveFastEffects !== undefined)
        ? Theme.curveExpressiveFastEffects : [0.2, 0.0, 0.0, 1.0]

    /// Remaining allowance, 0..100. A negative value means "not reported".
    property real remainingPercent: 0
    /// Human window title ("5-Hour Rolling Limit"); the compact variant uses
    /// `windowLabel` instead.
    property string title: ""
    /// Window kind as the daemon labels it: "5h", "weekly", "monthly".
    property string windowLabel: "5h"
    /// Window roll-over, RFC3339 (`2026-10-02T21:46:01Z`), or "" when unknown.
    property string resetAt: ""
    /// Used% at which the runway turns amber, then rose (the user's own
    /// thresholds from the AI page).
    property real warningThreshold: 80
    property real criticalThreshold: 95
    /// Injectable clock, so the reset text and marker are testable.
    property real now: Date.now()
    /// Dense variant for the provider grid.
    property bool compact: false

    readonly property real usedPercent: Math.max(0, Math.min(100, 100 - root.remainingPercent))
    /// "unknown" | "ok" | "watch" | "critical" | "exhausted"
    readonly property string state: root.stateFor(root.remainingPercent, root.warningThreshold, root.criticalThreshold)
    readonly property real fillFraction: root.remainingPercent > 0
        ? Math.max(0, Math.min(1, root.remainingPercent / 100)) : 0
    readonly property real markerFraction: root.markerFractionFor(root.resetAt, root.now, root.windowLabel)
    readonly property string resetText: root.resetTextFor(root.resetAt, root.now)
    /// The severity the runway reports, in the shell's shared vocabulary:
    /// a used-up window is `idle` (normal), not `critical` (broken).
    readonly property string severity: QuotaMath.severityFor(root.state)
    readonly property color stateColor: StateColor.colorFor(root.severity, Colors)
    /// What the right-hand value reads: the percentage, or "—" when unknown.
    readonly property string valueText: root.remainingPercent < 0
        ? "—"
        : (Math.round(root.remainingPercent) + "%")

    // ------------------------------------------------------------------
    // Pure mapping (unit-tested)
    // ------------------------------------------------------------------

    // The rules live in `components/QuotaMath.js` so a rail, a badge or a tooltip
    // can summarise with the same functions this bar renders. These wrappers keep
    // the component's own surface (and its callers) unchanged.
    function stateFor(remainingPercent, warning, critical) {
        return QuotaMath.stateFor(remainingPercent, warning, critical);
    }
    function windowMinutesFor(label) {
        return QuotaMath.windowMinutesFor(label);
    }
    function markerFractionFor(resetAt, nowMs, label) {
        return QuotaMath.markerFractionFor(resetAt, nowMs, label);
    }
    function resetTextFor(resetAt, nowMs) {
        return QuotaMath.resetTextFor(resetAt, nowMs);
    }
    function parseMs(iso) {
        return QuotaMath.parseMs(iso);
    }

    // ------------------------------------------------------------------
    // Rendering
    // ------------------------------------------------------------------
    /// Test / introspection surface (the geometry assertions read these).
    property alias trackItem: track
    property alias fillItem: fill
    property alias tickItem: tick
    property alias axisItem: axis

    implicitHeight: column.implicitHeight

    Column {
        id: column
        width: parent.width
        spacing: root.compact ? 4 : 6

        Row {
            width: parent.width

            Text {
                width: parent.width - value.implicitWidth - 12
                text: root.compact
                    ? (root.windowLabel.charAt(0).toUpperCase() + root.windowLabel.slice(1))
                    : (root.title !== "" ? root.title : root.windowLabel)
                font.family: Theme.fontFamily
                font.pixelSize: root.compact ? 11 : 12
                font.weight: root.compact ? Font.DemiBold : Font.Medium
                color: Colors.m3onSurface
                elide: Text.ElideRight
            }

            Text {
                id: value
                text: root.valueText + (root.resetText !== "" ? "  ·  " + root.resetText : "")
                font.family: Theme.fontFamily
                font.pixelSize: root.compact ? 10 : 11
                // Tabular figures: the number changes on every poll, and
                // proportional digits make the whole row twitch as it does.
                font.features: ({ "tnum": 1 })
                color: root.state === "exhausted" || root.state === "unknown"
                    ? Colors.m3onSurfaceVariant
                    : root.stateColor
            }
        }

        // The shared axis: track = the window, fill = what is left, tick = reset.
        Item {
            id: axis
            width: parent.width
            height: 6

            Rectangle {
                id: track
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 6
                radius: Theme.radiusFull
                // An exhausted window dims instead of shouting: out of quota is a
                // normal state of a rate limit.
                color: root.state === "exhausted"
                    ? Qt.alpha(Colors.m3onSurface, 0.06)
                    : Qt.alpha(Colors.outlineVariant, 0.35)
            }

            Rectangle {
                id: fill
                anchors.verticalCenter: parent.verticalCenter
                width: track.width * root.fillFraction
                height: track.height
                radius: Theme.radiusFull
                color: root.stateColor

                Behavior on width {
                    NumberAnimation {
                        duration: root.motionFast
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: root.motionFastCurve
                    }
                }
            }

            // Reset tick: where the window rolls over, on the same axis.
            Rectangle {
                id: tick
                visible: root.markerFraction > 0
                x: Math.round(track.width * root.markerFraction) - 1
                y: -2
                width: 2
                height: axis.height + 4
                radius: 1
                color: Qt.alpha(Colors.m3onSurfaceVariant, 0.9)

                Behavior on x {
                    NumberAnimation {
                        duration: root.motionFast
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: root.motionFastCurve
                    }
                }
            }
        }
    }
}
