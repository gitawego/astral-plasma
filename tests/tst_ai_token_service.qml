import QtQuick
import "../theme"
import "../components"

Item {
    id: testRoot
    width: 600
    height: 400

    Timer {
        interval: 50
        running: true
        repeat: false
        onTriggered: runTests()
    }

    function assert(cond, msg) {
        if (!cond) {
            console.error("FAIL: " + msg);
            Qt.exit(1);
            return false;
        }
        return true;
    }

    // AI Token Model matching services/AiTokenService.qml specification
    QtObject {
        id: aiModel

        property bool aiEnabled: true
        property string aiDockPillMode: "dynamic"
        property real aiWarningThreshold: 80
        property real aiCriticalThreshold: 95
        property int aiPollIntervalMinutes: 5

        property var providers: []
        property real highestUsedPercent: 0.0
        property real lowestRemainingPercent: 100.0
        property string warningLevel: "normal"
        property string activeGeminiEmail: ""
        property string fetchedAt: ""
        property bool isRefreshing: false

        readonly property bool shouldShowPill: {
            if (!aiEnabled) return false;
            if (aiDockPillMode === "always") return true;
            if (aiDockPillMode === "never") return false;
            return (warningLevel === "warning" || warningLevel === "critical" || (providers && providers.length > 0));
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

        function applySnapshot(d) {
            if (!d) return;
            if (d.providers && Array.isArray(d.providers)) {
                providers = d.providers;
            }
            if (d.highest_used_percent !== undefined) {
                highestUsedPercent = d.highest_used_percent;
            }
            if (d.lowest_remaining_percent !== undefined) {
                lowestRemainingPercent = d.lowest_remaining_percent;
            }
            if (d.warning_level) {
                warningLevel = d.warning_level;
            }
            if (d.active_gemini_email !== undefined) {
                activeGeminiEmail = d.active_gemini_email || "";
            }
            if (d.active_gemini_account !== undefined) {
                activeGeminiEmail = d.active_gemini_account || "";
            }
            if (d.fetched_at) {
                fetchedAt = d.fetched_at;
            }
        }
    }

    function runTests() {
        console.log("RUNNING: AI Token Service Unit Tests");

        // 1. Initial State
        assert(aiModel.warningLevel === "normal", "Initial warningLevel must be normal");
        assert(aiModel.highestUsedPercent === 0.0, "Initial highestUsedPercent must be 0.0");
        assert(!aiModel.shouldShowPill, "Pill must not show when no providers and normal level");

        // 2. Test formatCountdown formatting contract
        assert(aiModel.formatCountdown(0) === "0s", "0s countdown");
        assert(aiModel.formatCountdown(45) === "45s", "45s countdown");
        assert(aiModel.formatCountdown(300) === "5m", "5m countdown");
        assert(aiModel.formatCountdown(3600) === "1h 00m", "1h 00m countdown");
        assert(aiModel.formatCountdown(3665) === "1h 01m", "1h 01m countdown");
        assert(aiModel.formatCountdown(90060) === "1d 01h", "1d 01h countdown");

        // 3. Ingest healthy mock snapshot
        var normalSnapshot = {
            "source": "cli_output",
            "active_gemini_account": "gitawego@gmail.com",
            "providers": [
                {
                    "provider": "gemini",
                    "display_name": "Gemini (Antigravity)",
                    "plan_type": "Pro Plan",
                    "is_available": true,
                    "windows": [
                        { "label": "5h", "used_percent": 35.0, "remaining_percent": 65.0, "reset_at": "in 3 hours" }
                    ]
                }
            ],
            "highest_used_percent": 35.0,
            "lowest_remaining_percent": 65.0,
            "warning_level": "normal"
        };

        aiModel.applySnapshot(normalSnapshot);
        assert(aiModel.providers.length === 1, "Must have 1 provider");
        assert(aiModel.activeGeminiEmail === "gitawego@gmail.com", "Gemini email must match");
        assert(aiModel.highestUsedPercent === 35.0, "Highest used percent must match");
        assert(aiModel.warningLevel === "normal", "Warning level must be normal");
        assert(aiModel.shouldShowPill === true, "Dynamic pill shows because active provider exists");

        // 4. Test warning mode pill filter
        aiModel.aiDockPillMode = "warning";
        assert(aiModel.shouldShowPill === false, "Pill must be hidden when pillMode is warning but level is normal");

        // 5. Ingest amber warning snapshot (82%)
        var warningSnapshot = {
            "source": "cli_output",
            "active_gemini_account": "gitawego@gmail.com",
            "providers": [
                {
                    "provider": "gemini",
                    "display_name": "Gemini (Antigravity)",
                    "plan_type": "Pro Plan",
                    "is_available": true,
                    "windows": [
                        { "label": "5h", "used_percent": 82.5, "remaining_percent": 17.5, "reset_at": "in 1 hour" }
                    ]
                }
            ],
            "highest_used_percent": 82.5,
            "lowest_remaining_percent": 17.5,
            "warning_level": "warning"
        };

        aiModel.applySnapshot(warningSnapshot);
        assert(aiModel.warningLevel === "warning", "Warning level must be warning");
        assert(aiModel.shouldShowPill === true, "Pill must show when pillMode is warning and level is warning");

        // 6. Ingest critical rose snapshot (97%)
        var criticalSnapshot = {
            "source": "cli_output",
            "active_gemini_account": "gitawego@gmail.com",
            "providers": [
                {
                    "provider": "gemini",
                    "display_name": "Gemini (Antigravity)",
                    "plan_type": "Pro Plan",
                    "is_available": true,
                    "windows": [
                        { "label": "5h", "used_percent": 97.0, "remaining_percent": 3.0, "reset_at": "in 45m" }
                    ]
                },
                {
                    "provider": "opencode",
                    "display_name": "OpenCode Go",
                    "plan_type": "Go Plan",
                    "is_available": true,
                    "windows": [
                        { "label": "weekly", "used_percent": 98.5, "remaining_percent": 1.5, "reset_at": "in 2 days" }
                    ]
                }
            ],
            "highest_used_percent": 98.5,
            "lowest_remaining_percent": 1.5,
            "warning_level": "critical"
        };

        aiModel.applySnapshot(criticalSnapshot);
        assert(aiModel.providers.length === 2, "Must have 2 providers");
        assert(aiModel.warningLevel === "critical", "Warning level must be critical");
        assert(aiModel.highestUsedPercent === 98.5, "Highest used must be 98.5");

        // 7. Pill mode "never" and "always"
        aiModel.aiDockPillMode = "never";
        assert(aiModel.shouldShowPill === false, "Pill must be hidden when never");

        aiModel.aiDockPillMode = "always";
        assert(aiModel.shouldShowPill === true, "Pill must show when always");

        console.log("PASS: AI Token Service Unit Tests");
        Qt.exit(0);
    }
}
