import QtQuick
import "../settings_gui/pages"
import "../settings_gui/controls"
import "../dashboard/tabs/DashboardTabs.js" as Tabs

// ============================================================================
// Downloads settings + the tab gate
// ============================================================================
// Two things have to hold:
//
//   1. the engine settings are configurable from one page (destination,
//      connections, parallelism, speed cap, border HUD) and every field has a
//      single write path that can be asserted without Config;
//   2. the dashboard's Downloads tab cannot be switched on without the engine -
//      the attempt is refused and answered with the reason plus both ways to get
//      aria2 (the system password dialog, or the manual command).
Item {
    id: testRoot
    width: 900
    height: 700

    // Engine present (the ordinary case).
    DownloadsPage {
        id: pageWithEngine
        testMode: true
        testAriaAvailable: true
        testAriaVersion: "1.37.0"
    }

    // Engine missing, native install available.
    DownloadsPage {
        id: pageMissingEngine
        testMode: true
        testAriaAvailable: false
        testAriaVersion: ""
        testAriaInstallable: true
        testAriaInstallCommand: "sudo pacman -S aria2"
    }

    // Engine missing and no authentication dialog on this system.
    DownloadsPage {
        id: pageNoPrompt
        testMode: true
        testAriaAvailable: false
        testAriaVersion: ""
        testAriaInstallable: false
        testAriaInstallCommand: "sudo apt install aria2"
    }

    // The refusal card, on its own (what the dashboard page shows).
    DownloadsGateCard {
        id: gateCard
        message: "aria2 is not installed, so the Downloads tab stays hidden."
        installable: true
        installCommand: "sudo pacman -S aria2"
    }

    // The coercion the page must not rely on: a `string` property turns the
    // policy's JS `null` into "", which reads as "blocked".
    Item {
        id: coercionProbe
        readonly property var reasonVar: Tabs.enableBlockedReason("workspaces", false)
        readonly property string reasonString: Tabs.enableBlockedReason("workspaces", false)
        readonly property bool blockedWhenVar: reasonVar !== null
        readonly property bool blockedWhenString: reasonString !== null
    }

    DashboardPage {
        id: tabsPage
        testMode: true
        testAriaAvailable: false
        testAriaInstallable: true
        testAriaInstallCommand: "sudo pacman -S aria2"
    }

    function assert(condition, message) {
        if (!condition) {
            console.error("FAIL: " + message);
            Qt.exit(1);
            throw new Error(message);
        }
    }

    Timer {
        interval: 50
        running: true
        repeat: false
        onTriggered: runTests()
    }

    function runTests() {
        console.log("RUNNING: Downloads Settings & Tab Gate");

        // ------------------------------------------------------------------
        // Engine status is visible, not inferred
        // ------------------------------------------------------------------
        assert(pageWithEngine.engineStatusItem.text.indexOf("1.37.0") >= 0,
            "a detected engine shows its version, got: " + pageWithEngine.engineStatusItem.text);
        assert(pageWithEngine.installButtonItem.visible === false,
            "nothing to install when the engine is there");
        assert(pageWithEngine.tabHintItem.visible === false,
            "no hidden-tab warning while the tab works");

        assert(pageMissingEngine.engineStatusItem.text.indexOf("not installed") >= 0,
            "a missing engine says so, got: " + pageMissingEngine.engineStatusItem.text);
        assert(pageMissingEngine.installButtonItem.visible === true,
            "the missing engine offers the install action");
        assert(pageMissingEngine.installButtonItem.label === "Install aria2",
            "the install action names the engine, got: " + pageMissingEngine.installButtonItem.label);
        assert(pageMissingEngine.engineHintItem.visible === true,
            "the hint explains what aria2 is for");
        assert(pageMissingEngine.engineHintItem.text.indexOf("password") >= 0,
            "the native flow is described as a password dialog, got: " + pageMissingEngine.engineHintItem.text);
        assert(pageMissingEngine.tabHintItem.visible === true,
            "the page says the dashboard tab stays hidden without the engine");

        // Without an authentication dialog the button must not promise one.
        assert(pageNoPrompt.installButtonItem.label === "Copy install command",
            "no polkit = guide instead of prompt, got: " + pageNoPrompt.installButtonItem.label);
        assert(pageNoPrompt.engineHintItem.text.indexOf("sudo apt install aria2") >= 0,
            "the manual command is spelled out, got: " + pageNoPrompt.engineHintItem.text);

        // The actions route to the daemon (counted in testMode).
        pageMissingEngine.installEngine();
        assert(pageMissingEngine.installRequests === 1, "Install runs the daemon's install flow");
        pageNoPrompt.copyInstallCommand();
        assert(pageNoPrompt.copyRequests === 1, "Copy puts the command on the clipboard");

        // ------------------------------------------------------------------
        // Every setting has one write path with clamped input
        // ------------------------------------------------------------------
        pageWithEngine.chooseDir("/data/downloads");
        assert(pageWithEngine.testDir === "/data/downloads", "the folder is written");
        pageWithEngine.applyParallelDownloads(9);
        assert(pageWithEngine.testMaxConcurrent === 9, "parallel downloads are written");
        pageWithEngine.applyParallelDownloads(99);
        assert(pageWithEngine.testMaxConcurrent === 16, "parallel downloads are clamped to the engine's range");
        pageWithEngine.applyParallelDownloads(0);
        assert(pageWithEngine.testMaxConcurrent === 1, "zero parallel downloads is not allowed");
        pageWithEngine.applySplit(8);
        assert(pageWithEngine.testSplit === 8, "connections per download are written");
        pageWithEngine.applySpeedLimit(1234);
        assert(pageWithEngine.testSpeedLimit === 1200, "the cap is rounded to a step the engine can honour");
        pageWithEngine.applySpeedLimit(-5);
        assert(pageWithEngine.testSpeedLimit === 0, "a negative cap means unlimited");
        pageWithEngine.setBorderEffect(false);
        assert(pageWithEngine.testBorderEffect === false, "the border HUD toggle is written");

        assert(pageWithEngine.speedLimitText(0) === "Unlimited", "0 reads as unlimited");
        assert(pageWithEngine.speedLimitText(2500).indexOf("MiB/s") >= 0,
            "a cap reads in units a human uses, got: " + pageWithEngine.speedLimitText(2500));

        // ------------------------------------------------------------------
        // The tab gate: refused, explained, and never silently dropped
        // ------------------------------------------------------------------
        assert(tabsPage.tabGateReason("downloads") === "aria-missing",
            "the Downloads tab reports why it cannot be enabled");
        assert(tabsPage.tabGateReason("media") === null,
            "no other tab is gated");
        // Named explicitly: the gate is decided by the tab's *identity*, so a
        // rendering that shows the engine reason on any other tab is wrong.
        assert(tabsPage.tabGateReason("workspaces") === null
                && tabsPage.tabGateReason("performance") === null
                && tabsPage.tabGateReason("dashboard") === null
                && tabsPage.tabGateReason("ai") === null,
            "only the Downloads tab can be gated on the engine");

        assert(tabsPage.requestTabEnabled("downloads", true) === false,
            "enabling Downloads without aria2 is refused");
        assert(tabsPage.lastRefusedTabId === "downloads",
            "the refusal is reported (the page renders the card from it)");
        assert(tabsPage.requestTabEnabled("downloads", false) === true,
            "disabling it is always allowed");
        assert(tabsPage.requestTabEnabled("media", true) === true,
            "unrelated tabs still toggle");
        assert(tabsPage.ariaMissing === true, "the page knows the engine is missing");

        // The card itself: explanation, install action, manual fallback.
        gateCard.installRequested();
        gateCard.copyRequested();
        assert(gateCard.messageTextItem.text.indexOf("aria2") >= 0, "the card names the missing engine");
        assert(gateCard.installButtonItem.label === "Install aria2", "the card offers the native install");
        assert(gateCard.commandTextItem.text === "sudo pacman -S aria2",
            "the card shows the command to run, got: " + gateCard.commandTextItem.text);
        gateCard.installable = false;
        assert(gateCard.installButtonItem.visible === false,
            "without a dialog the card only offers the command");

        // ------------------------------------------------------------------
        // The nullable reason survives only in a `var` property
        // ------------------------------------------------------------------
        assert(coercionProbe.reasonVar === null && coercionProbe.blockedWhenVar === false,
            "a var-typed reason keeps `null` = not blocked");
        assert(coercionProbe.blockedWhenString === true,
            "a string-typed reason would report every tab as blocked (the trap)");

        console.log("PASS: Downloads Settings & Tab Gate");
        Qt.exit(0);
    }
}
