pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

Singleton {
    id: root

    property string currentSummary: ""
    property string currentBody: ""
    property string currentAppName: ""
    property string currentIcon: "info"
    property string currentTime: "now"
    property bool hasNotification: false
    property var currentActions: []

    readonly property string serviceDir: Qt.resolvedUrl(".").toString().replace("file://", "").replace(/\/$/, "")
    readonly property string daemonBin: root.serviceDir + "/../bin/astral-plasma"

    signal notificationReceived(string summary, string body, string icon, string appName)

    function show(summary: string, body: string, icon: string, appName: string) {
        currentSummary = summary || "Notification";
        currentBody = body || "";
        currentIcon = icon || "info";
        currentAppName = appName || "System";
        currentTime = "now";
        hasNotification = true;
        notificationReceived(currentSummary, currentBody, currentIcon, currentAppName);
    }

    function dismiss() {
        hasNotification = false;
    }

    // Direct Quickshell Notification Server
    NotificationServer {
        id: server
        keepOnReload: false
        actionsSupported: true
        bodyHyperlinksSupported: true
        bodyImagesSupported: true
        bodyMarkupSupported: true
        imageSupported: true
        persistenceSupported: true

        onNotification: notif => {
            notif.tracked = true;
            root.show(notif.summary, notif.body, notif.appIcon || "info", notif.appName);
        }
    }

    // Background DBus Monitor process (captures notify-send / KDE system notifications seamlessly)
    Process {
        id: notifProc
        command: [root.daemonBin, "notifs"]
        running: true
        stdout: SplitParser {
            onRead: data => {
                try {
                    const line = data.trim();
                    if (!line || !line.startsWith("{")) return;
                    const parsed = JSON.parse(line);
                    root.show(parsed.summary, parsed.body, parsed.icon, parsed.app);
                } catch (e) {
                    console.warn("NotificationService parse error:", e);
                }
            }
        }
        onExited: restartTimer.start()
    }

    Timer {
        id: restartTimer
        interval: 2000
        repeat: false
        onTriggered: notifProc.running = true
    }
}
