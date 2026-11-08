pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property var history: []
    property string currentText: ""
    property bool isBusy: false

    readonly property string serviceDir: Qt.resolvedUrl(".").toString().replace("file://", "").replace(/\/$/, "")
    readonly property string daemonBin: (typeof Config !== "undefined" && Config.daemonBin) ? Config.daemonBin : (root.serviceDir + "/../bin/astral-plasma")

    function isBinaryJunk(str) {
        if (typeof str !== "string") return false;
        return str.startsWith("\x89PNG") || str.startsWith("PNG\r\n") || str.indexOf("\x00") !== -1;
    }

    function applyItem(item) {
        if (!item || !item.type || item.type === "empty") return;

        let cleanList = root.history.filter(it => {
            if (typeof it === "string") return !root.isBinaryJunk(it);
            return true;
        });

        if (item.type === "image") {
            // Check if top item is already this image
            if (cleanList.length > 0) {
                const top = cleanList[0];
                if (top && top.type === "image" && (top.path === item.path || (top.bytes_len && top.bytes_len === item.bytes_len))) {
                    root.currentText = item.text || "[Image]";
                    return;
                }
            }
            // Remove duplicates
            cleanList = cleanList.filter(it => !(it && it.type === "image" && it.path === item.path));
            cleanList.unshift(item);
            root.history = cleanList.slice(0, 50);
            root.currentText = item.text || "[Image]";
        } else if (item.type === "text") {
            const txt = (item.text || "").trim();
            if (!txt || root.isBinaryJunk(txt)) return;

            if (cleanList.length > 0) {
                const top = cleanList[0];
                const topTxt = typeof top === "string" ? top : (top && top.text ? top.text : "");
                if (topTxt === txt) {
                    root.currentText = txt;
                    return;
                }
            }
            cleanList = cleanList.filter(it => {
                const itTxt = typeof it === "string" ? it : (it && it.text ? it.text : "");
                return itTxt !== txt;
            });
            cleanList.unshift(txt);
            root.history = cleanList.slice(0, 50);
            root.currentText = txt;
        }
    }

    // Rich Clipboard Process via native Astral Plasma daemon
    Process {
        id: readProc
        command: [root.daemonBin, "clipboard", "read"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.isBusy = false;
                try {
                    const raw = this.text.trim();
                    if (raw && raw.startsWith("{")) {
                        const parsed = JSON.parse(raw);
                        root.applyItem(parsed);
                    }
                } catch(e) {
                    // Fall back to KDE Klipper
                    root.fallbackRead();
                }
            }
        }
        onExited: (code, status) => {
            root.isBusy = false;
        }
    }

    // Fetch history from KDE Klipper DBus for backwards compatibility
    Process {
        id: fetchProc
        command: ["busctl", "--user", "call", "org.kde.klipper", "/klipper", "org.kde.klipper.klipper", "getClipboardHistoryMenu", "--json=pretty"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(this.text.trim());
                    if (parsed && parsed.data && parsed.data.length > 0 && Array.isArray(parsed.data[0])) {
                        const rawItems = parsed.data[0];
                        const cleanList = root.history.slice();
                        for (let i = 0; i < rawItems.length; i++) {
                            const item = rawItems[i];
                            if (typeof item === "string" && item.trim().length > 0 && !root.isBinaryJunk(item)) {
                                if (cleanList.indexOf(item) === -1) {
                                    cleanList.push(item);
                                }
                            }
                        }
                        root.history = cleanList.slice(0, 50);
                    }
                } catch(e) {
                    // Ignored if Klipper is not available
                }
            }
        }
    }

    Process {
        id: setProc
    }

    Process {
        id: clearProc
    }

    function fallbackRead() {
        if (!fetchProc.running) {
            fetchProc.running = true;
        }
    }

    function refresh() {
        if (readProc.running) {
            readProc.running = false;
        }
        root.isBusy = true;
        readProc.running = true;
        if (!fetchProc.running) {
            fetchProc.running = true;
        }
    }

    function setClipboard(item) {
        if (!item) return;

        if (typeof item === "object" && item.type === "image") {
            const imgPath = item.path || "";
            if (!imgPath) return;
            if (typeof Quickshell !== "undefined" && typeof Quickshell.execDetached === "function") {
                Quickshell.execDetached([root.daemonBin, "clipboard", "set", imgPath, "--image"]);
            } else {
                if (setProc.running) setProc.running = false;
                setProc.command = [root.daemonBin, "clipboard", "set", imgPath, "--image"];
                setProc.running = true;
            }
            root.applyItem(item);
        } else {
            const text = typeof item === "string" ? item : (item.text || "");
            if (!text || root.isBinaryJunk(text)) return;
            if (typeof Quickshell !== "undefined" && typeof Quickshell.execDetached === "function") {
                Quickshell.execDetached([root.daemonBin, "clipboard", "set", text]);
                Quickshell.execDetached(["qdbus6", "org.kde.klipper", "/klipper", "org.kde.klipper.klipper.setClipboardContents", text]);
            } else {
                if (setProc.running) setProc.running = false;
                setProc.command = [root.daemonBin, "clipboard", "set", text];
                setProc.running = true;
                Quickshell.execDetached(["qdbus6", "org.kde.klipper", "/klipper", "org.kde.klipper.klipper.setClipboardContents", text]);
            }
            root.applyItem({ type: "text", text: text });
        }
    }

    function clearHistory() {
        root.history = [];
        root.currentText = "";
        if (typeof Quickshell !== "undefined" && typeof Quickshell.execDetached === "function") {
            Quickshell.execDetached([root.daemonBin, "clipboard", "clear"]);
            Quickshell.execDetached(["qdbus6", "org.kde.klipper", "/klipper", "org.kde.klipper.klipper.clearClipboardHistory"]);
        } else {
            clearProc.command = [root.daemonBin, "clipboard", "clear"];
            clearProc.running = true;
            Quickshell.execDetached(["qdbus6", "org.kde.klipper", "/klipper", "org.kde.klipper.klipper.clearClipboardHistory"]);
        }
    }

    // Auto-poll every 2 seconds to capture copied items across apps
    Timer {
        id: autoPollTimer
        interval: 2000
        running: true
        repeat: true
        onTriggered: {
            if (!readProc.running) {
                readProc.running = true;
            }
        }
    }

    Component.onCompleted: {
        refresh();
    }
}
