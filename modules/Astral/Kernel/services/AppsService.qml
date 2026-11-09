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
//   `app inspect <file>`                  -> what installing a file would grant
//   `app install <file> --accept-permissions` -> staging, verify, record
//   `app enable|disable <id>`             -> registry, written atomically
//   `app remove <id> [--purge]`           -> payload + record + tombstone
//   `app removed --json`                  -> bundled apps the user removed
//   `app restore <id>`                    -> clear the tombstone, re-add the record
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
        // A refresh starts from a known state: an error from a previous action must not sit
        // under a list that has since updated.
        root.lastError = "";
        root.loading = true;
        listProc.running = false;
        listProc.running = true;
        removedProc.running = false;
        removedProc.running = true;
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

    /// The consent card's data: what installing `path` would mean, read from the artifact.
    /// Nothing is installed and nothing is trusted until `install` is called.
    function inspect(path) {
        root.lastError = "";
        root.pendingInstall = null;
        inspectProc.pendingPath = String(path);
        inspectProc.command = [root.daemonBin, "app", "inspect", String(path)];
        inspectProc.running = false;
        inspectProc.running = true;
    }

    /// Install a file the user has just consented to.
    function install(path) {
        root.lastError = "";
        actionProc.command = [root.daemonBin, "app", "install", String(path), "--accept-permissions"];
        actionProc.running = false;
        actionProc.running = true;
        root.pendingInstall = null;
    }

    /// What `inspect` found, or null while nothing has been inspected.
    property var pendingInstall: null

    /// Bundled apps the user removed: removable, and restorable from here.
    property var removed: []

    function restore(appId) {
        root.lastError = "";
        actionProc.command = [root.daemonBin, "app", "restore", String(appId)];
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
        id: removedProc
        command: [root.daemonBin, "app", "removed", "--json"]

        stdout: StdioCollector {
            onStreamFinished: {
                const text = this.text.trim();
                if (text.length === 0) return;
                try {
                    const parsed = JSON.parse(text);
                    root.removed = Array.isArray(parsed) ? parsed : [];
                } catch (error) {
                    root.removed = [];
                }
            }
        }
    }

    Process {
        id: inspectProc
        property string pendingPath: ""

        stdout: StdioCollector {
            onStreamFinished: {
                const text = this.text.trim();
                if (text.length === 0) return;
                try {
                    const found = JSON.parse(text);
                    found.path = inspectProc.pendingPath;
                    root.pendingInstall = found;
                } catch (error) {
                    root.lastError = "could not read the artifact: " + error;
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                const text = this.text.trim();
                if (text.length > 0) root.lastError = text.split("\n").pop();
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
