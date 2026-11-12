import QtQuick
import "../settings_gui"

// ============================================================================
// Settings hub: sections scroll, tabs switch
// ============================================================================
// The hub owns the page frame, the sticky header, and the deep-link entry point.
// A page chooses its shape:
//
//   * sections: a vertical stack; a deep link scrolls to the named anchor;
//   * tabs: only for a page that runs several viewports; a deep link selects the
//     named tab and leaves the viewport at the top.
//
// This test drives the real hub and presses the rendered tabs, so a tab that
// looks right but is a dead control fails here.
Item {
    id: testRoot
    width: 1000
    height: 560

    NexusHub {
        id: hub
        width: parent.width
        height: parent.height
        testMode: true
    }

    property int step: 0

    Timer {
        interval: 300
        running: true
        repeat: true
        onTriggered: testRoot.advance()
    }

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
        case 0: {
            console.log("RUNNING: Settings Hub Sections & Tabs");

            // ------------------------------------------------------------------
            // A short page is sections, not tabs
            // ------------------------------------------------------------------
            assert(hub.activePage === "wallpaper", "the hub opens on the wallpaper page");
            const page = hub.pageItem;
            assert(page && page.hasTabs === false,
                "the wallpaper page is a sections page");
            assert(page.zones.length === 4,
                "the wallpaper page names its four section anchors");

            // A short viewport makes the section jump observable.
            hub.height = 300;
            hub.scrollToSection("palette");
            break;
        }
        case 1:
            // Let the deferred anchor recompute land.
            break;
        case 2: {
            const page = hub.pageItem;
            assert(hub.contentMaxOffset > 0,
                "the wallpaper page is tall enough to scroll at this viewport");
            assert(page.currentSection === "palette",
                "the palette deep link is the current section (got \"" + page.currentSection + "\")");
            assert(hub.contentOffset > 0,
                "the palette deep link scrolled the page (offset " + hub.contentOffset + ")");

            hub.height = 560;
            hub.activePage = "system";
            break;
        }
        case 3:
            // Let the system page settle into its layout.
            break;
        case 4: {
            // ------------------------------------------------------------------
            // A long page is tabs, and a deep link selects the tab
            // ------------------------------------------------------------------
            const page = hub.pageItem;
            assert(page && page.hasTabs === true,
                "the system page is a tabs page");
            assert(page.tabs.length === 5,
                "the system page names its five tabs");
            assert(page.currentTab === "services", "system opens on Services");

            hub.scrollToSection("developer");
            assert(page.currentTab === "developer", "a deep link selects Developer");
            assert(hub.contentOffset === 0, "a tab selection does not scroll");

            hub.height = 300;
            hub.activePage = "ai";
            break;
        }
        case 5:
            // Let the AI page settle into its layout.
            break;
        case 6: {
            const page = hub.pageItem;
            assert(page && page.hasTabs === true, "the AI page is a tabs page");
            assert(page.tabs.length === 3, "the AI page names its three tabs");
            assert(page.currentTab === "quotas", "AI opens on Quotas");

            hub.scrollToSection("voice");
            assert(page.currentTab === "setup", "the legacy voice deep link selects Setup");
            assert(hub.contentOffset === 0, "the legacy deep link does not scroll");

            hub.height = 560;
            hub.activePage = "skills";
            break;
        }
        case 7:
            // Let the skills page settle into its layout.
            break;
        case 8: {
            const page = hub.pageItem;
            assert(page && page.hasTabs === true, "the skills page is a tabs page");
            assert(page.currentTab === "find", "skills opens on Find");
            hub.scrollToSection("mcp");
            assert(page.currentTab === "mcp", "the MCP deep link selects its tab");
            testRoot.pressTab("Installed");
            assert(page.currentTab === "installed", "the rendered Installed tab swaps the body");

            // ------------------------------------------------------------------
            // The hub has both routes, and chooses by the page's shape
            // ------------------------------------------------------------------
            const hubSource = testRoot.readLocalFile("../settings_gui/NexusHub.qml");
            assert(hubSource.indexOf("page.selectTab(zoneId)") >= 0,
                "the hub's deep-link path selects a tab");
            assert(hubSource.indexOf("page.hasTabs") >= 0,
                "the hub recognizes a tabs page");
            assert(hubSource.indexOf("page.sectionY(zoneId)") >= 0,
                "the hub's deep-link path scrolls a sections page");
            assert(hubSource.indexOf("stickyHeaderLoader") >= 0,
                "the hub still pins the page header outside the flickable");

            console.log("PASS: Settings Hub Sections & Tabs");
            Qt.exit(0);
            break;
        }
        default:
            break;
        }
    }
}
