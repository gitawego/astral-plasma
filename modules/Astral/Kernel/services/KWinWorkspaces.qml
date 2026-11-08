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
    readonly property string daemonBin: root.serviceDir + "/../bin/astral-plasma"

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
        onRunningChanged: {
            if (!running) root.refresh();
        }
    }

    Process {
        id: createAndSwitchProc
        onRunningChanged: {
            if (!running) root.refresh();
        }
    }

    Process {
        id: actionProc
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
        let updated = [];
        for (let i = 0; i < root.desktops.length; i++) {
            let item = Object.assign({}, root.desktops[i]);
            item.active = (item.id === id);
            updated.push(item);
        }
        root.desktops = updated;
    }

    function switchToDesktop(id) {
        switchTo(id);
    }

    function switchToWorkspace(index) {
        if (index < root.desktops.length && root.desktops[index] && root.desktops[index].id) {
            switchTo(root.desktops[index].id);
        } else {
            createAndSwitchProc.command = [root.daemonBin, "workspaces", "ensure", "" + index];
            createAndSwitchProc.running = true;
        }
    }

    function moveWindow(winId, desktopId) {
        if (!winId || !desktopId) return;
        actionProc.command = [root.daemonBin, "workspaces", "move-window", winId, desktopId];
        actionProc.running = true;
    }

    function createDesktop(name) {
        let cmd = [root.daemonBin, "workspaces", "create"];
        if (name && ("" + name).trim().length > 0) {
            cmd.push(("" + name).trim());
        }
        actionProc.command = cmd;
        actionProc.running = true;
    }

    function removeDesktop(desktopId) {
        if (!desktopId) return;
        actionProc.command = [root.daemonBin, "workspaces", "remove", desktopId];
        actionProc.running = true;
    }

    function renameDesktop(desktopId, name) {
        if (!desktopId || !name) return;
        actionProc.command = [root.daemonBin, "workspaces", "rename", desktopId, ("" + name).trim()];
        actionProc.running = true;
    }

    function toggleOverview() {
        actionProc.command = [root.daemonBin, "workspaces", "overview"];
        actionProc.running = true;
    }

    function toggleGrid() {
        actionProc.command = [root.daemonBin, "workspaces", "grid"];
        actionProc.running = true;
    }

    Timer {
        interval: 6000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!queryDesktops.running) queryDesktops.running = true;
        }
    }
}
