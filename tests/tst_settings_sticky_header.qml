import QtQuick
import "../settings_gui/pages"
import "../settings_gui/SectionSpy.js" as SectionSpy
import "../settings_gui/ScrollMotion.js" as ScrollMotion

// ============================================================================
// Sticky page header + scroll spy
// ============================================================================
// A long settings page used to hide its own identity (title, state rail) as soon
// as you scrolled, and there was no way to tell which zone you were in. Two
// contracts fix that:
//
//   * the hub pins a header the page provides (`stickyHeader`), so the title and
//     the state rail stay put while the content moves;
//   * the hub tells the page which section is current (`currentSection`), so the
//     rail can highlight it - the reader always knows where they are.
//
// The spy rule is pure (SectionSpy); the wiring is asserted against the real
// sources, and the page's own contract is exercised through its test seam.
Item {
    id: testRoot
    width: 900
    height: 700

    // The AI page is the reference implementation of the contract.
    AiPage {
        id: aiPage
        testMode: true
        testProviders: []
    }

    readonly property var zones: [
        { id: "quotas", label: "Quotas" },
        { id: "copilot", label: "Copilot" },
        { id: "setup", label: "Setup" }
    ]
    readonly property var offsets: ({ quotas: 0, copilot: 720, setup: 1580 })

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

    Timer {
        interval: 60
        running: true
        repeat: false
        onTriggered: runTests()
    }

    function runTests() {
        console.log("RUNNING: Sticky Header & Section Spy");

        // ------------------------------------------------------------------
        // The spy: which zone is the reader in?
        // ------------------------------------------------------------------
        assert(SectionSpy.sectionAt(testRoot.zones, testRoot.offsets, 0) === "quotas",
            "the top of the page is the first zone");
        assert(SectionSpy.sectionAt(testRoot.zones, testRoot.offsets, 719) === "quotas",
            "a zone becomes current when its anchor is reached, not before");
        assert(SectionSpy.sectionAt(testRoot.zones, testRoot.offsets, 720) === "copilot",
            "crossing an anchor switches the zone");
        assert(SectionSpy.sectionAt(testRoot.zones, testRoot.offsets, 5000) === "setup",
            "past the last anchor the last zone stays current");
        assert(SectionSpy.sectionAt(testRoot.zones, testRoot.offsets, -50) === "quotas",
            "a bounce above the top does not lose the first zone");

        // The end of a scrollable page: a trailing section can be shorter than
        // the viewport, so its anchor never reaches the top - the reader is still
        // looking at it, and the pill they clicked must light up.
        assert(SectionSpy.sectionAt(testRoot.zones, testRoot.offsets, 900, 800) === "setup",
            "at the end of a page that scrolls, the last zone is current");
        // A page that fits the viewport does not scroll (`endOffset` is 0): the
        // top stays the first zone, not the last one.
        assert(SectionSpy.sectionAt(testRoot.zones, testRoot.offsets, 16, 0) === "quotas",
            "a page that fits entirely opens on its first zone");
        assert(SectionSpy.sectionAt(testRoot.zones, testRoot.offsets, 400, 800) === "quotas",
            "mid-page, the anchor rule still decides (not the page end)");

        assert(SectionSpy.sectionAt(testRoot.zones, testRoot.offsets, -50) === "quotas",
            "a bounce above the top does not lose the first zone");

        // Unknown anchors are skipped, not guessed.
        assert(SectionSpy.sectionAt(testRoot.zones, { copilot: 100 }, 5000) === "copilot",
            "a zone without a known anchor cannot be current");
        assert(SectionSpy.sectionAt(testRoot.zones, null, 5000) === "quotas",
            "no offsets at all still names the first zone");
        assert(SectionSpy.sectionAt([], testRoot.offsets, 100) === "",
            "a page without zones highlights nothing");

        // ------------------------------------------------------------------
        // The page half of the contract
        // ------------------------------------------------------------------
        assert(aiPage.stickyHeader !== null, "the AI page provides a sticky header");
        assert(aiPage.zones.length === 3, "the AI page names its three zones");
        assert(aiPage.zones[0].id === "quotas" && aiPage.zones[2].id === "setup",
            "zones are declared in document order");
        assert(aiPage.sectionY("quotas") !== undefined && aiPage.sectionY("copilot") !== undefined
                && aiPage.sectionY("setup") !== undefined,
            "every zone has an anchor the hub can scroll to");
        assert(aiPage.sectionY("voice") === aiPage.sectionY("setup"),
            "the old voice deep link still lands on the setup zone");
        assert(aiPage.sectionY("nonsense") === undefined,
            "an unknown section name has no anchor");

        // The rail follows the hub's scroll-spy (the delegate renders the rule, so
        // the rule is what is asserted here; the hub's side is below).
        aiPage.currentSection = "copilot";
        assert(aiPage.isZoneCurrent("copilot") === true
                && aiPage.isZoneCurrent("quotas") === false
                && aiPage.isZoneCurrent("setup") === false,
            "only the current zone's segment is highlighted");
        aiPage.currentSection = "setup";
        assert(aiPage.isZoneCurrent("setup") === true && aiPage.isZoneCurrent("copilot") === false,
            "scrolling to another zone moves the highlight");
        const pageSrcForRail = readLocalFile("../settings_gui/pages/AiPage.qml");
        assert(pageSrcForRail.indexOf("active: root.isZoneCurrent(modelData.id)") >= 0,
            "the rail segments render the spy's rule");

        // Its rail asks the host too: the AI page keeps its own root, so it
        // forwards the same `zoneRequested` contract as every scaffold page.
        let aiRequested = "";
        function aiZoneProbe(zoneId) { aiRequested = zoneId; }
        aiPage.zoneRequested.connect(aiZoneProbe);
        aiPage.jumpToZone("setup");
        aiPage.zoneRequested.disconnect(aiZoneProbe);
        assert(aiRequested === "setup", "the AI page's rail asks the host for its zone");

        // ------------------------------------------------------------------
        // The hub half of the contract
        // ------------------------------------------------------------------
        const hub = readLocalFile("../settings_gui/NexusHub.qml");
        const stickyLoader = hub.indexOf("id: stickyHeaderLoader");
        const flickable = hub.indexOf("id: pageFlickable");
        assert(stickyLoader >= 0, "the hub renders the page's sticky header");
        assert(stickyLoader < flickable,
            "the sticky header is declared outside (before) the flickable, or it would scroll with it");
        assert(hub.indexOf("SectionSpy.sectionAt(") >= 0, "the hub derives the current section");
        assert(hub.indexOf("currentSection =") >= 0,
            "the hub pushes the current section into the loaded page");
        assert(hub.indexOf("item.stickyHeader") >= 0,
            "the hub reads the header the page provides");
        assert(hub.indexOf("pageFlickable.contentY + 16") >= 0,
            "the spy follows the flickable's offset");
        assert(hub.indexOf("stickyHeaderLoader.item") >= 0 || hub.indexOf("id: stickyHeaderLoader") >= 0,
            "the pinned header has its own loader");

        // The AI page must not render the header twice.
        const page = readLocalFile("../settings_gui/pages/AiPage.qml");
        assert(page.split("AI & Agents").length - 1 === 1,
            "the page title lives in the sticky header exactly once");
        assert(page.indexOf("property Component stickyHeader") >= 0,
            "the page exposes its header as a component");
        assert(page.indexOf("readonly property var zones") >= 0, "the page declares its zones");

        // ------------------------------------------------------------------
        // Smooth scrolling: a section jump is a spatial transition
        // ------------------------------------------------------------------
        // ScrollMotion owns the whole motion two ways: pure (asserted here) and
        // as the single call the hub makes.
        const theme = {
            animExpressiveFastSpatial: 350,
            animExpressiveDefaultSpatial: 500,
            curveExpressiveFastSpatial: [0.42, 1.67, 0.21, 0.9, 1.0, 1.0],
            curveExpressiveDefaultSpatial: [0.38, 1.21, 0.22, 1.0, 1.0, 1.0],
            curveExpressiveDefaultEffects: [0.34, 0.80, 0.34, 1.0, 1.0, 1.0]
        };
        assert(ScrollMotion.motionFor(theme, 200).duration === 350,
            "a short jump uses the fast spatial duration");
        assert(ScrollMotion.motionFor(theme, -900).duration === 500,
            "a long jump uses the default spatial duration, in either direction");
        assert(ScrollMotion.motionFor(theme, 599).duration === 350
                && ScrollMotion.motionFor(theme, 601).duration === 500,
            "the ladder switches by distance, not by luck");

        // The spring is damped by distance: expressive on a hop, settled on a jump.
        const spatial = [0.42, 1.67, 0.21, 0.9, 1.0, 1.0];
        const settled = [0.34, 0.80, 0.34, 1.0, 1.0, 1.0];
        const undamped = ScrollMotion.dampedCurve(spatial, settled, 0);
        assert(undamped[1] === spatial[1] && undamped[3] === spatial[3],
            "at zero distance the token curve is untouched");
        const fullyDamped = ScrollMotion.dampedCurve(spatial, settled, ScrollMotion.FULL_DAMP_DISTANCE);
        assert(fullyDamped[1] === settled[1] && fullyDamped[3] === settled[3] && fullyDamped[5] === settled[5],
            "a long jump arrives on the settled spring (" + fullyDamped.join(", ") + ")");
        assert(fullyDamped[0] === spatial[0] && fullyDamped[2] === spatial[2],
            "and keeps the spatial token's rhythm (x controls untouched)");
        assert(fullyDamped[1] <= 1.0,
            "the settled curve has no overshoot left to fling past the section");
        const halfway = ScrollMotion.dampedCurve(spatial, settled, ScrollMotion.FULL_DAMP_DISTANCE / 2);
        assert(halfway[1] < spatial[1] && halfway[1] > settled[1],
            "between the two, the spring is partially damped");
        assert(halfway[0] === spatial[0] && halfway[2] === spatial[2],
            "the x controls (the rhythm) are never touched");
        const shortHop = ScrollMotion.dampedCurve(spatial, settled, 120);
        assert(shortHop[1] > 1.0, "a short hop keeps its spring");
        assert(ScrollMotion.dampedCurve(null, settled, 100) === null
                && ScrollMotion.dampedCurve(spatial, [1, 2], 100) === spatial,
            "malformed curves are returned untouched instead of crashing the scroll");

        // The complete motion for a scroll: duration and curve from one place.
        const hop = ScrollMotion.motionFor(theme, 200);
        assert(hop && hop.duration === 350, "a short hop takes the fast spatial token");
        assert(hop.curve[1] > 1.0 && hop.curve[1] < spatial[1] && hop.curve[0] === spatial[0],
            "a short hop keeps its spring (damped by distance, rhythm untouched)");
        const jump = ScrollMotion.motionFor(theme, 1500);
        assert(jump && jump.duration === 500, "a long jump takes the default spatial token");
        assert(jump.curve[1] === settled[1] && jump.curve[0] === theme.curveExpressiveDefaultSpatial[0],
            "a long jump is damped onto the settled spring, with the spatial rhythm");
        assert(ScrollMotion.motionFor(undefined, 500) === null
                && ScrollMotion.motionFor({}, 500) === null,
            "without motion tokens there is no motion to invent (the harness degrades to a jump)");

        // The hub animates the scroll and yields to the reader.
        assert(hub.indexOf('property: "contentY"') >= 0,
            "the section scroll animates the flickable's contentY");
        assert(hub.indexOf("ScrollMotion.motionFor(root.motionTokens,") >= 0,
            "the scroll takes its duration and curve from the shell's motion tokens");
        assert(hub.indexOf("property var motionTokens: Theme") >= 0,
            "the motion tokens come from Theme (one seam, overridable for tests / reduced motion)");
        assert(hub.indexOf("sectionScrollAnim.stop()") >= 0,
            "the animation can be stopped (the wheel handler does, so it never fights the reader)");
        assert(hub.indexOf("Math.min(max, y)") >= 0 || hub.indexOf("Math.min(max, y);") >= 0,
            "a scroll target is clamped to the scrollable range");

        console.log("PASS: Sticky Header & Section Spy");
        Qt.exit(0);
    }
}
