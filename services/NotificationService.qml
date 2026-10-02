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
    property var currentNotification: null
    property var currentActions: []
    property var defaultAction: null
    property int timeoutMs: 5000

    readonly property string serviceDir: Qt.resolvedUrl(".").toString().replace("file://", "").replace(/\/$/, "")
    readonly property string daemonBin: root.serviceDir + "/../bin/astral-plasma"

    signal notificationReceived(string summary, string body, string icon, string appName, string image)
    signal actionInvoked(string actionId)

    Process {
        id: deviceProc
    }

    function runDeviceAction(actionCommand, target) {
        let args = [root.daemonBin, "device", actionCommand];
        if (target) args.push(target);
        deviceProc.command = args;
        deviceProc.running = true;
    }

    function isDeviceNotification(summary, body, appName, appIcon) {
        let s = (summary || "").toLowerCase();
        let b = (body || "").toLowerCase();
        let app = (appName || "").toLowerCase();
        let icon = (appIcon || "").toLowerCase();
        return (
            app.includes("device") ||
            icon.includes("drive-removable") ||
            icon.includes("media-removable") ||
            icon.includes("usb") ||
            s.includes("usb device") ||
            s.includes("device plugged") ||
            s.includes("removable")
        );
    }

    function showNotification(notif) {
        if (!notif) return;
        currentNotification = notif;

        let img = notif.image || "";
        if (!img && notif.appIcon && (notif.appIcon.indexOf("/") !== -1 || notif.appIcon.indexOf("file:") !== -1)) {
            img = notif.appIcon;
        }

        let defAct = null;
        let actList = [];
        if (notif.actions && notif.actions.length !== undefined && notif.actions.length > 0) {
            for (let i = 0; i < notif.actions.length; i++) {
                let act = notif.actions[i];
                if (!act) continue;
                if (act.identifier === "default") {
                    defAct = act;
                } else {
                    actList.push(act);
                }
            }
        } else if (isDeviceNotification(notif.summary, notif.body, notif.appName, notif.appIcon)) {
            let openAct = {
                identifier: "device_open",
                text: "Open in File Manager",
                target: notif.body || notif.summary
            };
            let ejectAct = {
                identifier: "device_eject",
                text: "Safely Remove",
                target: notif.body || notif.summary
            };
            defAct = openAct;
            actList.push(openAct);
            actList.push(ejectAct);
        }

        root.defaultAction = defAct;
        root.currentActions = actList;

        if (notif.expireTimeout > 100) {
            root.timeoutMs = Math.round(notif.expireTimeout);
        } else if (notif.expireTimeout > 0) {
            root.timeoutMs = Math.round(notif.expireTimeout * 1000);
        } else {
            root.timeoutMs = 6000;
        }

        root.show(notif.summary, notif.body, notif.appIcon || "info", notif.appName, img);
    }

    function show(summary: string, body: string, icon: string, appName: string, image: string) {
        currentSummary = summary || "Notification";
        currentBody = body || "";
        currentAppName = appName || "System";

        if (isDeviceNotification(summary, body, appName, icon) && root.currentActions.length === 0) {
            let openAct = {
                identifier: "device_open",
                text: "Open in File Manager",
                target: body || summary
            };
            let ejectAct = {
                identifier: "device_eject",
                text: "Safely Remove",
                target: body || summary
            };
            root.defaultAction = openAct;
            root.currentActions = [openAct, ejectAct];
        }

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

    function invokeAction(action) {
        if (!action) return;
        let id = "";
        let target = "";
        if (typeof action === "string") {
            id = action;
        } else if (action) {
            id = action.identifier || "";
            target = action.target || "";
        }

        if (id === "device_open") {
            runDeviceAction("mount-open", target || currentSummary || currentBody);
            if (id) root.actionInvoked(id);
            dismiss();
            return;
        }
        if (id === "device_eject") {
            runDeviceAction("eject", target || currentSummary || currentBody);
            if (id) root.actionInvoked(id);
            dismiss();
            return;
        }

        if (typeof action === "string") {
            if (defaultAction && defaultAction.identifier === action && typeof defaultAction.invoke === "function") {
                try { defaultAction.invoke(); } catch(e) { console.warn("invoke error:", e); }
            } else if (currentActions) {
                for (let i = 0; i < currentActions.length; i++) {
                    let act = currentActions[i];
                    if (act && act.identifier === action && typeof act.invoke === "function") {
                        try { act.invoke(); } catch(e) { console.warn("invoke error:", e); }
                        break;
                    }
                }
            }
        } else if (action && typeof action.invoke === "function") {
            try { action.invoke(); } catch(e) { console.warn("invoke error:", e); }
        }
        if (id) root.actionInvoked(id);
        dismiss();
    }

    function invokeDefaultAction() {
        if (defaultAction) {
            let id = defaultAction.identifier || "default";
            if (id === "device_open") {
                runDeviceAction("mount-open", defaultAction.target || currentSummary || currentBody);
                root.actionInvoked(id);
                dismiss();
                return true;
            }
            if (typeof defaultAction.invoke === "function") {
                try { defaultAction.invoke(); } catch(e) { console.warn("default invoke error:", e); }
                root.actionInvoked(id);
                dismiss();
                return true;
            }
        }
        if (currentActions && currentActions.length > 0) {
            for (let i = 0; i < currentActions.length; i++) {
                let act = currentActions[i];
                if (!act) continue;
                let id = (act.identifier || "").toLowerCase();
                let txt = (act.text || "").toLowerCase();
                if (id === "device_open") {
                    runDeviceAction("mount-open", act.target || currentSummary || currentBody);
                    root.actionInvoked("device_open");
                    dismiss();
                    return true;
                }
                if (id.includes("open") || id.includes("mount") || id.includes("view") ||
                    txt.includes("open") || txt.includes("mount") || txt.includes("view")) {
                    if (typeof act.invoke === "function") {
                        try { act.invoke(); } catch(e) { console.warn("action invoke error:", e); }
                        root.actionInvoked(act.identifier || "open");
                        dismiss();
                        return true;
                    }
                }
            }
            let first = currentActions[0];
            if (first) {
                if (first.identifier === "device_open") {
                    runDeviceAction("mount-open", first.target || currentSummary || currentBody);
                    root.actionInvoked("device_open");
                    dismiss();
                    return true;
                }
                if (typeof first.invoke === "function") {
                    try { first.invoke(); } catch(e) { console.warn("first action invoke error:", e); }
                    root.actionInvoked(first.identifier || "");
                    dismiss();
                    return true;
                }
            }
        }

        // Automatic fallback: if device notification without default action, default click opens USB folder
        if (isDeviceNotification(currentSummary, currentBody, currentAppName, currentIcon)) {
            runDeviceAction("mount-open", currentBody || currentSummary);
            root.actionInvoked("device_open");
            dismiss();
            return true;
        }

        dismiss();
        return false;
    }

    function dismiss() {
        if (currentNotification) {
            try {
                if (typeof currentNotification.dismiss === "function") {
                    currentNotification.dismiss();
                }
            } catch(e) {
                console.warn("Notification dismiss error:", e);
            }
            currentNotification = null;
        }
        currentActions = [];
        defaultAction = null;
        hasNotification = false;
    }

    function expire() {
        if (currentNotification) {
            try {
                if (typeof currentNotification.expire === "function") {
                    currentNotification.expire();
                }
            } catch(e) {
                console.warn("Notification expire error:", e);
            }
            currentNotification = null;
        }
        currentActions = [];
        defaultAction = null;
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
            root.showNotification(notif);
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
                    // Avoid duplicating if native NotificationServer already received this notification
                    if (root.hasNotification && root.currentNotification !== null) {
                        return;
                    }
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
