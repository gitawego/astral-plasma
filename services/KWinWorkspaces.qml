pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property int count: 1
    property string currentId: ""
    property var desktops: [] // Array of { id, name, index, active }

    readonly property string serviceDir: Qt.resolvedUrl(".").toString().replace("file://", "").replace(/\/$/, "")
    readonly property string daemonBin: root.serviceDir + "/../bin/caelestia-daemon"

    Process {
        id: queryDesktops
        command: [root.daemonBin, "workspaces", "query"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(this.text.trim());
                    root.currentId = data.current;
                    root.count = data.count;
                    root.desktops = data.items;
                } catch (e) {}
            }
        }
    }

    Process {
        id: switchProc
    }

    Process {
        id: createAndSwitchProc
        onRunningChanged: {
            if (!running) root.refresh();
        }
    }

    function refresh() {
        if (!queryDesktops.running) queryDesktops.running = true;
    }

    function switchTo(id) {
        switchProc.command = [root.daemonBin, "workspaces", "switch", id];
        switchProc.running = true;
        root.currentId = id;
        for (let i = 0; i < root.desktops.length; i++) {
            root.desktops[i].active = (root.desktops[i].id === id);
        }
        root.desktopsChanged();
    }

    function switchToWorkspace(index) {
        if (index < root.desktops.length && root.desktops[index] && root.desktops[index].id) {
            switchTo(root.desktops[index].id);
        } else {
            createAndSwitchProc.command = [root.daemonBin, "workspaces", "ensure", "" + index];
            createAndSwitchProc.running = true;
        }
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!queryDesktops.running) queryDesktops.running = true;
        }
    }
}
