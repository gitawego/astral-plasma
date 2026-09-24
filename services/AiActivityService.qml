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
    property real tokenRate: 0.0
    property real recentTokens: 0.0

    // Combined throughput load from request rate (RPM) and token processing rate
    readonly property real throughputLoad: Math.max(0.0, root.requestRate + (root.tokenRate / 2500.0) + Math.min(15.0, root.recentTokens / 2000.0))

    // Velocity modulation: higher throughput load accelerates electric travel duration (850ms to 2400ms)
    readonly property int currentTravelDuration: Math.max(850, Math.min(2400, Math.round(2400.0 / (1.0 + 0.08 * throughputLoad))))

    // Breathing pulse duration modulated by throughput: faster for high RPM/tokens (500ms to 2000ms)
    readonly property int pulseDuration: Math.max(500, Math.min(2200, Math.round(2000.0 / (1.0 + 0.15 * throughputLoad))))

    // Electric packet length elongates with higher velocity/momentum (48px to 96px)
    readonly property real packetLength: Math.min(96, Math.max(48, 48 + throughputLoad * 1.5))

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

    // Fallback auto-decay watchdog: resets active state to idle if no agent events arrive for 9s
    Timer {
        id: autoDecayWatchdog
        interval: 9000
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
        if (data.token_rate !== undefined) root.tokenRate = Number(data.token_rate);
        if (data.recent_tokens !== undefined) root.recentTokens = Number(data.recent_tokens);

        if (root.isActive) {
            autoDecayWatchdog.restart();
        } else {
            autoDecayWatchdog.stop();
        }
    }
}
