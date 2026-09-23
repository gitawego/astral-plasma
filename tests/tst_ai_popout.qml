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
                    { label: "5h", used_percent: 88.0, remaining_percent: 12.0, reset_at: "in 1 hour" },
                    { label: "weekly", used_percent: 20.0, remaining_percent: 80.0, reset_at: "in 6 days" },
                    { label: "monthly", used_percent: 10.0, remaining_percent: 90.0, reset_at: "in 25 days" }
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
            },
            {
                provider: "minimax-cn",
                display_name: "MiniMax",
                plan_type: "Pay-as-you-go",
                is_available: true,
                account_email: "",
                accounts: [
                    { id: "default", label: "Default Account", is_active: true }
                ],
                windows: []
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
        assert(aiSection.currentProvider.provider === "gemini", "Gemini must be initial provider");
        assert(aiSection.warningLevel === "warning", "warningLevel must be warning");

        // 3. Active account vs selected account separation
        assert(aiSection.activeAccount !== null, "activeAccount must not be null");
        assert(aiSection.activeAccount.identity === "gitawego@gmail.com", "Active account must be gitawego@gmail.com");
        assert(aiSection.selectedAccount.identity === "gitawego@gmail.com", "Default selected account must be active account");

        // Select secondary account to inspect
        aiSection.selectedAccountIdentity = "secondary@gmail.com";
        assert(aiSection.selectedAccount.identity === "secondary@gmail.com", "Selected account must now be secondary@gmail.com");
        assert(aiSection.activeAccount.identity === "gitawego@gmail.com", "Active account must remain gitawego@gmail.com");

        // 4. Monthly quota window check
        assert(aiSection.currentWindows.length === 3, "Expected 3 quota windows for Gemini (5h, weekly, monthly)");
        assert(aiSection.currentWindows[2].label === "monthly", "3rd window must be monthly");
        assert(aiSection.currentWindows[2].remaining_percent === 90.0, "Monthly remaining percent must be 90.0");

        // 5. Switch active provider to OpenCode
        aiSection.activeProviderIndex = 1;
        assert(aiSection.currentProvider !== null, "currentProvider must not be null after switch");
        assert(aiSection.currentProvider.provider === "opencode", "OpenCode must be active provider after switch");

        // 6. Switch to MiniMax pay-as-you-go provider
        aiSection.activeProviderIndex = 2;
        assert(aiSection.currentProvider !== null, "MiniMax must not be null");
        assert(aiSection.currentProvider.provider === "minimax-cn", "MiniMax must be 3rd provider");
        assert(aiSection.currentWindows.length === 0, "MiniMax pay-as-you-go should have empty windows");

        // 7. Test critical warning tier
        aiSection.testWarningLevel = "critical";
        assert(aiSection.warningLevel === "critical", "warningLevel must update to critical");

        // 8. Account switching and inspect separation
        aiSection.activeProviderIndex = 0; // Back to gemini
        assert(aiSection.currentProvider !== null && aiSection.currentProvider.accounts !== undefined, "currentProvider must have accounts");
        assert(aiSection.currentProvider.accounts.length === 2, "Expected 2 gemini accounts in test data");
        assert(aiSection.currentProvider.accounts[0].is_active === true, "First account must be active in test model");
        assert(aiSection.currentProvider.accounts[1].is_active === false, "Second account must be inactive in test model");

        console.log("PASS: AI Popout and Section Unit Tests");
        Qt.exit(0);
    }
}
