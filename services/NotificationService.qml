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
    property string currentImage: ""
    property string currentTime: "now"
    property bool hasNotification: false
    property var currentActions: []

    readonly property string serviceDir: Qt.resolvedUrl(".").toString().replace("file://", "").replace(/\/$/, "")
    readonly property string daemonBin: root.serviceDir + "/../bin/astral-plasma"

    signal notificationReceived(string summary, string body, string icon, string appName, string image)

    function show(summary: string, body: string, icon: string, appName: string, image: string) {
        currentSummary = summary || "Notification";
        currentBody = body || "";
        currentAppName = appName || "System";

        let appLower = (appName || "").toLowerCase();
        let isMedia = appLower.includes("strawberry") || 
                      appLower.includes("elisa") || 
                      appLower.includes("cloudmusic") || 
                      appLower.includes("netease") || 
                      appLower.includes("music") || 
                      appLower.includes("player") || 
                      appLower.includes("spotify") ||
                      (typeof MprisMedia !== "undefined" && MprisMedia.identity && appLower.includes(MprisMedia.identity.toLowerCase()));

        currentIcon = icon && icon !== "info" ? icon : (isMedia ? "music_note" : (icon || "info"));

        let img = image || "";
        if (!img && typeof MprisMedia !== "undefined" && MprisMedia.artUrl && MprisMedia.artUrl.length > 0) {
            if (isMedia || 
                (MprisMedia.title && summary && summary.toLowerCase().includes(MprisMedia.title.toLowerCase())) ||
                (MprisMedia.artist && body && body.toLowerCase().includes(MprisMedia.artist.toLowerCase()))) {
                img = MprisMedia.artUrl;
            }
        }

        currentImage = img;
        currentTime = "now";
        hasNotification = true;
        notificationReceived(currentSummary, currentBody, currentIcon, currentAppName, currentImage);
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
            let img = notif.image || "";
            if (!img && notif.appIcon && (notif.appIcon.indexOf("/") !== -1 || notif.appIcon.indexOf("file:") !== -1)) {
                img = notif.appIcon;
            }
            root.show(notif.summary, notif.body, notif.appIcon || "info", notif.appName, img);
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
                    root.show(parsed.summary, parsed.body, parsed.icon, parsed.app, parsed.image || "");
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
