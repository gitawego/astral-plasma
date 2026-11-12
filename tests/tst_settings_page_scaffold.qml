import QtQuick
import QtQuick.Layouts
import "../settings_gui/pages"

// ============================================================================
// Settings page scaffold
// ============================================================================
// The contract every settings page opts into. There are two shapes:
//
//   * **sections**: a vertical stack. `zones` names the anchors the hub scrolls
//     a deep link to; there is no in-page navigation strip.
//   * **tabs**: only for a page that genuinely runs several viewports. Tabs
//     switch the body; they never scroll the reader to an anchor.
//
// These assertions are the contract itself, so a page cannot half-adopt it.
Item {
    id: testRoot
    width: 900
    height: 700

    // A sections page with three anchors, at deliberately uneven offsets.
    SettingsPage {
        id: triPage
        width: 800
        title: "Network"
        subtitle: "Interfaces, addresses, and per-network preferences"
        zones: [
            { id: "status", label: "Status", anchor: statusAnchor },
            { id: "wifi", label: "Wi-Fi", anchor: wifiAnchor },
            { id: "advanced", label: "Advanced", anchor: advancedAnchor }
        ]

        ColumnLayout {
            width: parent.width
            spacing: 0

            Item {
                id: statusAnchor
                implicitHeight: 40
            }
            Item { implicitHeight: 260 }
            Item {
                id: wifiAnchor
                implicitHeight: 40
            }
            Item { implicitHeight: 120 }
            Item {
                id: advancedAnchor
                implicitHeight: 40
            }
        }
    }

    // A single-section page: a title and one body, no anchors needed.
    SettingsPage {
        id: singleZonePage
        width: 400
        title: "Sound"
        Item {
            id: outputsAnchor
            implicitHeight: 20
        }
    }

    // Tabs: switch the body; do not scroll to an anchor.
    SettingsPage {
        id: tabPage
        width: 800
        title: "Skills"
        icon: "extension"
        tabs: [
            { id: "find", label: "Find", icon: "search", component: findTab },
            { id: "mcp", label: "MCP server", icon: "lan", component: mcpTab }
        ]
        property Component findTab: Component {
            Item {
                objectName: "findTab"
                implicitHeight: 40
            }
        }
        property Component mcpTab: Component {
            Item {
                objectName: "mcpTab"
                implicitHeight: 40
            }
        }
    }

    function assert(condition, message) {
        if (!condition) {
            console.error("FAIL: " + message);
            Qt.exit(1);
            throw new Error(message);
        }
    }

    Timer {
        interval: 60
        running: true
        repeat: false
        onTriggered: runTests()
    }

    function runTests() {
        console.log("RUNNING: Settings Page Scaffold");

        // ------------------------------------------------------------------
        // Sections: anchors for deep links, no rail
        // ------------------------------------------------------------------
        assert(triPage.title === "Network" && triPage.subtitle !== "",
            "the page carries its identity");
        assert(triPage.hasTabs === false, "a sections page declares no tabs");
        assert(triPage.zones.length === 3, "three section anchors declared");

        const statusY = triPage.sectionY("status");
        const wifiY = triPage.sectionY("wifi");
        const advancedY = triPage.sectionY("advanced");
        assert(statusY !== undefined && wifiY !== undefined && advancedY !== undefined,
            "every declared section has an anchor");
        assert(statusY < wifiY && wifiY < advancedY,
            "sections resolve in document order (" + statusY + ", " + wifiY + ", " + advancedY + ")");
        assert(statusY === statusAnchor.mapToItem(triPage, 0, 0).y,
            "the anchor is mapped into page coordinates, not guessed");
        assert(triPage.sectionY("nonsense") === undefined,
            "an undeclared section has no anchor to scroll to");

        triPage.currentSection = "wifi";
        assert(triPage.currentSection === "wifi",
            "the hub can write the current section for its scroll-spy");

        // ------------------------------------------------------------------
        // A single section needs no anchor declaration at all
        // ------------------------------------------------------------------
        assert(singleZonePage.hasTabs === false,
            "a single-section page declares no tabs");
        assert(singleZonePage.zones.length === 0,
            "a single-section page declares no anchors");
        assert(singleZonePage.sectionY("outputs") === undefined,
            "and there is no scroll target to resolve");

        // ------------------------------------------------------------------
        // Tabs: switch the body
        // ------------------------------------------------------------------
        assert(tabPage.hasTabs === true && tabPage.hasTabComponents === true,
            "the page declares tabs and their components");
        assert(tabPage.zones.length === 0,
            "a tabs page declares no scroll anchors");
        assert(tabPage.currentTab === "find", "the first tab is selected by default");
        assert(tabPage.tabContentItem !== null
                && tabPage.tabContentItem.objectName === "findTab",
            "the body is the active tab's component");
        tabPage.selectTab("mcp");
        assert(tabPage.currentTab === "mcp", "selectTab changes the tab");
        assert(tabPage.tabContentItem !== null
                && tabPage.tabContentItem.objectName === "mcpTab",
            "selecting a tab swaps the body, not a scroll position");
        tabPage.selectTab("nonsense");
        assert(tabPage.currentTab === "mcp", "an unknown tab id is ignored");

        // ------------------------------------------------------------------
        // The scaffold's own contract
        // ------------------------------------------------------------------
        assert(triPage.stickyHeader !== null && typeof triPage.stickyHeader === "object",
            "the scaffold provides the sticky header");
        assert(typeof triPage.sectionY === "function",
            "the scaffold answers the hub's section question");

        const src = readLocalFile("../settings_gui/pages/SettingsPage.qml") || "";
        assert(src === "" || src.indexOf("SettingsTabBar") >= 0,
            "the scaffold renders the shared tab bar for a tabs page");
        assert(src === "" || src.indexOf("isZoneCurrent") >= 0,
            "the scaffold exposes the scroll-spy helper section pages may use");
        assert(src === "" || src.indexOf("zoneRequested") < 0,
            "the scaffold no longer forwards zone scrolls");
        assert(src === "" || src.indexOf("Config.settingsSection =") < 0,
            "the scaffold asks the host for a scroll instead of writing a global");

        console.log("PASS: Settings Page Scaffold");
        Qt.exit(0);
    }

    function readLocalFile(relUrl) {
        try {
            const xhr = new XMLHttpRequest();
            const bust = (relUrl.indexOf("?") < 0 ? "?v=" : "&v=") + Date.now() + Math.random();
            xhr.open("GET", Qt.resolvedUrl(relUrl) + bust, false);
            xhr.send();
            return xhr.responseText || "";
        } catch (e) {
            return "";
        }
    }
}
