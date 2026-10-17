pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property var history: []
    property string currentText: ""
    property bool isBusy: false

    // Fetch history from klipper DBus or wl-paste
    Process {
        id: fetchProc
        command: ["busctl", "--user", "call", "org.kde.klipper", "/klipper", "org.kde.klipper.klipper", "getClipboardHistoryMenu", "--json=pretty"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.isBusy = false;
                try {
                    const parsed = JSON.parse(this.text.trim());
                    if (parsed && parsed.data && parsed.data.length > 0 && Array.isArray(parsed.data[0])) {
                        const rawItems = parsed.data[0];
                        const cleanList = [];
                        const seen = {};
                        for (let i = 0; i < rawItems.length; i++) {
                            const item = rawItems[i];
                            if (typeof item === "string" && item.trim().length > 0) {
                                if (!seen[item]) {
                                    seen[item] = true;
                                    cleanList.push(item);
                                }
                            }
                        }
                        root.history = cleanList;
                        if (cleanList.length > 0) {
                            root.currentText = cleanList[0];
                        }
                    }
                } catch(e) {
                    root.fallbackRead();
                }
            }
        }
        onExited: (code, status) => {
            root.isBusy = false;
        }
    }

    Process {
        id: fallbackProc
        command: ["wl-paste", "--no-newline"]
        stdout: StdioCollector {
            onStreamFinished: {
                const txt = this.text;
                if (txt && txt.trim().length > 0) {
                    root.currentText = txt;
                    if (root.history.indexOf(txt) === -1) {
                        root.history = [txt].concat(root.history.slice(0, 24));
                    }
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
        fallbackProc.running = false;
        fallbackProc.running = true;
    }

    function refresh() {
        if (fetchProc.running) return;
        root.isBusy = true;
        fetchProc.running = true;
    }

    function setClipboard(text) {
        if (!text) return;
        root.currentText = text;
        // 1. Send to Klipper DBus
        setProc.command = ["qdbus6", "org.kde.klipper", "/klipper", "org.kde.klipper.klipper.setClipboardContents", text];
        setProc.running = true;
        // 2. Also keep in local history at front
        const list = [text].concat(root.history.filter(it => it !== text).slice(0, 49));
        root.history = list;
    }

    function clearHistory() {
        root.history = [];
        root.currentText = "";
        clearProc.command = ["qdbus6", "org.kde.klipper", "/klipper", "org.kde.klipper.klipper.clearClipboardHistory"];
        clearProc.running = true;
    }

    Component.onCompleted: {
        refresh();
    }
}
