pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

Singleton {
    id: root

    property var providers: []
    property real highestUsedPercent: 0.0
    property real lowestRemainingPercent: 100.0
    property string warningLevel: "normal" // "normal", "warning", "critical"
    property string activeGeminiEmail: ""
    property string lastActiveProviderId: "gemini"
    property string fetchedAt: ""
    property bool isRefreshing: false

    readonly property string serviceDir: Qt.resolvedUrl(".").toString().replace("file://", "").replace(/\/$/, "")
    readonly property string daemonBin: root.serviceDir + "/../bin/astral-plasma"

    readonly property bool shouldShowPill: {
        if (typeof Config === "undefined" || !Config.aiEnabled) return false;
        if (Config.aiDockPillMode === "always") return true;
        if (Config.aiDockPillMode === "never") return false;
        // "dynamic" mode: show if any model is in warning/critical state, or if valid providers exist
        return (root.warningLevel === "warning" || root.warningLevel === "critical" || root.providers.length > 0);
    }

    readonly property bool isUiActive: (typeof Config !== "undefined")
        ? ((Config.bottomPopoutVisible && Config.bottomPopoutMode === "ai") ||
           (Config.settingsVisible && Config.activeSettingsPage === "ai"))
        : false

    onIsUiActiveChanged: {
        if (isUiActive) {
            root.refresh(false);
        }
    }

    Process {
        id: statusProc
        command: [
            root.daemonBin,
            "ai",
            "status",
            (typeof Config !== "undefined" ? Config.aiWarningThreshold : 80).toString(),
            (typeof Config !== "undefined" ? Config.aiCriticalThreshold : 95).toString()
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                root.isRefreshing = false;
                try {
                    const text = this.text.trim();
                    if (!text) return;
                    const d = JSON.parse(text);
                    root.applySnapshot(d);
                } catch (e) {
                    console.warn("AiTokenService: Failed to parse quota JSON:", e);
                }
            }
        }
    }

    function applySnapshot(d) {
        if (!d) return;
        if (d.providers && Array.isArray(d.providers)) {
            root.providers = d.providers;
        }
        if (d.highest_used_percent !== undefined) {
            root.highestUsedPercent = d.highest_used_percent;
        }
        if (d.lowest_remaining_percent !== undefined) {
            root.lowestRemainingPercent = d.lowest_remaining_percent;
        }
        if (d.warning_level) {
            root.warningLevel = d.warning_level;
        }
        if (d.active_gemini_email !== undefined) {
            root.activeGeminiEmail = d.active_gemini_email || "";
        }
        if (d.active_gemini_account !== undefined) {
            root.activeGeminiEmail = d.active_gemini_account || "";
        }
        if (d.fetched_at) {
            root.fetchedAt = d.fetched_at;
        }
    }

    function formatCountdown(sec) {
        if (!sec || sec <= 0) return "0s";
        if (sec < 60) return Math.floor(sec) + "s";
        if (sec < 3600) {
            let m = Math.floor(sec / 60);
            return m + "m";
        }
        if (sec < 86400) {
            let h = Math.floor(sec / 3600);
            let remM = Math.floor((sec % 3600) / 60);
            return h + "h " + (remM < 10 ? "0" : "") + remM + "m";
        }
        let d = Math.floor(sec / 86400);
        let remH = Math.floor((sec % 86400) / 3600);
        return d + "d " + (remH < 10 ? "0" : "") + remH + "h";
    }

    Process {
        id: switchProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const text = this.text.trim();
                    if (text) {
                        const res = JSON.parse(text);
                        if (res.success && res.account) {
                            root.activeGeminiEmail = res.account;
                        }
                    }
                } catch (e) {
                    console.warn("AiTokenService: switch-account output parse error:", e);
                }
                root.isRefreshing = false;
                root.refresh(true);
            }
        }
        onExited: (code, status) => {
            root.isRefreshing = false;
            root.refresh(true);
        }
    }

    function refresh(force) {
        if (root.isRefreshing) return;
        root.isRefreshing = true;

        statusProc.command = [
            root.daemonBin,
            "ai",
            force ? "refresh" : "status",
            (typeof Config !== "undefined" ? Config.aiWarningThreshold : 80).toString(),
            (typeof Config !== "undefined" ? Config.aiCriticalThreshold : 95).toString()
        ];

        if (!statusProc.running) {
            statusProc.running = true;
        }
    }

    function switchGeminiAccount(targetIdOrEmail) {
        if (!targetIdOrEmail) return;
        switchProc.command = [root.daemonBin, "ai", "switch-account", "gemini", targetIdOrEmail];
        if (!switchProc.running) {
            switchProc.running = true;
        }
    }

    Timer {
        id: pollTimer
        interval: Math.max(60000, (typeof Config !== "undefined" ? Config.aiPollIntervalMinutes : 5) * 60000)
        running: (typeof Config !== "undefined" ? Config.aiEnabled : true)
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            root.refresh(false);
        }
    }

    Component.onCompleted: {
        root.refresh(false);
    }
}
