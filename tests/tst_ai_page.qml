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

        // A downloaded model must be removable, and the control must only exist
        // while there is something to remove.
        assert(aiPage.voiceModelRemoveItem !== undefined, "AiPage must offer removing a downloaded model");
        aiPage.testVoiceStatus = { engine_available: true, model_present: true, setup_complete: true, gap: "" };
        assert(aiPage.voiceModelPresent === true, "the seam must drive model presence");
        assert(aiPage.voiceModelRemoveItem.visible === true, "the remove control shows for a present model");
        aiPage.testVoiceStatus = { engine_available: true, model_present: false, setup_complete: false, gap: "model_missing" };
        assert(aiPage.voiceModelRemoveItem.visible === false, "no remove control without a model");
        aiPage.testVoiceStatus = null;

        // The install one-liner must come from the daemon, which knows the
        // distribution. A hardcoded `pacman` line is a dead end everywhere else.
        aiPage.testVoiceStatus = { engine_available: false, engine_install_command: "sudo dnf install whisper-cpp" };
        assert(aiPage.voiceEngineNotice.indexOf("sudo dnf install whisper-cpp") >= 0,
            "the engine notice must show the command the daemon reported, got: " + aiPage.voiceEngineNotice);
        aiPage.testVoiceStatus = { engine_available: false, engine_install_command: "" };
        assert(aiPage.voiceEngineNotice.indexOf("github.com/ggml-org/whisper.cpp") >= 0,
            "an unknown distribution must get the upstream build, got: " + aiPage.voiceEngineNotice);
        aiPage.testVoiceStatus = null;

        // Readiness must be re-probed when the page is shown: a status cached at
        // shell start goes stale the moment someone installs the engine. The
        // probe goes through one named helper so construction and visibility
        // share the exact same guard (and the test seam stays honoured).
        assert(/onVisibleChanged:\s*if\s*\(visible\)\s*refreshVoiceReadiness\(\)/.test(aiPageSrc),
            "AiPage must refresh voice readiness when it becomes visible");

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
        assert(aiPage.sectionY("voice") > aiPage.voicePanelItem.y,
            "the voice anchor must be mapped into the page's space, got " + aiPage.sectionY("voice"));
        assert(aiPage.sectionY("voice") >= 0, "the voice anchor must be inside the page");
        assert(aiPage.sectionY("skills") >= 0, "the skills anchor must be inside the page");
        assert(aiPage.sectionY("skill") === aiPage.sectionY("skills"), "skill and skills aliases must match");
        assert(aiPage.sectionY("nope") === undefined, "an unknown section has no anchor");

        console.log("PASS: AI Settings Page Unit Tests");
        Qt.exit(0);
    }
}
