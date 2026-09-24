pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string serviceDir: Qt.resolvedUrl(".").toString().replace("file://", "").replace(/\/$/, "")
    readonly property string daemonBin: root.serviceDir + "/../bin/astral-plasma"

    // Session status
    property string profile: "kde" // "kde" | "hyprland" | "omarchy"
    property string connection: "connected" // "starting" | "connected" | "degraded" | "disconnected"
    property int revision: 1
    property string focusedOutputId: ""
    property bool isStale: (connection === "disconnected" || connection === "degraded")

    // Canonical projections
    property var outputs: []
    property var workspaces: []
    property var windows: []
    property var capabilities: ({})

    // Active window projection (for backwards compatibility & quick access)
    property string activeTitle: ""
    property string activeAppId: ""
    property string activeIconName: ""
    property string activeMaterialIcon: ""
    property bool hasMaximizedWindow: false

    Process {
        id: initSnapshotProc
        command: [root.daemonBin, "session", "snapshot"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const snap = JSON.parse(this.text.trim());
                    root.applySnapshot(snap);
                } catch (e) {}
            }
        }
    }

    function refresh() {
        if (!initSnapshotProc.running) {
            initSnapshotProc.running = true;
        }
    }

    function switchWorkspace(id) {
        if (typeof KWinWorkspaces !== "undefined") {
            KWinWorkspaces.switchTo(id);
        }
    }

    function activateWindow(id) {
        if (typeof WindowService !== "undefined") {
            WindowService.activateWindow(id);
        }
    }

    function closeWindow(id) {
        if (typeof WindowService !== "undefined") {
            WindowService.closeWindow(id);
        }
    }

    function isCapabilityAvailable(name) {
        if (!capabilities || !capabilities[name]) return false;
        return Boolean(capabilities[name].available);
    }

    function getCapabilityReason(name) {
        if (!capabilities || !capabilities[name]) return "not-declared";
        return capabilities[name].reason || "";
    }

    function getCapabilityMode(name) {
        if (!capabilities || !capabilities[name]) return "";
        return capabilities[name].mode || "";
    }

    function applySnapshot(snap) {
        if (!snap) return;
        if (snap.profile !== undefined) root.profile = snap.profile;
        if (snap.connection !== undefined) root.connection = snap.connection;
        if (snap.revision !== undefined) root.revision = snap.revision;
        if (snap.focusedOutputId !== undefined) root.focusedOutputId = snap.focusedOutputId;
        if (snap.outputs !== undefined && Array.isArray(snap.outputs)) root.outputs = snap.outputs;
        if (snap.workspaces !== undefined && Array.isArray(snap.workspaces)) root.workspaces = snap.workspaces;
        if (snap.windows !== undefined && Array.isArray(snap.windows)) {
            root.windows = snap.windows;
            // Update active window projection
            let foundActive = false;
            let foundMax = false;
            for (let i = 0; i < snap.windows.length; i++) {
                const w = snap.windows[i];
                if (w.isMaximized || w.maximized) foundMax = true;
                if (w.isActive || w.active) {
                    root.activeTitle = w.title || "";
                    root.activeAppId = w.appId || "";
                    root.activeIconName = w.iconName || "";
                    root.activeMaterialIcon = w.materialIcon || "";
                    foundActive = true;
                }
            }
            root.hasMaximizedWindow = foundMax;
            if (!foundActive && snap.windows.length === 0) {
                root.activeTitle = "";
                root.activeAppId = "";
                root.activeIconName = "";
                root.activeMaterialIcon = "";
            }
        }
        if (snap.capabilities !== undefined) root.capabilities = snap.capabilities;
    }
}
