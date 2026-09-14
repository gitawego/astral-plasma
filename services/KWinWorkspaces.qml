pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property int count: 1
    property string currentId: ""
    property var desktops: [] // Array of { id, name, index, active }

    Process {
        id: queryDesktops
        command: ["python3", "-c", 
            "import subprocess, re, json\n" +
            "out = subprocess.check_output(['qdbus6', '--literal', 'org.kde.KWin', '/VirtualDesktopManager', 'org.kde.KWin.VirtualDesktopManager.desktops']).decode('utf-8')\n" +
            "curr = subprocess.check_output(['qdbus6', 'org.kde.KWin', '/VirtualDesktopManager', 'org.kde.KWin.VirtualDesktopManager.current']).decode('utf-8').strip()\n" +
            "matches = re.findall(r'\\(uss\\)\\s*(\\d+),\\s*\"([^\"]+)\",\\s*\"([^\"]+)\"', out)\n" +
            "items = [{'index': int(m[0]), 'id': m[1], 'name': m[2], 'active': m[1] == curr} for m in matches]\n" +
            "if not items:\n" +
            "    items = [{'index': 0, 'id': 'default', 'name': 'Desktop 1', 'active': True}]\n" +
            "print(json.dumps({'current': curr, 'count': len(items), 'items': items}))\n"
        ]
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

    function switchTo(id) {
        switchProc.command = ["qdbus6", "org.kde.KWin", "/VirtualDesktopManager", "org.kde.KWin.VirtualDesktopManager.current", id];
        switchProc.running = true;
        root.currentId = id;
        for (let i = 0; i < root.desktops.length; i++) {
            root.desktops[i].active = (root.desktops[i].id === id);
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
