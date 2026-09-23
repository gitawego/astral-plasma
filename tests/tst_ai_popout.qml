import QtQuick
import "../theme"
import "../components"
import "../config"
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
            throw new Error(msg);
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

    function readLocalFile(relPath) {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", Qt.resolvedUrl(relPath), false);
        xhr.send();
        return xhr.responseText;
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

        // 9. Provider brand icon URL resolution & asset availability
        const cfgSrc = readLocalFile("../config/Config.qml");
        assert(cfgSrc.indexOf("function providerIconUrl(") !== -1, "Config.qml must define providerIconUrl()");
        assert(cfgSrc.indexOf('"gemini"') !== -1, "Config.qml providerIconUrl must handle gemini");
        assert(cfgSrc.indexOf('"minimax"') !== -1, "Config.qml providerIconUrl must handle minimax");
        assert(cfgSrc.indexOf('"xiaomi"') !== -1, "Config.qml providerIconUrl must handle xiaomi");
        assert(cfgSrc.indexOf('"deepseek"') !== -1, "Config.qml providerIconUrl must handle deepseek");
        assert(cfgSrc.indexOf('"anthropic"') !== -1, "Config.qml providerIconUrl must handle anthropic");
        assert(cfgSrc.indexOf('"openai"') !== -1, "Config.qml providerIconUrl must handle openai");
        assert(cfgSrc.indexOf('"antigravity"') !== -1, "Config.qml providerIconUrl must handle antigravity");
        assert(cfgSrc.indexOf('"../theme/assets/icons/" + name + ".svg"') !== -1, "Config.qml providerIconUrl must construct theme/assets/icons SVG URL");

        assert(readLocalFile("../theme/assets/icons/gemini.svg").length > 0, "gemini.svg must exist");
        assert(readLocalFile("../theme/assets/icons/minimax.svg").length > 0, "minimax.svg must exist");
        assert(readLocalFile("../theme/assets/icons/opencode.svg").length > 0, "opencode.svg must exist");
        assert(readLocalFile("../theme/assets/icons/opencode-dark.svg").length > 0, "opencode-dark.svg must exist");
        assert(readLocalFile("../theme/assets/icons/xiaomi.svg").length > 0, "xiaomi.svg must exist");
        assert(readLocalFile("../theme/assets/icons/deepseek.svg").length > 0, "deepseek.svg must exist");
        assert(readLocalFile("../theme/assets/icons/anthropic.svg").length > 0, "anthropic.svg must exist");
        assert(readLocalFile("../theme/assets/icons/openai.svg").length > 0, "openai.svg must exist");
        assert(readLocalFile("../theme/assets/icons/ollama.svg").length > 0, "ollama.svg must exist");
        assert(readLocalFile("../theme/assets/icons/ollama-dark.svg").length > 0, "ollama-dark.svg must exist");
        assert(readLocalFile("../theme/assets/icons/antigravity.svg").length > 0, "antigravity.svg must exist");

        if (typeof Config !== "undefined" && typeof Config.providerIconUrl === "function") {
            assert(Config.providerIconUrl("gemini").indexOf("gemini.svg") !== -1, "Gemini icon URL must end with gemini.svg");
            assert(Config.providerIconUrl("minimax-cn").indexOf("minimax.svg") !== -1, "MiniMax icon URL must end with minimax.svg");
        }

        // 10. Account row tabular column alignment & dedicated action bar verification
        const aiSecSrc = readLocalFile("../dock/popouts/AiTokensSection.qml");
        assert(aiSecSrc.indexOf("Layout.preferredWidth: 82") !== -1, "Quota percentages must have fixed preferredWidth 82 for tabular alignment");
        assert(aiSecSrc.indexOf("horizontalAlignment: Text.AlignRight") !== -1, "Quota percentages must be right aligned");
        assert(aiSecSrc.indexOf("Layout.preferredWidth: 44") !== -1, "Action buttons must be housed in fixed 44px container");
        assert(aiSecSrc.indexOf("Dedicated Action Bar for Selected Account") !== -1, "AiTokensSection must have dedicated action bar for selected account");
        assert(aiSecSrc.indexOf("text: \"Manage\"") !== -1, "AiTokensSection must provide Manage button in header");

        console.log("PASS: AI Popout and Section Unit Tests");
        Qt.exit(0);
    }
}
