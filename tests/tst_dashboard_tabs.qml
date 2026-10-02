import QtQuick
import "../dashboard/tabs/DashboardTabs.js" as Tabs

// ============================================================================
// Dashboard tab policy
// ============================================================================
// Which tabs the central dashboard shows is a setting, and one of those tabs has
// a dependency: the Downloads tab is useless without the aria2 engine, so it is
// not shown on a machine that does not have it - and the settings page refuses to
// switch it on, offering to install the engine instead of silently doing nothing.
//
// The policy is pure (`dashboard/tabs/DashboardTabs.js`), so it is asserted here
// without a session, and the wiring is asserted against the real sources so the
// dashboard cannot drift back to a hardcoded tab list.
Item {
    id: testRoot
    width: 800
    height: 600

    readonly property var allTabs: [
        { id: "dashboard", label: "Dashboard", icon: "dashboard", enabled: true },
        { id: "media", label: "Media", icon: "media", enabled: true },
        { id: "performance", label: "Performance", icon: "performance", enabled: false },
        { id: "workspaces", label: "Workspaces", icon: "workspaces", enabled: true },
        { id: "downloads", label: "Downloads", icon: "download", enabled: true },
        { id: "ai", label: "AI Quotas", icon: "auto_awesome", enabled: true }
    ]

    function readLocalFile(relUrl) {
        const xhr = new XMLHttpRequest();
        const bust = (relUrl.indexOf("?") < 0 ? "?v=" : "&v=") + Date.now() + Math.random();
        xhr.open("GET", Qt.resolvedUrl(relUrl) + bust, false);
        xhr.send();
        return xhr.responseText || "";
    }

    function assert(condition, message) {
        if (!condition) {
            console.error("FAIL: " + message);
            Qt.exit(1);
            throw new Error(message);
        }
    }

    function ids(tabs) {
        return tabs.map(t => t.id).join(",");
    }

    Timer {
        interval: 50
        running: true
        repeat: false
        onTriggered: runTests()
    }

    function runTests() {
        console.log("RUNNING: Dashboard Tab Policy");

        // ------------------------------------------------------------------
        // A disabled setting hides the tab; a missing flag means "on"
        // ------------------------------------------------------------------
        assert(Tabs.enabledTabs(testRoot.allTabs).length === 5,
            "a disabled tab is dropped: " + ids(Tabs.enabledTabs(testRoot.allTabs)));
        assert(ids(Tabs.enabledTabs(testRoot.allTabs)).indexOf("performance") < 0,
            "the disabled tab is the one that disappears");
        assert(Tabs.enabledTabs([{ id: "media" }]).length === 1,
            "a tab without an explicit flag counts as enabled");

        // ------------------------------------------------------------------
        // The engine dependency: no aria2, no Downloads tab
        // ------------------------------------------------------------------
        const withEngine = Tabs.availableTabs(Tabs.enabledTabs(testRoot.allTabs), true);
        assert(ids(withEngine).indexOf("downloads") >= 0,
            "with the engine the Downloads tab is available: " + ids(withEngine));

        const withoutEngine = Tabs.availableTabs(Tabs.enabledTabs(testRoot.allTabs), false);
        assert(ids(withoutEngine).indexOf("downloads") < 0,
            "without the engine the Downloads tab is hidden even when enabled: " + ids(withoutEngine));
        assert(ids(withoutEngine).indexOf("media") >= 0 && ids(withoutEngine).indexOf("ai") >= 0,
            "only the engine-dependent tab is affected: " + ids(withoutEngine));
        assert(withoutEngine.length === withEngine.length - 1,
            "exactly one tab depends on the engine");

        // ------------------------------------------------------------------
        // Enabling it without the engine is refused, with a reason
        // ------------------------------------------------------------------
        assert(Tabs.enableBlockedReason("downloads", false) === "aria-missing",
            "enabling Downloads without aria2 must report why");
        assert(Tabs.enableBlockedReason("downloads", true) === null,
            "with the engine the toggle is free");
        assert(Tabs.enableBlockedReason("media", false) === null
                && Tabs.enableBlockedReason("workspaces", false) === null
                && Tabs.enableBlockedReason("ai", false) === null,
            "no other tab is gated on the engine");

        // ------------------------------------------------------------------
        // The selected tab can disappear underneath the user
        // ------------------------------------------------------------------
        assert(Tabs.fallbackActiveTab(withoutEngine, "downloads") === "dashboard",
            "a hidden active tab falls back to the first available one");
        assert(Tabs.fallbackActiveTab(withEngine, "downloads") === "downloads",
            "a visible active tab is kept");
        assert(Tabs.fallbackActiveTab([], "downloads") === "dashboard",
            "an empty tab list still names a tab");

        // ------------------------------------------------------------------
        // Migration: a stored list grows with the build's new tabs
        // ------------------------------------------------------------------
        const shipped6 = testRoot.allTabs;
        const storedOld = [
            { id: "dashboard", label: "Dashboard", enabled: true },
            { id: "media", label: "Media", enabled: false },
            { id: "workspaces", label: "Workspaces", enabled: true }
        ];
        const reconciled = Tabs.reconcileTabs(storedOld, shipped6);
        assert(reconciled.length === shipped6.length,
            "every shipped tab is present after reconciling, got " + ids(reconciled));
        assert(ids(reconciled).indexOf("downloads") >= 0 && ids(reconciled).indexOf("ai") >= 0,
            "tabs added by a newer build are appended: " + ids(reconciled));
        assert(reconciled.filter(t => t.id === "media")[0].enabled === false,
            "the user's own off choice survives");
        assert(reconciled.filter(t => t.id === "downloads")[0].enabled === true,
            "an appended tab takes the shipped default");
        assert(reconciled[0].id === "dashboard" && reconciled[1].id === "media",
            "the user's order wins: " + ids(reconciled));
        assert(Tabs.reconcileTabs([{ id: "my-own-tab", label: "Custom" }], shipped6).filter(t => t.id === "my-own-tab").length === 1,
            "a tab this build does not ship is kept, not dropped");
        assert(Tabs.reconcileTabs(null, shipped6).length === shipped6.length,
            "no stored list = the shipped list");

        // ------------------------------------------------------------------
        // Wiring: settings own the list, the dashboard consumes the policy
        // ------------------------------------------------------------------
        const shipped = JSON.parse(readLocalFile("../config/settings.json"));
        const shippedIds = (shipped.dashboard.tabs || []).map(t => t.id);
        for (const expected of ["dashboard", "media", "performance", "workspaces", "downloads", "ai"]) {
            assert(shippedIds.indexOf(expected) >= 0,
                "every rendered tab must be configurable: " + expected + " missing from " + shippedIds);
        }
        assert(shipped.dashboard.tabs.filter(t => t.id === "downloads")[0].enabled === true,
            "the shipped default is on, and the engine decides whether it applies");
        assert(shipped.downloads && shipped.downloads.maxConcurrentDownloads !== undefined
                && shipped.downloads.speedLimitKbps !== undefined,
            "the engine settings must ship with defaults");

        const config = readLocalFile("../config/Config.qml");
        assert(config.indexOf("DashboardTabs.reconcileTabs(") >= 0,
            "Config must reconcile the stored tab list with the shipped one");
        assert(config.indexOf("readonly property var dashboardTabs") >= 0,
            "Config must expose the enabled tab list");
        assert(config.indexOf("function setDownloadsMaxConcurrent(") >= 0
                && config.indexOf("function setDownloadsSpeedLimit(") >= 0,
            "Config must accept the engine settings");
        assert(config.indexOf("function setDashboardTabEnabled(") >= 0,
            "the existing tab setter stays the one write path");

        // Both dashboard views: shell/CentralDropdown is what the shell
        // instantiates (the top drawer), dashboard/CentralDashboard is the
        // standalone variant. A hardcoded list in either would silently ignore
        // the setting and the engine state.
        for (const view of ["../shell/CentralDropdown.qml", "../dashboard/CentralDashboard.qml"]) {
            const src = readLocalFile(view);
            assert(src.indexOf("DashboardTabs.js") >= 0,
                view + " must use the tab policy module");
            assert(/availableTabs\(Config\.dashboardTabs, root\.ariaAvailable\)/.test(src),
                view + " must render Config's tab list filtered by the engine state");
            assert(src.indexOf('{ id: "downloads", label: "Downloads"') < 0,
                view + " must not hardcode the tab list");
            assert(src.indexOf("fallbackActiveTab(") >= 0,
                view + " must fall back when the selected tab is not rendered");
        }

        const page = readLocalFile("../settings_gui/pages/DashboardPage.qml");
        assert(page.indexOf("enableBlockedReason(") >= 0,
            "the settings page must refuse to enable a tab whose engine is missing");
        assert(page.indexOf("DownloadsGateCard") >= 0 || page.indexOf("aria2") >= 0,
            "and it must offer the install path instead of failing silently");
        // The gate decision is nullable, so it must not be held in a `string`
        // property: QML coerces a JS null to "", and `"" !== null` is true -
        // every tab then renders as blocked (this shipped once, on all of them).
        assert(/readonly property var gateReason/.test(page),
            "the gate reason must be typed `var` so `null` (no reason) survives");

        console.log("PASS: Dashboard Tab Policy");
        Qt.exit(0);
    }
}
