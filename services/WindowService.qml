pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../components"

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

    property bool hasMaximizedWindow: false
    readonly property bool hasActiveMaximized: {
        if (root.hasMaximizedWindow) return true;
        for (let i = 0; i < root.windows.length; i++) {
            const w = root.windows[i];
            if (w && (w.isMaximized || w.isFullScreen || w.maximized || w.fullScreen)) {
                return true;
            }
        }
        return false;
    }

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

    // Dedicated process for calendar launches: sharing activateProc meant a
    // busy activation silently dropped the calendar open request.
    Process {
        id: calendarProc
    }

    /// Open the system's default calendar application for `isoDate`
    /// (`YYYY-MM-DD`). Resolution is data-driven via the XDG MIME database
    /// (`text/calendar`) in the daemon - no application name is hardcoded.
    /// With no date, the calendar simply opens to its own current view.
    function openCalendar(isoDate) {
        var cmd = [root.daemonBin, "calendar", "open"];
        if (isoDate !== undefined && isoDate !== null && ("" + isoDate).length > 0) {
            cmd.push("" + isoDate);
        }
        calendarProc.command = cmd;
        calendarProc.running = true;
    }

    Process {
        id: trayActivateProc
    }

    function activateTray(service, path, x, y) {
        if (!service || !path) return;
        trayActivateProc.running = false;
        let cmd = [root.daemonBin, "tray", "activate", service, path];
        if (x !== undefined && y !== undefined) {
            cmd.push(Math.round(x).toString(), Math.round(y).toString());
        }
        trayActivateProc.command = cmd;
        trayActivateProc.running = true;
    }

    function contextMenuTray(service, path, x, y) {
        if (!service || !path) return;
        trayActivateProc.running = false;
        let cmd = [root.daemonBin, "tray", "context-menu", service, path];
        if (x !== undefined && y !== undefined) {
            cmd.push(Math.round(x).toString(), Math.round(y).toString());
        }
        trayActivateProc.command = cmd;
        trayActivateProc.running = true;
    }

    function updateWinePlaybackStatus(isPlaying) {
        // Its own Process: sharing one with the activation calls meant a busy
        // instance silently dropped the update, and the bridge kept advertising
        // "Playing" after the music was paused.
        if (winePlaybackProc.running) {
            winePlaybackProc.running = false;
        }
        winePlaybackProc.command = ["qdbus6", "org.astralplasma.WindowWatcher", "/Watcher", "org.astralplasma.WindowWatcher.UpdateWinePlaybackStatus", isPlaying ? "true" : "false"];
        winePlaybackProc.running = true;
    }

    Process {
        id: winePlaybackProc
    }

    property var _trayMenuCallback: null
    property int _trayMenuReqId: 0
    property string _trayMenuReqService: ""

    Process {
        id: trayMenuProc
        stdout: StdioCollector {
            onStreamFinished: {
                const cb = root._trayMenuCallback;
                const expectedReqId = root._trayMenuReqId;
                const expectedService = root._trayMenuReqService;
                // Invalidate callback immediately so this stream is consumed once only
                root._trayMenuCallback = null;

                if (cb) {
                    try {
                        const raw = this.text.trim();
                        if (!raw) {
                            cb([], expectedReqId);
                            return;
                        }
                        const parsed = JSON.parse(raw);
                        let items = [];
                        let respService = "";
                        if (Array.isArray(parsed)) {
                            items = parsed;
                        } else if (parsed && Array.isArray(parsed.items)) {
                            items = parsed.items;
                            respService = parsed.service || "";
                        }
                        // Discard if response is stamped with a different service
                        if (respService && expectedService && respService !== expectedService) {
                            console.warn("Tray menu service mismatch: expected", expectedService, "got", respService);
                            return;
                        }
                        cb(items, expectedReqId);
                    } catch (e) {
                        console.warn("fetchTrayMenu error:", e, this.text);
                        cb([], expectedReqId);
                    }
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (this.text.trim()) console.warn("[WindowService] trayMenuProc stderr:", this.text.trim());
            }
        }
    }

    Process {
        id: trayClickProc
        onExited: (exitCode, exitStatus) => {
            refreshTrayProc.running = false;
            refreshTrayProc.command = ["qdbus6", "org.astralplasma.WindowWatcher", "/Watcher", "org.astralplasma.WindowWatcher.RefreshTray"];
            refreshTrayProc.running = true;
        }
    }

    Process {
        id: refreshTrayProc
    }

    function fetchTrayMenu(service, menuPath, callback) {
        if (!service || !menuPath) {
            if (callback) callback([]);
            return;
        }

        // 1. Immediately invalidate any pending callback BEFORE terminating the old process
        root._trayMenuCallback = null;
        if (trayMenuProc.running) {
            trayMenuProc.running = false;
        }

        // 2. Increment request ID token and track target service
        const currentReqId = ++root._trayMenuReqId;
        root._trayMenuReqService = service;

        // 3. Register callback guarded by request ID
        root._trayMenuCallback = (items, respReqId) => {
            if (respReqId === undefined || respReqId === root._trayMenuReqId) {
                if (callback) callback(items);
            }
        };

        trayMenuProc.command = [root.daemonBin, "tray", "menu", service, menuPath];
        trayMenuProc.running = true;
    }

    property var activeTrayItem: null
    property var activeTrayMenuItems: []
    property bool activeTrayLoading: false

    function loadTrayMenu(item) {
        if (!item) {
            root.activeTrayItem = null;
            root.activeTrayMenuItems = [];
            root.activeTrayLoading = false;
            return;
        }

        const isDifferentItem = !root.activeTrayItem 
            || root.activeTrayItem.service !== item.service 
            || root.activeTrayItem.menuPath !== item.menuPath;

        if (isDifferentItem) {
            // CRITICAL: Reset items and set loading state BEFORE setting activeTrayItem,
            // ensuring any synchronous onActiveTrayItemChanged listeners see clean empty items
            root.activeTrayMenuItems = [];
            root.activeTrayLoading = true;
            root.activeTrayItem = item;
        }

        if (item.menuPath) {
            root.fetchTrayMenu(item.service, item.menuPath, (items) => {
                if (root.activeTrayItem && root.activeTrayItem.service === item.service) {
                    root.activeTrayMenuItems = items;
                    root.activeTrayLoading = false;
                }
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
        property string requestedWinKey: ""

        stdout: StdioCollector {
            onStreamFinished: {
                const lines = this.text.trim().split("\n");
                const outPath = lines.length > 0 ? lines[lines.length - 1].trim() : "";
                if (outPath.startsWith("/")) {
                    const fileUrl = "file://" + outPath;
                    const reqKey = previewCaptureProc.requestedWinKey;
                    if (reqKey) {
                        root._previewCache[reqKey] = fileUrl;
                    }
                    if (root.activePreviewApp && root.activePreviewApp.id && root.activePreviewApp.id.toString() === reqKey) {
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
            previewCaptureProc.requestedWinKey = "";
            return;
        }

        const winKey = app.id.toString();
        previewCaptureProc.requestedWinKey = winKey;
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
        previewCaptureProc.requestedWinKey = winKey;
        previewCaptureProc.command = [root.daemonBin, "preview", winKey, "320"];
        previewCaptureProc.running = true;
    }

    // ---- Active-apps overview thumbnails ---------------------------------
    // While the overview is open, PreviewCycle rotates ONE capture at a time
    // across every window through a single Process, so two KWin
    // CaptureWindow calls never race. Each capture alternates that window's
    // two slot files, so the stored URL changes on every refresh and
    // LiveWindowThumbnail can swap buffers without a blank frame. The map is
    // reassigned (not mutated) so delegate bindings re-evaluate.
    property var overviewThumbnails: ({})
    property bool overviewActive: false
    readonly property int overviewThumbWidth: 480

    PreviewCycle {
        id: overviewCycle
        interval: 120
        runner: key => {
            overviewCaptureProc.requestedWinKey = key;
            overviewCaptureProc.command = [root.daemonBin, "preview", key, "" + root.overviewThumbWidth];
            overviewCaptureProc.running = true;
        }
    }

    Process {
        id: overviewCaptureProc
        property string requestedWinKey: ""

        stdout: StdioCollector {
            onStreamFinished: {
                const lines = this.text.trim().split("\n");
                const outPath = lines.length > 0 ? lines[lines.length - 1].trim() : "";
                const key = overviewCaptureProc.requestedWinKey;
                if (outPath.startsWith("/") && key) {
                    root._storeOverviewThumbnail(key, "file://" + outPath);
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                const err = this.text.trim();
                if (err) console.warn("Overview preview error:", err);
            }
        }
        // A finished capture advances the rotation; after stop() the advance
        // hits the inactive cycle and is ignored.
        onExited: overviewCycle.advance()
    }

    function _storeOverviewThumbnail(key, url) {
        const next = Object.assign({}, root.overviewThumbnails);
        next[key] = url;
        root.overviewThumbnails = next;
    }

    function _overviewKeys() {
        const wins = root.windows || [];
        const seen = {};
        const keys = [];
        for (let i = 0; i < wins.length; i++) {
            const w = wins[i];
            if (!w || w.id === undefined || w.id === null) continue;
            const k = String(w.id);
            if (seen[k]) continue;
            seen[k] = true;
            keys.push(k);
        }
        return keys;
    }

    /// Start (or re-target) the overview rotation for every current window.
    function startOverviewThumbnails() {
        root.overviewActive = true;
        overviewCycle.items = root._overviewKeys();
        if (!overviewCycle.active) overviewCycle.start();
    }

    /// Adopt window-list changes while open without restarting the rotation:
    /// PreviewCycle re-reads `items` at the next wrap.
    function refreshOverviewThumbnails() {
        overviewCycle.items = root._overviewKeys();
    }

    function stopOverviewThumbnails() {
        root.overviewActive = false;
        overviewCycle.stop();
        // An in-flight capture is left to finish (~one frame). Killing it
        // would emit a late onExited whose advance() could race a fast reopen
        // into a double-advance (a skipped window in the new rotation).
    }

    onWindowsChanged: {
        if (root.overviewActive) root.refreshOverviewThumbnails();
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
                    if (data.hasMaximizedWindow !== undefined) root.hasMaximizedWindow = Boolean(data.hasMaximizedWindow);
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
