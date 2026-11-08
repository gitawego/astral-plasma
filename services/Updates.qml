pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

// ============================================================================
// Release state, as the daemon reports it
// ============================================================================
// The daemon owns every decision about an update: whether one exists, whether
// this install may apply it, and what the user would be installing. This service
// only reads that answer and exposes it to the Settings page and the curtain. It
// never invents a version, a percentage or a changelog line.
Singleton {
    id: root

    readonly property string serviceDir: Qt.resolvedUrl(".").toString().replace("file://", "").replace(/\/$/, "")
    readonly property string daemonBin: (typeof Config !== "undefined" && Config.daemonBin) ? Config.daemonBin : (root.serviceDir + "/../bin/astral-plasma")

    /// Test seam: a page may inject a status object instead of running a process.
    property bool testMode: false
    property var testStatus: null
    property var testChangelog: null

    property string currentVersion: ""
    property string channel: "stable"
    property string installMethod: ""
    property bool canApply: false
    property string refuseReason: ""
    property string candidateVersion: ""
    property var highlights: []
    property int candidateBytes: 0
    property string lastError: ""
    property string rollbackVersion: ""
    property string rollbackReason: ""
    property string restartPending: ""
    property int lastCheckUnix: 0
    property string lastSeenVersion: ""
    property var changelog: []

    readonly property bool updateAvailable: root.candidateVersion !== ""
    readonly property bool applying: applyProc.running
    property string applyError: ""

    function applyStatus(status) {
        if (!status || typeof status !== "object") return;
        root.currentVersion = status.current_version || "";
        root.channel = status.channel || "stable";
        root.installMethod = status.install_method || "";
        root.canApply = status.can_apply === true;
        root.refuseReason = status.refuse_reason || "";
        root.lastError = status.last_error || "";
        root.lastCheckUnix = status.last_check_unix || 0;
        root.lastSeenVersion = status.last_seen_version || "";
        root.restartPending = status.restart_pending || "";
        root.rollbackVersion = (status.rollback && status.rollback.version) || "";
        root.rollbackReason = (status.rollback && status.rollback.reason) || "";
        const candidate = status.candidate || null;
        root.candidateVersion = candidate ? candidate.version : "";
        root.highlights = candidate && candidate.highlights ? candidate.highlights : [];
        root.candidateBytes = candidate ? candidate.size : 0;
    }

    function refresh() {
        if (root.testMode) {
            root.applyStatus(root.testStatus);
            root.changelog = root.testChangelog || [];
            return;
        }
        if (!statusProc.running) statusProc.running = true;
        if (!changelogProc.running) changelogProc.running = true;
    }

    /// Ask the daemon to look now; the status refresh follows.
    function checkNow() {
        if (root.testMode) return;
        Quickshell.execDetached([root.daemonBin, "update", "check"]);
        refreshTimer.restart();
    }

    /// Stage and apply the candidate. The daemon asks the shell to exit; the
    /// supervisor swaps the binary and restarts it with the desktop claim kept.
    function applyUpdate() {
        if (root.testMode) return;
        root.applyError = "";
        applyProc.running = true;
    }

    /// Go back to the previous installed release and restart into it.
    function revert() {
        if (root.testMode) return;
        revertProc.running = true;
    }

    /// Record that this version's notes have been shown.
    function markSeen(version) {
        if (root.testMode || !version) return;
        Quickshell.execDetached([root.daemonBin, "update", "seen", version]);
    }

    function uninstall() {
        if (root.testMode) return;
        // --from-shell keeps the desktop claim alive: the shell exits through
        // its own IPC after the files are gone, so the supervisor can still
        // restore the user's panels.
        Quickshell.execDetached([root.daemonBin, "uninstall", "--yes", "--from-shell"]);
    }

    Process {
        id: statusProc
        command: [root.daemonBin, "update", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                const text = this.text.trim();
                if (!text.startsWith("{")) return;
                try {
                    root.applyStatus(JSON.parse(text));
                } catch (e) {
                    console.warn("Updates: status parse error:", e);
                }
            }
        }
    }

    Process {
        id: changelogProc
        command: [root.daemonBin, "changelog", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                const text = this.text.trim();
                if (!text.startsWith("[")) return;
                try {
                    root.changelog = JSON.parse(text);
                } catch (e) {
                    console.warn("Updates: changelog parse error:", e);
                }
            }
        }
    }

    Process {
        id: revertProc
        command: [root.daemonBin, "update", "revert", "--yes"]
        stderr: StdioCollector {
            onStreamFinished: {
                const text = this.text.trim();
                if (text) root.applyError = text;
            }
        }
        onExited: root.refresh()
    }

    Process {
        id: applyProc
        command: [root.daemonBin, "update", "apply", "--yes"]
        stderr: StdioCollector {
            onStreamFinished: {
                const text = this.text.trim();
                if (text) root.applyError = text;
            }
        }
        onExited: (exitCode) => {
            if (exitCode !== 0 && root.applyError === "") {
                root.applyError = "The update could not be applied.";
            }
            root.refresh();
        }
    }

    Timer {
        id: refreshTimer
        interval: 3000
        repeat: false
        onTriggered: root.refresh()
    }

    // Status is cheap (a state file); poll it so a check made by the daemon's own
    // six-hour timer appears without the user opening Settings.
    Timer {
        interval: 120000
        repeat: true
        running: !root.testMode
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}
