pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

// ============================================================================
// DisplayService — apply the display refresh preference
// ============================================================================
// The shell's own motion is budgeted at 30 fps, so the panel's refresh rate is a
// power/performance choice rather than something the UI needs (docs/LESSONS.md 33:
// capping 240 Hz to 60 Hz cut every client's per-frame work by 4x, including the
// compositor's blend and blur of the shell's glass).
//
// The switch itself belongs to the daemon: it picks the highest refresh at the
// *current resolution* that does not exceed the preference, records what the
// session was running before the first switch, and `run.sh` puts that back when
// the shell exits. This service only asks for it - at startup, and whenever the
// setting changes. Applying is idempotent: the daemon leaves outputs that already
// satisfy the preference untouched, so a second apply never blanks the screen.
Singleton {
    id: root

    readonly property string preference: (typeof Config !== "undefined" && Config)
        ? ("" + Config.displayRefreshRate)
        : "60"

    readonly property string serviceDir: Qt.resolvedUrl(".").toString().replace("file://", "")
    readonly property string daemonBin: root.serviceDir + "/../bin/astral-plasma"

    // Last outcome, so the settings page can confirm what actually happened
    // ("applied" / "unchanged") instead of assuming the request succeeded.
    property bool applying: false
    property bool lastApplySucceeded: false
    property string lastApplied: ""

    function apply(preference) {
        const target = (preference === undefined || preference === null || preference === "")
            ? root.preference
            : ("" + preference);
        applyProc.running = false;
        root.applying = true;
        root.lastApplied = target;
        applyProc.command = [root.daemonBin, "display", "apply", target];
        applyProc.running = true;
    }

    Process {
        id: applyProc
        stdout: StdioCollector {
            onStreamFinished: {
                const text = this.text.trim();
                if (!text) return;
                try {
                    const result = JSON.parse(text);
                    if (result && result.preference) {
                        root.lastApplied = "" + result.preference;
                    }
                } catch (e) {
                    // A malformed reply must not take the shell down; the state
                    // simply stays as it was.
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            root.applying = false;
            root.lastApplySucceeded = exitCode === 0;
        }
    }

    onPreferenceChanged: root.apply()
    Component.onCompleted: root.apply()
}
