import QtQuick
import QtQuick.Layouts
import "../components"
import "../theme"
import "../config"
import "../shell"
import "../dashboard/tabs"

// ============================================================================
// CentralDropdown Tab Switching Tests (regression: "switching a tab stays on
// the Dashboard pane")
// ============================================================================
// Root cause guarded here: the tabSlider Item lost
//   x: -tabContentContainer.activeTabIndex * tabContentContainer.width
//   height: parent.height
// while the Downloads tab was added, so the content strip stayed parked at
// x = 0 (Dashboard) no matter which header cell was clicked.
//
// The suite clicks the real header MouseArea of every tab, waits for the
// spatial slide to settle, then asserts:
//   1. the content strip x equals -index * viewport width (content swapped),
//   2. only the active pane is visible,
//   3. panes are laid out at index * viewport width,
//   4. the sliding indicator + Config.activeDashboardTab agree,
//   5. dashboard/CentralDashboard.qml keeps its TabBar ↔ Config wiring.
Item {
    id: testRoot
    width: 1280
    height: 900

    CentralDropdown {
        id: dropdown
        dropX: 150
        dropW: 980
        visible: true
    }

    // Every icon the dropdown header (and the Downloads tab) depends on must
    // resolve in MaterialIcon, or the surface renders with blank glyphs.
    MaterialIcon {
        id: iconProbe
        visible: false
        size: 16
    }

    readonly property var downloadsTabIcons: [
        "download", "cloud_download", "link", "folder", "add", "remove",
        "refresh", "delete", "error", "check_circle", "close", "pause",
        "play_arrow", "task_alt", "content_paste", "select_all", "delete_sweep"
    ]

    readonly property var tabIds: ["dashboard", "media", "performance", "workspaces", "downloads", "ai"]
    // Start on a non-dashboard tab so the regression cannot hide behind the
    // trivially-correct index 0 position.
    readonly property var tabOrder: [1, 2, 3, 4, 5, 0]
    property int step: 0
    property int maxSteps: 0
    property var pendingCheck: null

    Timer {
        interval: 80
        running: true
        repeat: false
        onTriggered: begin()
    }

    // Poll until the slider's spatial animation settles (or times out).
    Timer {
        id: settleTimer
        interval: 40
        repeat: true
        property int ticks: 0

        onTriggered: {
            const slider = dropdown.tabSliderItem;
            ticks++;
            const settled = (!slider.isAnimating) || ticks > 75;
            if (!settled)
                return;
            stop();
            const cb = testRoot.pendingCheck;
            testRoot.pendingCheck = null;
            cb(ticks > 75 && slider.isAnimating);
        }
    }

    function assert(cond, msg) {
        if (!cond) {
            console.error("FAIL: " + msg);
            console.log("FAIL: " + msg);
            Qt.exit(1);
            throw new Error(msg);
        }
        return true;
    }

    function readLocalFile(relUrl) {
        const xhr = new XMLHttpRequest();
        const bust = (relUrl.indexOf("?") < 0 ? "?v=" : "&v=") + Date.now() + Math.random();
        xhr.open("GET", Qt.resolvedUrl(relUrl) + bust, false);
        xhr.send();
        return xhr.responseText || "";
    }

    // The click target of a tab cell is its MouseArea (hoverEnabled is the
    // only stable marker without importing private test hooks).
    function findClickArea(item) {
        if (!item || !item.children)
            return null;
        for (let i = 0; i < item.children.length; i++) {
            const c = item.children[i];
            if (c.hoverEnabled !== undefined)
                return c;
            const nested = findClickArea(c);
            if (nested !== null)
                return nested;
        }
        return null;
    }

    function checkTab(index) {
        const slider = dropdown.tabSliderItem;
        const container = dropdown.tabContentContainerItem;
        const expectedId = testRoot.tabIds[index];
        const panes = slider.children;
        const expectedX = -index * container.width;

        // The root-cause assertion: the content strip must actually move.
        assert(Math.abs(slider.x - expectedX) <= 1.0,
            "content strip x must be " + expectedX + " for tab '" + expectedId + "', got " + slider.x
                + " (dashboard content would stay parked at 0)");

        assert(dropdown.activeTab === expectedId,
            "clicking tab " + index + " must activate '" + expectedId + "', got '" + dropdown.activeTab + "'");
        assert(dropdown.tabSlidingIndicatorItem.activeIdx === index,
            "sliding indicator must point at tab " + index + ", got " + dropdown.tabSlidingIndicatorItem.activeIdx);

        for (let j = 0; j < panes.length; j++) {
            assert(Math.abs(panes[j].x - j * container.width) <= 1.0,
                "pane " + j + " must sit at x=" + (j * container.width) + ", got " + panes[j].x);
            assert(panes[j].visible === (j === index),
                "pane " + j + " visibility must be " + (j === index) + " with tab " + index + " active, got " + panes[j].visible);
        }
    }

    function nextTab() {
        if (testRoot.step >= testRoot.tabIds.length) {
            // Height contract (checked after the slides, so the slide failure
            // cannot hide behind it).
            assert(dropdown.tabSliderItem.height === dropdown.tabContentContainerItem.height
                    && dropdown.tabSliderItem.height > 50,
                "content strip must fill the viewport height, got " + dropdown.tabSliderItem.height
                    + " vs " + dropdown.tabContentContainerItem.height);

            // ---- Icon resolution: blank glyphs are invisible regressions ----
            for (let i = 0; i < dropdown.tabs.length; i++) {
                iconProbe.text = dropdown.tabs[i].icon;
                assert(iconProbe.hasIcon === true,
                    "dropdown tab icon '" + dropdown.tabs[i].icon + "' must resolve to a glyph");
            }
            for (let i = 0; i < testRoot.downloadsTabIcons.length; i++) {
                iconProbe.text = testRoot.downloadsTabIcons[i];
                assert(iconProbe.hasIcon === true,
                    "DownloadsTab icon '" + testRoot.downloadsTabIcons[i] + "' must resolve to a glyph");
            }

            // ---- Source contract: tab selection persists to Config on both
            // surfaces (Config is not a live singleton under the plain qml
            // runner, so the wiring is pinned at the source level).
            const dropdownSrc = readLocalFile("../shell/CentralDropdown.qml");
            assert(/x:\s*-tabContentContainer\.activeTabIndex \* tabContentContainer\.width/.test(dropdownSrc),
                "CentralDropdown content strip must bind x to the active tab index (root cause guard)");
            assert(/Config\.activeDashboardTab\s*=\s*modelData\.id/.test(dropdownSrc),
                "CentralDropdown tab clicks must persist to Config.activeDashboardTab");

            const standalone = readLocalFile("../dashboard/CentralDashboard.qml");
            // The bar shows the tab the user selected, unless that tab cannot be
            // rendered here (disabled in settings, or the engine-dependent
            // Downloads tab without aria2): a bar pointing at a tab it does not
            // render, or a loader showing content with no chip to return from, is
            // the bug the fallback exists for.
            assert(/activeTab:\s*root\.shownTab/.test(standalone),
                "CentralDashboard TabBar must bind activeTab to the policy's shown tab");
            assert(/shownTab:\s*DashboardTabs\.fallbackActiveTab\([\s\S]{0,200}Config\.activeDashboardTab\)/.test(standalone),
                "the shown tab must be the selected one when it is available, else the first");
            assert(/DashboardTabs\.availableTabs\(Config\.dashboardTabs/.test(standalone),
                "the rendered tabs must come from the settings, minus the unavailable ones");
            assert(/onTabSelected/.test(standalone) && /Config\.activeDashboardTab\s*=/.test(standalone),
                "CentralDashboard TabBar must persist tab selections to Config.activeDashboardTab");

            const cfgSrc = readLocalFile("../config/Config.qml");
            assert(!/onSettingsChanged:\s*\{[^}]*activeDashboardTab\s*=/.test(cfgSrc),
                "Config.qml must never clobber activeDashboardTab on settingsChanged");

            console.log("PASS: CentralDropdown tab switching moves content for all "
                + testRoot.tabIds.length + " tabs!");
            Qt.exit(0);
            return;
        }

        const index = testRoot.tabOrder[testRoot.step];
        const cell = dropdown.tabRepeaterItem.itemAt(index);
        assert(cell !== null && cell !== undefined, "tab cell " + index + " must exist");

        const clickArea = findClickArea(cell);
        assert(clickArea !== null, "tab cell " + index + " must expose a click area");
        clickArea.clicked(null);

        testRoot.pendingCheck = function(timedOut) {
            assert(!timedOut, "tab " + index + " content slide must settle (never parked off animation)");
            checkTab(index);
            testRoot.step++;
            nextTab();
        };
        settleTimer.ticks = 0;
        settleTimer.start();
    }

    function begin() {
        const slider = dropdown.tabSliderItem;
        const container = dropdown.tabContentContainerItem;
        assert(dropdown !== null, "CentralDropdown must instantiate");
        assert(slider !== undefined && slider !== null, "CentralDropdown must expose tabSliderItem");
        assert(container !== undefined && container !== null, "CentralDropdown must expose tabContentContainerItem");
        assert(slider.children.length === dropdown.tabs.length,
            "content strip must host one pane per tab, got " + slider.children.length + " for " + dropdown.tabs.length + " tabs");

        nextTab();
    }
}
