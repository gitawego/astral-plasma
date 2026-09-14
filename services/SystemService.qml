pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property string distroName: "CachyOS Linux"
    property string compositor: "KDE Plasma 6 (KWin)"
    property string uptime: "up 1 hour, 20 minutes"
    property real cpuUsage: 0.15
    property real ramUsage: 0.40

    Process {
        id: sysInfoProc
        command: ["python3", "-c",
            "import os, re, json\n" +
            "uptime_str = ''\n" +
            "try:\n" +
            "    with open('/proc/uptime') as f:\n" +
            "        s = float(f.readline().split()[0])\n" +
            "        h = int(s // 3600)\n" +
            "        m = int((s % 3600) // 60)\n" +
            "        uptime_str = f'up {h} hours, {m} minutes' if h > 0 else f'up {m} minutes'\n" +
            "except: pass\n" +
            "ram_pct = 0.0\n" +
            "try:\n" +
            "    with open('/proc/meminfo') as f:\n" +
            "        lines = f.readlines()\n" +
            "        mem = {l.split(':')[0]: float(l.split(':')[1].strip().split()[0]) for l in lines}\n" +
            "        total = mem.get('MemTotal', 1)\n" +
            "        avail = mem.get('MemAvailable', 0)\n" +
            "        ram_pct = (total - avail) / total\n" +
            "except: pass\n" +
            "print(json.dumps({'uptime': uptime_str, 'ram': ram_pct}))\n"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(this.text.trim());
                    if (d.uptime) root.uptime = d.uptime;
                    if (d.ram !== undefined) root.ramUsage = d.ram;
                } catch (e) {}
            }
        }
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!sysInfoProc.running) sysInfoProc.running = true;
        }
    }
}
