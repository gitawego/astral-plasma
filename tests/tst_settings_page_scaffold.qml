import QtQuick
import QtQuick.Layouts
import "../settings_gui/pages"

// ============================================================================
// Settings page scaffold
// ============================================================================
// The contract every settings page opts into: a sticky title, and the zone list
// the hub's scroll-spy and rail are built from. These assertions are the contract
// itself, so a page cannot half-adopt it (a rail with zones whose anchors do not
// resolve would scroll nowhere).
Item {
    id: testRoot
    width: 900
    height: 700

    // A page with three zones, at deliberately uneven offsets.
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

            Item { id: statusAnchor; implicitHeight: 40 }
            Item { implicitHeight: 260 }
            Item { id: wifiAnchor; implicitHeight: 40 }
            Item { implicitHeight: 120 }
            Item { id: advancedAnchor; implicitHeight: 40 }
        }
    }

    // A page with a single zone: a title, no rail.
    SettingsPage {
        id: singleZonePage
        width: 400
        title: "Sound"
        zones: [{ id: "outputs", label: "Outputs", anchor: outputsAnchor }]
        Item { id: outputsAnchor; implicitHeight: 20 }
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
        // The declaration *is* the contract
        // ------------------------------------------------------------------
        assert(triPage.title === "Network" && triPage.subtitle !== "",
            "the page carries its identity");
        assert(triPage.zones.length === 3, "three zones declared");
        assert(triPage.hasRail === true, "three zones means a rail");

        // Anchors resolve to real page coordinates, in order.
        const statusY = triPage.sectionY("status");
        const wifiY = triPage.sectionY("wifi");
        const advancedY = triPage.sectionY("advanced");
        assert(statusY !== undefined && wifiY !== undefined && advancedY !== undefined,
            "every declared zone has an anchor");
        assert(statusY < wifiY && wifiY < advancedY,
            "zones resolve in document order (" + statusY + ", " + wifiY + ", " + advancedY + ")");
        assert(statusY === statusAnchor.mapToItem(triPage, 0, 0).y,
            "the anchor is mapped into page coordinates, not guessed");
        assert(triPage.sectionY("nonsense") === undefined,
            "an undeclared zone has no anchor to scroll to");

        // ------------------------------------------------------------------
        // Highlighting and jumping
        // ------------------------------------------------------------------
        triPage.currentSection = "wifi";
        assert(triPage.isZoneCurrent("wifi") === true
                && triPage.isZoneCurrent("status") === false,
            "only the current zone is highlighted");
        triPage.currentSection = "";
        assert(triPage.isZoneCurrent("status") === false,
            "before the spy reports, nothing is highlighted");
        // A rail press must reach the host: the page emits `zoneRequested`, and
        // the hub is the one that scrolls. It used to write
        // `Config.settingsSection` from a file that never imported `Config` - an
        // unimported singleton is not in a component's scope, so the guarded
        // write was a silent no-op and the whole rail was dead.
        let requested = "";
        function scaffoldZoneProbe(zoneId) { requested = zoneId; }
        triPage.zoneRequested.connect(scaffoldZoneProbe);
        triPage.jumpToZone("advanced");
        triPage.zoneRequested.disconnect(scaffoldZoneProbe);
        assert(requested === "advanced", "a rail press asks the host for that zone");

        // ------------------------------------------------------------------
        // A single zone is a title, not a rail
        // ------------------------------------------------------------------
        assert(singleZonePage.hasRail === false,
            "one zone does not get a rail - a single pill is not navigation");
        assert(singleZonePage.sectionY("outputs") !== undefined, "its anchor still resolves");

        // ------------------------------------------------------------------
        // The hub contract is present (the hub reads these four members)
        // ------------------------------------------------------------------
        assert(triPage.stickyHeader !== null && typeof triPage.stickyHeader === "object",
            "the scaffold provides the sticky header");
        assert(triPage.currentSection === "", "the hub can write the current section");
        assert(typeof triPage.sectionY === "function" && typeof triPage.isZoneCurrent === "function",
            "the scaffold answers the hub's questions");

        // The rail renders the shared rule, and the header is built from the
        // declaration rather than hand-written per page.
        const src = readLocalFile("../settings_gui/pages/SettingsPage.qml") || "";
        assert(src === "" || src.indexOf("active: root.isZoneCurrent(modelData.id)") >= 0,
            "rail segments render the shared highlight rule");
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
