import QtQuick
import "../theme"
import "../components"
import "../settings_gui/pages"

Item {
    id: testRoot
    width: 800
    height: 600

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

    AiPage {
        id: aiPage
        testMode: true
        testAiEnabled: true
        testDockPillMode: "dynamic"
        testWarningThreshold: 80
        testCriticalThreshold: 95
        testPollInterval: 5
        testProviders: [
            {
                provider: "gemini",
                provider_id: "gemini",
                display_name: "Gemini (Antigravity)",
                plan_type: "Pro Plan",
                is_available: true,
                account_email: "gitawego@gmail.com",
                accounts: [
                    { id: "acc_1", identity: "gitawego@gmail.com", label: "Work", is_active: true },
                    { id: "acc_2", identity: "personal@gmail.com", label: "Personal", is_active: false }
                ],
                windows: [
                    { label: "5h", used_percent: 85.0, remaining_percent: 15.0, reset_at: "in 1 hour" }
                ]
            }
        ]
    }

    function runTests() {
        console.log("RUNNING: AI Settings Page Unit Tests");

        // 1. Initial State
        assert(aiPage.aiEnabled === true, "AI must start enabled");
        assert(aiPage.dockPillMode === "dynamic", "Dock pill mode must start dynamic");
        assert(aiPage.warningThreshold === 80, "Warning threshold must start at 80");
        assert(aiPage.criticalThreshold === 95, "Critical threshold must start at 95");
        assert(aiPage.pollInterval === 5, "Poll interval must start at 5m");
        assert(aiPage.providersList.length === 1, "Must have 1 test provider");

        // 2. Toggle AI enabled
        aiPage.setAiEnabled(false);
        assert(aiPage.aiEnabled === false, "AI must be disabled after toggle");
        aiPage.setAiEnabled(true);
        assert(aiPage.aiEnabled === true, "AI must be enabled after re-toggle");

        // 3. Change pill mode
        aiPage.setDockPillMode("warning");
        assert(aiPage.dockPillMode === "warning", "Dock pill mode must update to warning");

        // 4. Change thresholds
        aiPage.setThresholds(75, 90);
        assert(aiPage.warningThreshold === 75, "Warning threshold must update to 75");
        assert(aiPage.criticalThreshold === 90, "Critical threshold must update to 90");

        // 5. Change poll interval
        aiPage.setPollInterval(10);
        assert(aiPage.pollInterval === 10, "Poll interval must update to 10m");

        // 6. Gemini Monthly Quota settings
        assert(aiPage.geminiMonthlyEnabled === true, "Gemini monthly tracking must start enabled");
        assert(aiPage.geminiMonthlyRemainingPercent === 85.0, "Gemini monthly remaining % must start at 85");
        assert(aiPage.geminiMonthlyResetDay === 1, "Gemini monthly reset day must start at 1");

        aiPage.setGeminiMonthlyEnabled(false);
        assert(aiPage.geminiMonthlyEnabled === false, "Gemini monthly tracking must be disabled after toggle");
        aiPage.setGeminiMonthlyEnabled(true);
        assert(aiPage.geminiMonthlyEnabled === true, "Gemini monthly tracking must be re-enabled");

        aiPage.setGeminiMonthlyRemainingPercent(75.0);
        assert(aiPage.geminiMonthlyRemainingPercent === 75.0, "Gemini monthly remaining % must update to 75");

        aiPage.setGeminiMonthlyResetDay(15);
        assert(aiPage.geminiMonthlyResetDay === 15, "Gemini monthly reset day must update to 15");

        // 7. Configured Accounts verification
        assert(aiPage.providersList[0].accounts.length === 2, "Must have 2 configured accounts");
        assert(aiPage.providersList[0].accounts[0].identity === "gitawego@gmail.com", "First account identity must match");
        assert(aiPage.providersList[0].accounts[0].is_active === true, "First account must be active");
        assert(aiPage.providersList[0].accounts[1].identity === "personal@gmail.com", "Second account identity must match");
        assert(aiPage.providersList[0].accounts[1].is_active === false, "Second account must be inactive");

        console.log("PASS: AI Settings Page Unit Tests");
        Qt.exit(0);
    }
}
