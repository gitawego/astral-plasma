// ============================================================================
// Settings hub: Atlas tab navigation
// ============================================================================
// The hub owns the page frame, the sticky header, and the deep-link entry point.
// Atlas changed what "go to a section" means: a section is a tab, so a deep link
// selects it instead of scrolling the reader to an anchor.

import "../settings_gui"
import QtQuick

// This test drives the real hub and presses the rendered tabs - not a page
// function and not a scroll offset - so a tab that looks right but is a dead
// control fails here.
Item {
    id: testRoot

    property int step: 0

    function assert(condition, message) {
        if (!condition) {
            console.error("FAIL: " + message);
            Qt.exit(1);
            throw new Error(message);
        }
    }

    /// The rendered tab with this label, wherever it sits in the hub's tree.
    function findTab(item, label) {
        if (!item || item.children === undefined)
            return null;

        for (let i = 0; i < item.children.length; ++i) {
            const child = item.children[i];
            if (child.label === label && typeof child.clicked === "function")
                return child;

            const nested = findTab(child, label);
            if (nested)
                return nested;

        }
        return null;
    }

    function readLocalFile(relUrl) {
        const xhr = new XMLHttpRequest();
        const bust = (relUrl.indexOf("?") < 0 ? "?v=" : "&v=") + Date.now() + Math.random();
        xhr.open("GET", Qt.resolvedUrl(relUrl) + bust, false);
        xhr.send();
        return xhr.responseText || "";
    }

    function pressTab(label) {
        const tab = testRoot.findTab(hub.contentPaneItem, label);
        assert(tab !== null, "the page renders a tab labelled \"" + label + "\"");
        tab.clicked();
    }

    function advance() {
        switch (testRoot.step++) {
        case 0:
            {
                console.log("RUNNING: Settings Hub Atlas Navigation");
                // ------------------------------------------------------------------
                // The default page is tabbed, not a scroll rail
                // ------------------------------------------------------------------
                assert(hub.activePage === "wallpaper", "the hub opens on the wallpaper page");
                const page = hub.pageItem;
                assert(page && page.hasTabs === true, "the wallpaper page declares Atlas tabs");
                assert(page.currentTab === "wallpaper", "the first tab is selected by default");
                assert(page.tabs.length === 4, "the wallpaper page names its four tabs");
                assert(hub.pageZones.length === 0, "an Atlas page declares no zones, so there is nothing to scroll-spy");
                // A deep link selects the tab it names.
                hub.scrollToSection("palette");
                assert(page.currentTab === "palette", "a deep link selects the palette tab");
                hub.scrollToSection("nonsense");
                assert(page.currentTab === "palette", "an unknown section leaves the tab alone");
                hub.activePage = "audio";
                break;
            };
        case 1:
            // Let the new page settle into its layout.
            break;
        case 2:
            {
                // ------------------------------------------------------------------
                // A tab press swaps the body; it never moves the view
                // ------------------------------------------------------------------
                const page = hub.pageItem;
                assert(page && page.hasTabs === true, "the audio page declares Atlas tabs");
                assert(page.currentTab === "output", "audio opens on Output");
                assert(page.tabs.length === 2, "audio names its two always-on tabs");
                testRoot.pressTab("Visualizer");
                assert(page.currentTab === "visualizer", "pressing Visualizer swaps the body");
                assert(hub.contentOffset === 0, "a tab press does not scroll the page");
                hub.activePage = "system";
                break;
            };
        case 3:
            // Let the new page settle into its layout.
            break;
        case 4:
            {
                const page = hub.pageItem;
                assert(page && page.hasTabs === true, "the system page declares Atlas tabs");
                assert(page.tabs.length === 5, "the system page names its five tabs");
                assert(page.currentTab === "services", "system opens on Services");
                testRoot.pressTab("Logging");
                assert(page.currentTab === "logging", "pressing Logging swaps the body");
                assert(hub.contentOffset === 0, "the body swap does not move the viewport");
                hub.scrollToSection("developer");
                assert(page.currentTab === "developer", "a deep link selects Developer");
                assert(hub.contentOffset === 0, "and still does not scroll");
                hub.activePage = "network";
                break;
            };
        case 5:
            // Let the new page settle into its layout.
            break;
        case 6:
            {
                const page = hub.pageItem;
                assert(page.currentTab === "wifi", "network opens on Wi-Fi");
                assert(page.tabs.length === 2, "network names both live tabs");
                hub.scrollToSection("networks");
                assert(page.currentTab === "networks", "the networks deep link selects its tab");
                // The AI page is the last page with a hand-written root. It must
                // still honour the same hub contract.
                hub.height = 300;
                hub.activePage = "ai";
                break;
            };
        case 7:
            // Let the AI page settle into its layout.
            break;
        case 8:
            {
                const page = hub.pageItem;
                assert(page && page.hasTabs === true, "the AI page declares Atlas tabs");
                assert(page.tabs.length === 3, "the AI page names its three tabs");
                assert(page.currentTab === "quotas", "AI opens on Quotas");
                hub.scrollToSection("voice");
                assert(page.currentTab === "setup", "the legacy voice deep link selects Setup");
                assert(hub.contentOffset === 0, "the legacy deep link does not scroll the page");
                hub.scrollToSection("providers");
                assert(page.currentTab === "quotas", "the providers deep link selects Quotas");
                testRoot.pressTab("Copilot");
                assert(page.currentTab === "copilot", "the rendered Copilot tab swaps the body");
                hub.height = 560;
                hub.activePage = "dock";
                break;
            };
        case 9:
            // Let the dock page settle into its layout.
            break;
        case 10:
            {
                const page = hub.pageItem;
                assert(page.currentTab === "dock", "dock opens on Dock");
                testRoot.pressTab("Tray");
                assert(page.currentTab === "tray", "the Tray tab swaps the body");
                testRoot.pressTab("Top Bar");
                assert(page.currentTab === "topbar", "the Top Bar tab swaps the body");
                hub.activePage = "skills";
                break;
            };
        case 11:
            // Let the skills page settle into its layout.
            break;
        case 12:
            {
                const page = hub.pageItem;
                assert(page && page.hasTabs === true, "the skills page declares Atlas tabs");
                assert(page.currentTab === "find", "skills opens on Find");
                hub.scrollToSection("mcp");
                assert(page.currentTab === "mcp", "the MCP deep link selects its tab");
                testRoot.pressTab("Installed");
                assert(page.currentTab === "installed", "the Installed tab swaps the body");
                hub.activePage = "downloads";
                break;
            };
        case 13:
            // Let the downloads page settle into its layout.
            break;
        case 14:
            {
                const page = hub.pageItem;
                assert(page.currentTab === "engine", "downloads opens on Engine");
                hub.scrollToSection("settings");
                assert(page.currentTab === "settings", "the settings deep link selects its tab");
                assert(hub.contentOffset === 0, "downloads stays at the top through a tab change");
                // ------------------------------------------------------------------
                // The hub routes sections through selectTab, not through scrollTo
                // ------------------------------------------------------------------
                const hubSource = testRoot.readLocalFile("../settings_gui/NexusHub.qml");
                assert(hubSource.indexOf("page.selectTab(zoneId)") >= 0, "the hub's deep-link path selects a tab");
                assert(hubSource.indexOf("page.hasTabs") >= 0, "the hub recognizes an Atlas page");
                assert(hubSource.indexOf("stickyHeaderLoader") >= 0, "the hub still pins the page header outside the flickable");
                console.log("PASS: Settings Hub Atlas Navigation");
                Qt.exit(0);
                break;
            };
        default:
            break;
        }
    }

    width: 1000
    height: 560

    NexusHub {
        id: hub

        width: parent.width
        height: parent.height
        testMode: true
    }

    Timer {
        interval: 300
        running: true
        repeat: true
        onTriggered: testRoot.advance()
    }

}
