import QtQuick
import QtQuick.Layouts
import "../components"
import "../theme"
import "../config"
import "../shell"
import "../dashboard/tabs"

Item {
    id: testRoot
    width: 1280
    height: 900

    AiTab {
        id: aiTab
        visible: false
        anchors.fill: parent
        testMode: true
        testWarningLevel: "normal"
        testProviders: [
            {
                provider_id: "gemini",
                provider: "gemini",
                display_name: "Google Gemini (Antigravity)",
                plan_type: "Google AI Pro",
                is_available: true,
                account_email: "hongbo.lu.fr@gmail.com",
                accounts: [
                    { id: "acc-1", identity: "gitawego@gmail.com", is_active: false, five_hour_remaining_percent: 100.0, weekly_remaining_percent: 73.3 },
                    { id: "acc-2", identity: "hongbo.lu.cn@gmail.com", is_active: false, five_hour_remaining_percent: 0.0, weekly_remaining_percent: 83.3 },
                    { id: "acc-3", identity: "hongbo.lu.fr@gmail.com", is_active: true, five_hour_remaining_percent: 34.1, weekly_remaining_percent: 89.0 }
                ],
                windows: [
                    { label: "5h", used_percent: 65.9, remaining_percent: 34.1, reset_at: "2026-09-24T00:36:40Z" },
                    { label: "weekly", used_percent: 11.0, remaining_percent: 89.0, reset_at: "2026-09-30T11:56:44Z" }
                ]
            },
            {
                provider_id: "opencode-go",
                provider: "opencode-go",
                display_name: "OpenCode Go",
                plan_type: "Go Plan",
                is_available: true,
                account_email: "",
                accounts: [],
                windows: [
                    { label: "5h", used_percent: 0.0, remaining_percent: 100.0, reset_at: "in 2 hours" },
                    { label: "weekly", used_percent: 28.0, remaining_percent: 72.0, reset_at: "in 4 days" }
                ]
            },
            {
                provider_id: "minimax-cn",
                provider: "minimax-cn",
                display_name: "MiniMax",
                plan_type: "Coding Plan",
                is_available: true,
                account_email: "",
                accounts: [],
                windows: [
                    { label: "5h", used_percent: 0.0, remaining_percent: 100.0, reset_at: "in 3 hours" },
                    { label: "weekly", used_percent: 1.0, remaining_percent: 99.0, reset_at: "in 5 days" }
                ]
            }
        ]
    }

    CentralDropdown {
        id: dropdown
        dropX: 150
        dropW: 980
        visible: false
    }

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

    function runTests() {
        console.log("RUNNING: AiTab & CentralDropdown 5-Tab Architecture Unit Tests");

        // 1. AiTab instantiation & seamless Item contract
        assert(aiTab !== null, "AiTab must instantiate");
        assert(typeof aiTab.border === "undefined" || aiTab.border.width === 0,
               "AiTab must NOT have an outer border (must be seamless Item or borderless)");

        // 2. AiTab implicit dimensions
        assert(aiTab.implicitWidth >= 680, "AiTab implicitWidth should be at least 680, got: " + aiTab.implicitWidth);
        assert(aiTab.implicitHeight >= 320, "AiTab implicitHeight should be at least 320, got: " + aiTab.implicitHeight);

        // 3. Provider list & initial provider selection
        assert(aiTab.providersList.length === 3, "AiTab providersList should have 3 providers");
        assert(aiTab.currentProvider !== null, "currentProvider should not be null");
        assert(aiTab.currentProvider.provider_id === "gemini", "Initial provider should be gemini");

        // 4. Provider tab switching
        aiTab.activeProviderIndex = 1;
        assert(aiTab.currentProvider.provider_id === "opencode-go", "Switching activeProviderIndex to 1 should select opencode-go");
        assert(aiTab.currentWindows.length === 2, "opencode-go should have 2 windows");

        aiTab.activeProviderIndex = 2;
        assert(aiTab.currentProvider.provider_id === "minimax-cn", "Switching activeProviderIndex to 2 should select minimax-cn");

        // Switch back to gemini
        aiTab.activeProviderIndex = 0;
        assert(aiTab.currentProvider.provider_id === "gemini", "Switching back to gemini");

        // 5. Account switching / selection
        assert(aiTab.activeAccount !== null, "activeAccount should be resolved");
        assert(aiTab.activeAccount.identity === "hongbo.lu.fr@gmail.com", "Active account should be hongbo.lu.fr@gmail.com");

        aiTab.selectedAccountIdentity = "gitawego@gmail.com";
        assert(aiTab.selectedAccount !== null, "selectedAccount should be resolved");
        assert(aiTab.selectedAccount.identity === "gitawego@gmail.com", "selectedAccount should be gitawego@gmail.com");

        // 6. Reset time formatting function
        assert(aiTab.formatResetTime("in 2 hours") === "in 2 hours", "formatResetTime should preserve literal 'in 2 hours'");
        let futureIso = new Date(Date.now() + 7200 * 1000).toISOString();
        let formattedIso = aiTab.formatResetTime(futureIso);
        assert(formattedIso.indexOf("Resets in") !== -1, "formatResetTime should format ISO string, got: " + formattedIso);

        // 7. CentralDropdown 5-tab registration
        assert(dropdown !== null, "CentralDropdown must instantiate");
        assert(dropdown.tabs.length === 5, "CentralDropdown tabs must contain exactly 5 tabs, got: " + dropdown.tabs.length);
        assert(dropdown.tabs[4].id === "ai", "CentralDropdown 5th tab must be 'ai', got: " + dropdown.tabs[4].id);
        assert(dropdown.tabs[4].label === "AI Quotas", "CentralDropdown 5th tab label must be 'AI Quotas'");

        // 8. Tab repeater item count
        let repeater = dropdown.tabRepeaterItem;
        assert(repeater !== undefined && repeater !== null, "CentralDropdown must expose tabRepeaterItem");
        assert(repeater.count === 5, "tabRepeater count must be 5, got: " + repeater.count);

        // 9. Tab sliding indicator activeIdx mapping
        let slidingIndicator = dropdown.tabSlidingIndicatorItem;
        assert(slidingIndicator !== undefined && slidingIndicator !== null, "CentralDropdown must expose tabSlidingIndicatorItem");

        dropdown.activeTab = "ai";
        assert(slidingIndicator.activeIdx === 4, "tabSlidingIndicator activeIdx should be 4 when activeTab is 'ai', got: " + slidingIndicator.activeIdx);

        dropdown.activeTab = "dashboard";
        assert(slidingIndicator.activeIdx === 0, "tabSlidingIndicator activeIdx should be 0 when activeTab is 'dashboard', got: " + slidingIndicator.activeIdx);

        dropdown.activeTab = "media";
        assert(slidingIndicator.activeIdx === 1, "tabSlidingIndicator activeIdx should be 1 when activeTab is 'media', got: " + slidingIndicator.activeIdx);

        dropdown.activeTab = "performance";
        assert(slidingIndicator.activeIdx === 2, "tabSlidingIndicator activeIdx should be 2 when activeTab is 'performance', got: " + slidingIndicator.activeIdx);

        dropdown.activeTab = "workspaces";
        assert(slidingIndicator.activeIdx === 3, "tabSlidingIndicator activeIdx should be 3 when activeTab is 'workspaces', got: " + slidingIndicator.activeIdx);

        // 10. Cache hit rate format token count helper
        assert(typeof aiTab.formatTokenCount === "function", "aiTab.formatTokenCount must be a function");
        assert(aiTab.formatTokenCount(120000000) === "120.0M", "formatTokenCount 120M");
        assert(aiTab.formatTokenCount(1500000000) === "1.5B", "formatTokenCount 1.5B");
        assert(aiTab.formatTokenCount(5000) === "5.0k", "formatTokenCount 5k");
        assert(aiTab.formatTokenCount(42) === "42", "formatTokenCount 42");

        console.log("PASS: All AiTab & CentralDropdown 5-Tab Unit Tests passed successfully!");
        Qt.exit(0);
    }
}
