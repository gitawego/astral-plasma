pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property string currentLayout: "US"
    property int currentIndex: 0
    property var layouts: ["US"]

    Process {
        id: queryCurrent
        command: ["qdbus6", "org.kde.keyboard", "/Layouts", "org.kde.KeyboardLayouts.getLayout"]
        stdout: StdioCollector {
            onStreamFinished: {
                const idx = parseInt(this.text.trim());
                if (!isNaN(idx)) {
                    root.currentIndex = idx;
                    if (root.layouts.length > idx) {
                        root.currentLayout = root.layouts[idx];
                    }
                }
            }
        }
    }

    Process {
        id: nextLayoutProc
        command: ["qdbus6", "org.kde.keyboard", "/Layouts", "org.kde.KeyboardLayouts.switchToNextLayout"]
        onExited: queryCurrent.running = true
    }

    Process {
        id: setLayoutProc
    }

    function nextLayout() {
        nextLayoutProc.running = true;
    }

    function setLayout(idx) {
        setLayoutProc.command = ["qdbus6", "org.kde.keyboard", "/Layouts", "org.kde.KeyboardLayouts.setLayout", idx.toString()];
        setLayoutProc.running = true;
        root.currentIndex = idx;
    }

    Timer {
        interval: 3000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!queryCurrent.running) queryCurrent.running = true;
        }
    }
}
