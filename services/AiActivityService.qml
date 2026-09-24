pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../theme"
import "../config"

Singleton {
    id: root

    property string agent: "idle"
    property string model: ""
    property string displayName: "AI Agent"
    property color brandColor: (typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#9bcbfb"
    property string brandIcon: "auto_awesome"
    property bool isActive: false
    property real intensity: 0.0
    property real requestRate: 0.0

    // Pulse duration modulated by request rate: faster for high RPM, calmer for steady state
    readonly property int pulseDuration: Math.max(900, Math.min(2600, 2400 - Math.round(root.requestRate * 180)))

    // Active effect enabled check
    readonly property bool effectEnabled: (typeof Config !== "undefined" && Config.modelActivityEffect !== undefined)
        ? Config.modelActivityEffect
        : true

    readonly property string serviceDir: Qt.resolvedUrl(".").toString().replace("file://", "").replace(/\/$/, "")
    readonly property string daemonBin: root.serviceDir + "/../bin/astral-plasma"

    // Query initial state on startup
    Process {
        id: initQueryProc
        command: [root.daemonBin, "ai", "activity"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const text = this.text.trim();
                    if (!text || !text.startsWith("{")) return;
                    const data = JSON.parse(text);
                    root.applyActivity(data);
                } catch (e) {
                    console.warn("AiActivityService: init query parse error:", e);
                }
            }
        }
    }

    // Fallback auto-decay watchdog: resets active state to idle if no agent events arrive for 15s
    Timer {
        id: autoDecayWatchdog
        interval: 15000
        repeat: false
        running: root.isActive
        onTriggered: {
            root.isActive = false;
            root.intensity = 0.0;
            root.requestRate = 0.0;
        }
    }

    function applyActivity(data) {
        if (!data) return;
        if (data.agent !== undefined) root.agent = data.agent;
        if (data.model !== undefined) root.model = data.model;
        if (data.display_name !== undefined) root.displayName = data.display_name;
        if (data.brand_color !== undefined && data.brand_color) root.brandColor = data.brand_color;
        if (data.brand_icon !== undefined && data.brand_icon) root.brandIcon = data.brand_icon;
        if (data.is_active !== undefined) root.isActive = Boolean(data.is_active);
        if (data.intensity !== undefined) root.intensity = Number(data.intensity);
        if (data.request_rate !== undefined) root.requestRate = Number(data.request_rate);

        if (root.isActive) {
            autoDecayWatchdog.restart();
        } else {
            autoDecayWatchdog.stop();
        }
    }
}
