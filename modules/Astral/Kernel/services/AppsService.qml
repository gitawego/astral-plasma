pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

// ============================================================================
// AppsService — the installed-app list, as the daemon owns it
// ============================================================================
// The Apps page renders state and offers actions; it does not implement install
// policy. Everything here is the daemon's own vocabulary:
//
//   `astral-plasma app list --json`       -> [{ id, name, version, kernelApi,
//                                             preinstalled, enabled, pinned,
//                                             compatible, reason }]
//   `app enable|disable <id>`             -> registry, written atomically
//   `app remove <id> [--purge]`           -> payload + record
//
// One short-lived process per action, then a refresh: the registry is the single
// source of truth, so the page never patches its own list optimistically.
Singleton {
    id: root

    /// `[{ id, name, version, kernelApi, preinstalled, enabled, pinned, compatible, reason }]`
    property var apps: []
    property bool loading: false
    /// Last action failure, as the daemon worded it.
    property string lastError: ""

    readonly property int installedCount: apps.length
    readonly property int enabledCount: {
        let count = 0;
        for (let index = 0; index < apps.length; index++) {
            if (apps[index].enabled) count++;
        }
        return count;
    }

    /// One authority for the layout (spec C.12).
    readonly property string daemonBin: Paths.daemonBin

    function refresh() {
        root.loading = true;
        listProc.running = false;
        listProc.running = true;
    }

    function setEnabled(appId, enabled) {
        root.lastError = "";
        actionProc.command = [root.daemonBin, "app", enabled ? "enable" : "disable", String(appId)];
        actionProc.running = false;
        actionProc.running = true;
    }

    function remove(appId, purge) {
        root.lastError = "";
        const args = [root.daemonBin, "app", "remove", String(appId)];
        if (purge) args.push("--purge");
        actionProc.command = args;
        actionProc.running = false;
        actionProc.running = true;
    }

    function appById(appId) {
        for (let index = 0; index < apps.length; index++) {
            if (apps[index].id === appId) return apps[index];
        }
        return null;
    }

    Process {
        id: listProc
        command: [root.daemonBin, "app", "list", "--json"]

        stdout: StdioCollector {
            onStreamFinished: {
                root.loading = false;
                const text = this.text.trim();
                if (text.length === 0) return;
                try {
                    const parsed = JSON.parse(text);
                    root.apps = Array.isArray(parsed) ? parsed : [];
                } catch (error) {
                    root.lastError = "could not read the app list: " + error;
                }
            }
        }
    }

    Process {
        id: actionProc

        stdout: StdioCollector {
            onStreamFinished: root.refresh()
        }
        stderr: StdioCollector {
            onStreamFinished: {
                const text = this.text.trim();
                if (text.length > 0) {
                    root.lastError = text.split("\n").pop();
                }
            }
        }
    }
}
