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
    readonly property string daemonBin: root.serviceDir + "/../bin/caelestia-daemon"

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
                    if (data.windows) root.windows = data.windows;
                    if (data.tray) root.tray = data.tray;
                } catch (e) {
                    console.warn("WindowService parse error:", e);
                }
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
