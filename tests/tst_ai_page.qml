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

    readonly property string aiPageSrc: {
        const xhr = new XMLHttpRequest();
        xhr.open("GET", Qt.resolvedUrl("../settings_gui/pages/AiPage.qml"), false);
        xhr.send(null);
        return xhr.responseText;
    }

    function assert(cond, msg) {
        if (!cond) {
            console.error("FAIL: " + msg);
            Qt.exit(1);
            throw new Error(msg);
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
                display_name: "Google Gemini (Antigravity)",
                plan_type: "OAuth",
                is_available: true,
                account_email: "gitawego@gmail.com",
                accounts: [
                    { id: "acc_1", identity: "gitawego@gmail.com", label: "Work", is_active: true },
                    { id: "acc_2", identity: "personal@gmail.com", label: "Personal", is_active: false }
                ],
                windows: [
                    { label: "5h", used_percent: 85.0, remaining_percent: 15.0, reset_at: "in 1 hour" }
                ]
            },
            {
                provider: "opencode",
                provider_id: "opencode-go",
                display_name: "OpenCode Go",
                plan_type: "Usage-Based",
                is_available: true,
                account_email: "Account 1",
                accounts: [
                    { id: "oc_1", identity: "Account 1", label: "Account 1", is_active: true },
                    { id: "oc_2", identity: "Account 2", label: "Account 2", is_active: false }
                ],
                windows: [
                    { label: "5h", used_percent: 14.0, remaining_percent: 86.0, reset_at: "in 3 hours" }
                ]
            },
            {
                provider: "minimax",
                provider_id: "minimax-cn",
                display_name: "MiniMax",
                plan_type: "Coding Plan",
                is_available: true,
                account_email: "Default",
                accounts: [
                    { id: "mm_1", identity: "Default", label: "Default", is_active: true }
                ],
                windows: [
                    { label: "5h", used_percent: 0.0, remaining_percent: 100.0, reset_at: "in 4 hours" }
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
        assert(aiPage.providersList.length === 3, "Must have 3 test providers");

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

        // 7. Configured Accounts verification & Layout Regression Guard
        assert(aiPage.providersList[0].accounts.length === 2, "Must have 2 configured Gemini accounts");
        assert(aiPage.providersList[0].accounts[0].identity === "gitawego@gmail.com", "First account identity must match");
        assert(aiPage.providersList[0].accounts[0].is_active === true, "First account must be active");
        assert(aiPage.providersList[0].accounts[1].identity === "personal@gmail.com", "Second account identity must match");
        assert(aiPage.providersList[0].accounts[1].is_active === false, "Second account must be inactive");

        // Regression test: ProviderQuotaCards must never be pushed off-screen into a clipped second column
        aiPage.width = 800;
        assert(aiPage.providersRepeaterItem !== undefined && aiPage.providersRepeaterItem.count === 3,
            "All 3 provider cards must be instantiated by the repeater");
        for (let i = 0; i < aiPage.providersRepeaterItem.count; i++) {
            const card = aiPage.providersRepeaterItem.itemAt(i);
            assert(card !== null, "Provider card " + i + " must exist");
            assert(card.x === 0, "Provider card " + i + " (" + card.provider.display_name + ") must start at x=0, got x=" + card.x);
            assert(card.width >= 700, "Provider card " + i + " must span full column width, got width=" + card.width);
            assert(card.accountsContentItem !== undefined && card.accountsContentItem.visible === true,
                "Provider card " + i + " (" + card.provider.provider_id + ") must make its accounts configuration content visible for all providers");
        }

        // 7b. Multi-provider account operations (Switch, Add, Remove) & Add Provider panel
        assert(aiPage.addProviderOpen === false, "Add Provider card must start closed");
        aiPage.addProviderButtonItem.clicked();
        assert(aiPage.addProviderOpen === true, "Clicking Add Provider button must open Add Provider panel");
        assert(aiPage.addProviderCardItem.visible === true, "Add Provider card must be visible when open");

        aiPage.switchProviderAccount("opencode-go", "oc_2");
        assert(aiPage.testAccountSwitchRequests.length === 1, "switchProviderAccount must record switch request");
        assert(aiPage.testAccountSwitchRequests[0].provider === "opencode-go" && aiPage.testAccountSwitchRequests[0].target === "oc_2",
            "switchProviderAccount must target opencode-go oc_2");

        aiPage.addProviderAccount("deepseek", "sk-test-12345", "DeepSeek Main");
        assert(aiPage.testAccountAddRequests.length === 1, "addProviderAccount must record add request");
        assert(aiPage.testAccountAddRequests[0].provider === "deepseek" && aiPage.testAccountAddRequests[0].label === "DeepSeek Main",
            "addProviderAccount must record provider and label");

        aiPage.removeProviderAccount("opencode-go", "oc_1");
        assert(aiPage.testAccountRemoveRequests.length === 1, "removeProviderAccount must record remove request");
        assert(aiPage.testAccountRemoveRequests[0].provider === "opencode-go" && aiPage.testAccountRemoveRequests[0].target === "oc_1",
            "removeProviderAccount must record provider and target");

        // 7c. Setup header eyebrow must never contain "undefined"
        assert(aiPage.setupHeaderItem.eyebrow.indexOf("undefined") === -1,
            "setupHeader eyebrow must never contain 'undefined', got: " + aiPage.setupHeaderItem.eyebrow);

        // 8. Authentication and Cancel button verification
        assert(!aiPage.isAuthenticating, "aiPage.isAuthenticating must start false");
        assert(aiPage.authenticatingEmail === "", "aiPage.authenticatingEmail must start empty");

        aiPage.testIsAuthenticating = true;
        aiPage.testAuthenticatingEmail = "gitawego@gmail.com";
        assert(aiPage.isAuthenticating === true, "aiPage.isAuthenticating must be true when testIsAuthenticating is set");
        assert(aiPage.authenticatingEmail === "gitawego@gmail.com", "aiPage.authenticatingEmail must match");

        aiPage.cancelAuth();
        assert(aiPage.isAuthenticating === false, "aiPage.isAuthenticating must be false after cancelAuth()");
        assert(aiPage.authenticatingEmail === "", "aiPage.authenticatingEmail must be empty after cancelAuth()");

        // 9. Desktop Agent Skills verification
        assert(aiPage.skillInstalled === false, "agent skill must start uninstalled");
        assert(aiPage.installSkillButtonItem.visible === true, "install button must be visible when uninstalled");
        assert(aiPage.uninstallSkillButtonItem.visible === false, "uninstall button must be hidden when uninstalled");
        assert(aiPage.reinstallSkillButtonItem.visible === false, "reinstall button must be hidden when uninstalled");
        assert(aiPage.skillStatusItem.text.indexOf("is not installed") >= 0, "status must indicate not installed");

        aiPage.installSkill();
        assert(aiPage.testInstallSkillRequests === 1, "installSkill() must record request");

        aiPage.testSkillInstalled = true;
        aiPage.testSkillLocations = ["/home/hlu/.agents/skills/astral-desktop-tools"];
        assert(aiPage.skillInstalled === true, "skillInstalled must reflect testSkillInstalled");
        assert(aiPage.installSkillButtonItem.visible === false, "install button hidden when installed");
        assert(aiPage.uninstallSkillButtonItem.visible === true, "uninstall button visible when installed");
        assert(aiPage.reinstallSkillButtonItem.visible === true, "reinstall button visible when installed");
        assert(aiPage.skillStatusItem.text.indexOf("installed") >= 0, "status text must indicate installed");

        aiPage.uninstallSkill();
        assert(aiPage.testUninstallSkillRequests === 1, "uninstallSkill() must record request");

        // Deep links land on a section, not just the page.
        assert(typeof aiPage.sectionY === "function", "AiPage must expose section anchors for deep links");
        assert(aiPage.sectionY("skills") >= 0, "the skills anchor must be inside the page");
        assert(aiPage.sectionY("skill") === aiPage.sectionY("skills"), "skill and skills aliases must match");
        assert(aiPage.sectionY("setup") === aiPage.sectionY("skills"), "setup alias must match skills");
        assert(aiPage.sectionY("copilot") >= 0, "the copilot anchor must be inside the page");
        assert(aiPage.sectionY("quotas") >= 0, "the quotas anchor must be inside the page");
        assert(aiPage.sectionY("nope") === undefined, "an unknown section has no anchor");

        console.log("PASS: AI Settings Page Unit Tests");
        Qt.exit(0);
    }
}
