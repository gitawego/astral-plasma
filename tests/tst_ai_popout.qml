import QtQuick
import "../theme"
import "../components"
import "../dock/popouts"

Item {
    id: testRoot
    width: 600
    height: 800

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

    // Host AiTokensSection directly in testMode
    AiTokensSection {
        id: aiSection
        anchors.centerIn: parent
        testMode: true
        testWarningLevel: "warning"
        testProviders: [
            {
                provider: "gemini",
                display_name: "Gemini (Antigravity)",
                plan_type: "Pro Plan",
                is_available: true,
                account_email: "gitawego@gmail.com",
                accounts: [
                    { id: "gitawego@gmail.com", identity: "gitawego@gmail.com", is_active: true },
                    { id: "secondary@gmail.com", identity: "secondary@gmail.com", is_active: false }
                ],
                windows: [
                    { label: "5h", used_percent: 88.0, remaining_percent: 12.0, reset_at: "in 1 hour" }
                ]
            },
            {
                provider: "opencode",
                display_name: "OpenCode Go",
                plan_type: "Go Plan",
                is_available: true,
                account_email: "",
                accounts: [],
                windows: [
                    { label: "5h", used_percent: 40.0, remaining_percent: 60.0, reset_at: "in 2 hours" }
                ]
            }
        ]
    }

    function runTests() {
        console.log("RUNNING: AI Popout and Section Unit Tests");

        // 1. Initial dimensions check
        assert(aiSection !== null, "AiTokensSection must exist");
        assert(aiSection.implicitWidth === 320, "AiTokensSection implicitWidth must be 320, got " + aiSection.implicitWidth);
        assert(aiSection.implicitHeight > 0, "AiTokensSection implicitHeight must be > 0, got " + aiSection.implicitHeight);

        // 2. Active provider selection
        assert(aiSection.currentProvider !== null, "currentProvider must not be null");
        assert(aiSection.currentProvider.provider === "gemini", "Gemini must be initial provider (highest quota)");
        assert(aiSection.warningLevel === "warning", "warningLevel must be warning");

        // 3. Switch active provider
        aiSection.activeProviderIndex = 1;
        assert(aiSection.currentProvider !== null, "currentProvider must not be null after switch");
        assert(aiSection.currentProvider.provider === "opencode", "OpenCode must be active provider after switch");

        // 4. Test critical warning tier
        aiSection.testWarningLevel = "critical";
        assert(aiSection.warningLevel === "critical", "warningLevel must update to critical");

        console.log("PASS: AI Popout and Section Unit Tests");
        Qt.exit(0);
    }
}
