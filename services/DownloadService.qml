pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

// Event-driven download state: ONE long-lived `downloads watch` process
// streams change-only snapshot lines (full state on start, then deltas at
// 1s active / 5s idle cadence, 0.5% progress quanta). QML holds NO polling
// timer — the daemon decides when state changed. Commands (add/pause/…)
// run on a separate short-lived Process so a busy control call can never
// swallow an event line.
//
// Perf contract: ~2 event lines/s worst case while downloading, ~0.2/s idle.
// Each line updates properties once; the border HUD and tab rows bind to
// these properties (fill fraction = total.progress, packet motion = speed).
Singleton {
    id: root

    // --- Snapshot state (bound by tab rows + border HUD) ---
    property var activeTasks: []
    property var waitingTasks: []
    property var stoppedTasks: []
    property real totalProgress: 0.0
    property double totalCompletedBytes: 0
    property double totalBytes: 0
    property double totalSpeed: 0
    property int activeCount: 0
    property bool indeterminate: false
    property bool ariaAvailable: true
    property string lastError: ""

    // Completion edge detection: daemon emits change-only lines, so a gid
    // moving active/waiting -> stopped+complete fires exactly once here.
    // Consumers (NotificationService) connect to downloadFinished; the tab
    // connects to downloadFailed for the retry toast. Burst guard: at most
    // one toast per gid per 10s (10 files finishing at once = 10 lines).
    signal downloadFinished(string gid, string name)
    signal downloadFailed(string gid, string name)
    signal snapshotChanged()

    property var _prevStatus: ({})
    property var _lastToastAt: ({})

    // --- Settings mirrors (Config is the source of truth) ---
    readonly property string defaultDir: (typeof Config !== "undefined" && Config.downloadsDir)
        ? Config.downloadsDir : ""
    readonly property int defaultSplit: (typeof Config !== "undefined" && Config.downloadsSplit)
        ? Config.downloadsSplit : 4

    readonly property string serviceDir: Qt.resolvedUrl(".").toString().replace("file://", "").replace(/\/$/, "")
    readonly property string daemonBin: root.serviceDir + "/../bin/astral-plasma"

    function watchCommand() {
        const cmd = [root.daemonBin, "downloads", "watch"];
        if (root.defaultDir && root.defaultDir.length > 0) {
            cmd.push("--dir", root.defaultDir);
        }
        cmd.push("--split", String(root.defaultSplit || 4));
        return cmd;
    }

    // Long-lived event stream. Auto-restarts on exit (daemon upgrades,
    // crashes): 1s backoff, no busy loop.
    Process {
        id: watchProc
        command: root.watchCommand()
        running: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: raw => {
                try {
                    const line = raw.trim();
                    if (!line || !line.startsWith("{")) return;
                    const data = JSON.parse(line);
                    if (!data || (data.msg_type !== "downloads" && data.type !== "downloads")) return;
                    root.applySnapshot(data);
                } catch (e) {
                    console.warn("DownloadService event parse error:", e);
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (this.text.trim()) console.warn("downloads watch stderr:", this.text.trim());
            }
        }
        onExited: (exitCode, exitStatus) => {
            console.warn("downloads watch exited (" + exitCode + "), restarting...");
            restartTimer.restart();
        }
    }

    Timer {
        id: restartTimer
        interval: 1000
        repeat: false
        onTriggered: {
            if (!watchProc.running) {
                watchProc.command = root.watchCommand();
                watchProc.running = true;
            }
        }
    }

    // Short-lived command runner: never touches the event stream.
    Process {
        id: cmdProc
        stdout: StdioCollector {
            onStreamFinished: {
                root._pendingDone = true;
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                const err = this.text.trim();
                if (err) {
                    root.lastError = err;
                    console.warn("downloads cmd stderr:", err);
                }
            }
        }
    }

    property bool _pendingDone: false
    on_PendingDoneChanged: {}

    function runCmd(args) {
        if (cmdProc.running) {
            root.lastError = "download command already running";
            return;
        }
        const cmd = [root.daemonBin, "downloads"].concat(args || []);
        if (root.defaultDir && root.defaultDir.length > 0) {
            cmd.push("--dir", root.defaultDir);
        }
        cmd.push("--split", String(root.defaultSplit || 4));
        cmdProc.command = cmd;
        cmdProc.running = true;
    }

    function applySnapshot(d) {
        if (!d) return;
        const prev = root._prevStatus;
        const next = {};

        const collect = list => {
            if (!list || !Array.isArray(list)) return;
            for (let i = 0; i < list.length; i++) {
                const t = list[i];
                if (t && t.gid) next[t.gid] = t;
            }
        };
        collect(d.active);
        collect(d.waiting);
        collect(d.stopped);

        // Edge detect BEFORE overwriting state.
        const now = Date.now();
        for (const gid in next) {
            const cur = next[gid];
            const was = prev[gid];
            if (was && was.status !== cur.status) {
                if (cur.status === "complete" || cur.status === "Complete") {
                    root.fireOnce("finished", gid, cur.name || gid, now);
                } else if (cur.status === "error" || cur.status === "Error") {
                    root.fireOnce("failed", gid, cur.name || gid, now);
                }
            } else if (!was && (cur.status === "complete" || cur.status === "Complete") && root._seenBoot) {
                // A result that appears out of nowhere after boot = just finished.
                root.fireOnce("finished", gid, cur.name || gid, now);
            }
        }

        if (d.active !== undefined && Array.isArray(d.active)) root.activeTasks = d.active;
        if (d.waiting !== undefined && Array.isArray(d.waiting)) root.waitingTasks = d.waiting;
        if (d.stopped !== undefined && Array.isArray(d.stopped)) root.stoppedTasks = d.stopped;
        if (d.total) {
            const t = d.total;
            if (t.progress !== undefined) root.totalProgress = Number(t.progress) || 0.0;
            if (t.completed_length !== undefined) root.totalCompletedBytes = Number(t.completed_length) || 0;
            if (t.total_length !== undefined) root.totalBytes = Number(t.total_length) || 0;
            if (t.download_speed !== undefined) root.totalSpeed = Number(t.download_speed) || 0;
            if (t.active_count !== undefined) root.activeCount = Number(t.active_count) || 0;
            if (t.indeterminate !== undefined) root.indeterminate = Boolean(t.indeterminate);
        }
        root._prevStatus = next;
        root._seenBoot = true;
        root.ariaAvailable = true;
        root.snapshotChanged();
    }

    property bool _seenBoot: false

    function fireOnce(kind, gid, name, now) {
        const last = root._lastToastAt[gid] || 0;
        if (now - last < 10000) return;
        const next = Object.assign({}, root._lastToastAt);
        next[gid] = now;
        root._lastToastAt = next;
        if (kind === "finished") root.downloadFinished(gid, name);
        else root.downloadFailed(gid, name);
    }

    // --- D5 actions (AriaNg verb mapping) ---
    function addUrls(urlText, opts) {
        if (!urlText || !urlText.trim()) {
            root.lastError = "no URLs provided";
            return;
        }
        const args = ["add"];
        const o = opts || {};
        if (o.dir) args.push("--dir", o.dir);
        if (o.split) args.push("--split", String(o.split));
        // Pass the raw text as ONE argv-safe positional via stdin-safe join:
        // newlines preserved so the daemon fans out one task per line.
        runCmdWithInput(args, urlText);
    }

    function runCmdWithInput(args, input) {
        // QML Process has no stdin writer: encode newlines as a sentinel the
        // daemon splits on. The daemon joins positionals with "\n" already,
        // so multi-URL works by passing each line as its own argv entry.
        if (cmdProc.running) {
            root.lastError = "download command already running";
            return;
        }
        const lines = String(input).split("\n").map(s => s.trim()).filter(s => s.length > 0);
        if (lines.length === 0) {
            root.lastError = "no URLs provided";
            return;
        }
        const cmd = [root.daemonBin, "downloads"].concat(args || []).concat(lines);
        if (root.defaultDir && root.defaultDir.length > 0 && args.indexOf("--dir") === -1) {
            cmd.push("--dir", root.defaultDir);
        }
        if (args.indexOf("--split") === -1) {
            cmd.push("--split", String(root.defaultSplit || 4));
        }
        cmdProc.command = cmd;
        cmdProc.running = true;
    }

    function pause(gid) { if (gid) runCmd(["pause", gid]); }
    function resume(gid) { if (gid) runCmd(["resume", gid]); }
    function cancel(gid, deletePartial) {
        if (!gid) return;
        runCmd([deletePartial ? "cancel-delete" : "cancel", gid]);
    }
    function removeResult(gid) { if (gid) runCmd(["remove", gid]); }
    function retry(gid) { if (gid) runCmd(["retry", gid]); }
    function purge() { runCmd(["purge"]); }

    // Aggregate helpers for the border HUD (D10–D15).
    function formatBytes(bytes) {
        if (!bytes || bytes <= 0) return "0 B";
        const units = ["B", "KiB", "MiB", "GiB", "TiB"];
        const i = Math.floor(Math.log(bytes) / Math.log(1024));
        const p = Math.min(Math.max(0, i), units.length - 1);
        return (bytes / Math.pow(1024, p)).toFixed(1) + " " + units[p];
    }

    function formatSpeed(bytesPerSec) {
        if (!bytesPerSec || bytesPerSec <= 0) return "stalled";
        return formatBytes(bytesPerSec) + "/s";
    }

    function formatEta() {
        if (!root.totalSpeed || root.totalSpeed <= 0) return "--";
        const remain = Math.max(0, root.totalBytes - root.totalCompletedBytes);
        if (remain <= 0) return "0s";
        const s = Math.floor(remain / root.totalSpeed);
        if (s < 60) return s + "s";
        if (s < 3600) return Math.floor(s / 60) + "m";
        return Math.floor(s / 3600) + "h " + Math.floor((s % 3600) / 60) + "m";
    }

    readonly property string hudText: {
        if (root.activeCount <= 0) return "";
        const pct = Math.round(root.totalProgress * 100);
        return "↓ " + root.activeCount + " · " + pct + "% · " + root.formatSpeed(root.totalSpeed) + " · " + root.formatEta();
    }
}
