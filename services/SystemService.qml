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

    readonly property string serviceDir: Qt.resolvedUrl(".").toString().replace("file://", "").replace(/\/$/, "")
    readonly property string daemonBin: root.serviceDir + "/../bin/astral-plasma"

    Process {
        id: sysInfoProc
        command: [root.daemonBin, "metrics"]
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

    Component.onCompleted: {
        if (!sysInfoProc.running) sysInfoProc.running = true;
    }

    readonly property bool isUiActive: (typeof Config !== "undefined")
        ? (Config.dashboardVisible ||
           (Config.bottomPopoutVisible && Config.bottomPopoutMode === "power") ||
           (Config.settingsVisible && Config.activeSettingsPage === "system"))
        : false

    onIsUiActiveChanged: {
        if (isUiActive && !sysInfoProc.running) {
            sysInfoProc.running = true;
        }
    }

    Timer {
        interval: 5000
        running: root.isUiActive
        repeat: true
        triggeredOnStart: false
        onTriggered: {
            if (!sysInfoProc.running) sysInfoProc.running = true;
        }
    }
}
