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

    readonly property string serviceDir: Qt.resolvedUrl(".").toString().replace("file://", "").replace(/\/$/, "")

    // Helper process to activate a window or tray item
    Process {
        id: activateProc
    }

    function activateWindow(winId) {
        if (!winId) return;
        activateProc.command = [root.serviceDir + "/activate_window.py", winId];
        activateProc.running = true;
        refreshTimer.restart();
    }

    function closeWindow(winId) {
        if (!winId) return;
        activateProc.command = [root.serviceDir + "/close_window.py", winId];
        activateProc.running = true;
        refreshTimer.restart();
    }

    function launchApp(target) {
        if (!target) return;
        activateProc.command = [root.serviceDir + "/launch_app.py", target];
        activateProc.running = true;
        refreshTimer.restart();
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

    function refresh() {
        if (!queryWindows.running) {
            queryWindows.running = true;
        }
    }

    Timer {
        id: refreshTimer
        interval: 150
        repeat: false
        onTriggered: root.refresh()
    }

    Process {
        id: queryWindows
        command: [root.serviceDir + "/window_watcher.py"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const raw = this.text.trim();
                    if (!raw) return;
                    const lines = raw.split("\n");
                    let data = null;
                    for (let i = lines.length - 1; i >= 0; i--) {
                        const line = lines[i].trim();
                        if (line.startsWith("{") && line.endsWith("}")) {
                            try {
                                data = JSON.parse(line);
                                break;
                            } catch (err) {}
                        }
                    }
                    if (!data) {
                        try { data = JSON.parse(raw); } catch (err) {}
                    }
                    if (!data) return;
                    if (data.windows) root.windows = data.windows;
                    if (data.tray) root.tray = data.tray;
                    if (data.activeTitle) root.activeTitle = data.activeTitle;
                    if (data.activeMaterialIcon) root.activeMaterialIcon = data.activeMaterialIcon;
                    if (data.activeIconName !== undefined) root.activeIconName = data.activeIconName;
                    console.log("WindowService updated: " + root.windows.length + " windows, " + root.tray.length + " tray items");
                } catch (e) {
                    console.warn("WindowService parse error:", e);
                }
            }
        }
    }

    Timer {
        id: queryTimer
        interval: 750
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            root.refresh();
        }
    }
}
