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
    property var activeAgents: []

    readonly property var primaryAgent: (activeAgents && activeAgents.length > 0) ? activeAgents[0] : null
    readonly property var secondaryAgent: (activeAgents && activeAgents.length > 1) ? activeAgents[1] : null

    // Combined throughput load from request rate (RPM) and token processing rate
    readonly property real throughputLoad: Math.max(0.0, root.requestRate + (root.tokenRate / 2500.0) + Math.min(15.0, root.recentTokens / 2000.0))

    // Velocity modulation: slowed down slightly for smooth, elegant, and trackable motion (1350ms to 3200ms)
    readonly property int currentTravelDuration: Math.max(1350, Math.min(3200, Math.round(3200.0 / (1.0 + 0.045 * throughputLoad))))

    // Breathing pulse duration modulated by throughput: faster for high RPM/tokens (750ms to 2600ms)
    readonly property int pulseDuration: Math.max(750, Math.min(2600, Math.round(2400.0 / (1.0 + 0.08 * throughputLoad))))

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

    // Fallback auto-decay watchdog: resets active state to idle if no agent events arrive for 8s
    Timer {
        id: autoDecayWatchdog
        interval: 8000
        repeat: false
        running: root.isActive
        onTriggered: {
            root.isActive = false;
            root.intensity = 0.0;
            root.requestRate = 0.0;
            root.tokenRate = 0.0;
            root.recentTokens = 0.0;
            root.activeAgents = [];
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
        if (data.active_agents !== undefined && Array.isArray(data.active_agents)) {
            root.activeAgents = data.active_agents;
        }
        if (!root.isActive) {
            root.intensity = 0.0;
            root.requestRate = 0.0;
            root.tokenRate = 0.0;
            root.recentTokens = 0.0;
            root.activeAgents = [];
            autoDecayWatchdog.stop();
        } else {
            autoDecayWatchdog.restart();
        }
    }
}
