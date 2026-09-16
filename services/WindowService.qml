pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property var windows: []
    property var tray: []
    property string activeTitle: "Desktop"
    property string activeMaterialIcon: "desktop_windows"
    property string activeIconName: ""
    property string activeAppId: ""
    property string activeId: ""

    property alias title: root.activeTitle
    property alias appId: root.activeIconName
    property alias materialIcon: root.activeMaterialIcon

    readonly property var activeWindow: {
        for (let i = 0; i < root.windows.length; i++) {
            if (root.windows[i].isActive) return root.windows[i];
        }
        return null;
    }

    readonly property string serviceDir: Qt.resolvedUrl(".").toString().replace("file://", "").replace(/\/$/, "")
    readonly property string daemonBin: root.serviceDir + "/../bin/astral-plasma"

    // Helper process to activate a window or tray item
    Process {
        id: activateProc
    }

    function activateWindow(winId) {
        if (!winId) return;
        activateProc.command = [root.daemonBin, "activate", winId];
        activateProc.running = true;
    }

    function closeWindow(winId) {
        if (!winId) return;
        activateProc.command = [root.daemonBin, "close", winId];
        activateProc.running = true;
    }

    function launchApp(target) {
        if (!target) return;
        activateProc.command = [root.daemonBin, "launch", target];
        activateProc.running = true;
    }

    function activateTray(service, path) {
        if (!service || !path) return;
        activateProc.command = ["qdbus6", service, path, "org.kde.StatusNotifierItem.Activate", "0", "0"];
        activateProc.running = true;
    }

    function contextMenuTray(service, path) {
        if (!service || !path) return;
        activateProc.command = ["qdbus6", service, path, "org.kde.StatusNotifierItem.ContextMenu", "0", "0"];
        activateProc.running = true;
    }

    property var _trayMenuCallback: null

    Process {
        id: trayMenuProc
        stdout: StdioCollector {
            onStreamFinished: {
                if (root._trayMenuCallback) {
                    try {
                        const items = JSON.parse(this.text.trim());
                        root._trayMenuCallback(Array.isArray(items) ? items : []);
                    } catch (e) {
                        console.warn("fetchTrayMenu error:", e, this.text);
                        root._trayMenuCallback([]);
                    }
                    root._trayMenuCallback = null;
                }
            }
        }
    }

    Process {
        id: trayClickProc
    }

    function fetchTrayMenu(service, menuPath, callback) {
        if (!service || !menuPath) {
            if (callback) callback([]);
            return;
        }
        root._trayMenuCallback = callback;
        trayMenuProc.running = false;
        trayMenuProc.command = [root.daemonBin, "tray", "menu", service, menuPath];
        trayMenuProc.running = true;
    }

    property var activeTrayItem: null
    property var activeTrayMenuItems: []
    property bool activeTrayLoading: false
    property var _menuCache: ({})

    function loadTrayMenu(item) {
        if (!item) return;
        root.activeTrayItem = item;
        const cacheKey = (item.service || "") + ":" + (item.menuPath || "");
        if (root._menuCache[cacheKey]) {
            root.activeTrayMenuItems = root._menuCache[cacheKey];
            root.activeTrayLoading = false;
        } else {
            root.activeTrayLoading = true;
            root.activeTrayMenuItems = [];
        }

        if (item.menuPath) {
            root.fetchTrayMenu(item.service, item.menuPath, (items) => {
                if (root.activeTrayItem && root.activeTrayItem.service === item.service) {
                    root.activeTrayLoading = false;
                    root.activeTrayMenuItems = items;
                }
                root._menuCache[cacheKey] = items;
            });
        } else {
            root.activeTrayLoading = false;
            root.activeTrayMenuItems = [];
        }
    }

    property var activePreviewApp: null
    property string activePreviewThumbnail: ""
    property bool activePreviewLoading: false
    property var _previewCache: ({})

    Process {
        id: previewCaptureProc
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = this.text.trim().split("\n");
                const outPath = lines.length > 0 ? lines[lines.length - 1].trim() : "";
                if (outPath.startsWith("/")) {
                    const fileUrl = "file://" + outPath;
                    if (root.activePreviewApp && root.activePreviewApp.id) {
                        root._previewCache[root.activePreviewApp.id.toString()] = fileUrl;
                        root.activePreviewThumbnail = fileUrl;
                    }
                }
                root.activePreviewLoading = false;
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                const err = this.text.trim();
                if (err) console.warn("Window preview error:", err);
            }
        }
        onExited: (exitCode, exitStatus) => {
            root.activePreviewLoading = false;
        }
    }

    function loadAppPreview(app) {
        root.activePreviewApp = app;
        const isRunning = app ? (Boolean(app.isRunning) || Boolean(app.id)) : false;
        if (!app || !isRunning || !app.id) {
            root.activePreviewThumbnail = "";
            root.activePreviewLoading = false;
            previewCaptureProc.running = false;
            return;
        }

        const winKey = app.id.toString();
        const cached = root._previewCache[winKey];
        if (cached) {
            root.activePreviewThumbnail = cached;
        } else {
            root.activePreviewThumbnail = "";
        }

        root.activePreviewLoading = true;
        previewCaptureProc.running = false;
        previewCaptureProc.command = [root.daemonBin, "preview", winKey, "320"];
        previewCaptureProc.running = true;
    }

    function refreshAppPreview(app) {
        if (!app || !app.id || previewCaptureProc.running) return;
        const winKey = app.id.toString();
        previewCaptureProc.command = [root.daemonBin, "preview", winKey, "320"];
        previewCaptureProc.running = true;
    }

    function triggerTrayMenuItem(service, menuPath, itemId) {
        if (!service || !menuPath || itemId === undefined) return;
        trayClickProc.running = false;
        trayClickProc.command = [root.daemonBin, "tray", "click", service, menuPath, itemId.toString()];
        trayClickProc.running = true;
    }

    function refresh() {
        if (!watcherDaemon.running) {
            watcherDaemon.running = true;
        }
    }

    // Real-Time Event-Driven Window Watcher Daemon
    Process {
        id: watcherDaemon
        command: [root.daemonBin, "watch"]
        running: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (raw) => {
                try {
                    const line = raw.trim();
                    if (!line || !line.startsWith("{")) return;
                    const data = JSON.parse(line);
                    if (!data) return;

                    if (data.activeTitle !== undefined) root.activeTitle = data.activeTitle;
                    if (data.activeMaterialIcon !== undefined) root.activeMaterialIcon = data.activeMaterialIcon;
                    if (data.activeIconName !== undefined) root.activeIconName = data.activeIconName;
                    if (data.activeAppId !== undefined) root.activeAppId = data.activeAppId;
                    if (data.activeId !== undefined) root.activeId = data.activeId;
                    if (data.windows) root.windows = data.windows;
                    if (data.tray) root.tray = data.tray;
                } catch (e) {
                    console.warn("WindowService parse error:", e);
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (this.text.trim()) console.warn("WindowWatcher daemon error:", this.text);
            }
        }
        onExited: (exitCode, exitStatus) => {
            console.warn("WindowWatcher daemon exited (" + exitCode + "), restarting...");
            restartTimer.restart();
        }
    }

    Timer {
        id: restartTimer
        interval: 1000
        repeat: false
        onTriggered: {
            if (!watcherDaemon.running) {
                watcherDaemon.running = true;
            }
        }
    }
}
