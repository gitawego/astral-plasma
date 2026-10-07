import QtQuick
import "../settings_gui"
import "../settings_gui/ScrollMotion.js" as ScrollMotion
import "../settings_gui/SectionSpy.js" as SectionSpy

// ============================================================================
// Settings hub: zone offsets, scroll spy, and the rail's pills
// ============================================================================
// The rail's highlight and every section jump depend on one number per zone: the
// anchor's offset inside the page. It is easy to get wrong in a way tests of the
// spy alone cannot see - the spy is pure and correct, it is the *input* that
// goes stale:
//
//   * a page that has not been laid out yet reports every anchor at y = 0, and
//     all-zero offsets make the spy pick the *last* zone, so the rail highlights
//     the wrong pill at the top of a short page;
//   * a short page never changes the flickable's content height, so a snapshot
//     taken when the page was installed is never refreshed.
//
// And a pill that *looks* right can still be a dead control: the rail is built by
// the page, the scrolling is owned by the hub, and the request between them has
// to actually arrive. So this test clicks the rendered pills - not the page's
// function, not the hub's scroll - and asserts the view moves.
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
    // Values captured in one step and asserted in the next (the request is
    // honoured one event-loop turn after the press).
    property int expectedLongRung: 0
    property int expectedNearRung: 0
    property real expectedNearAnchor: 0

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

    /// The rendered pill with this label, wherever it sits in the hub's tree.
    /// Walking the visual children keeps the test black-box: it asserts what the
    /// reader can press, not the plumbing behind it.
    function findPill(item, label) {
        if (!item || item.children === undefined) return null;
        for (let i = 0; i < item.children.length; ++i) {
            const child = item.children[i];
            if (child.label === label && typeof child.clicked === "function") return child;
            const nested = findPill(child, label);
            if (nested) return nested;
        }
        return null;
    }

    function advance() {
        switch (testRoot.step++) {
        case 0: {
            console.log("RUNNING: Settings Hub Rail");

            // --------------------------------------------------------------
            // A default page: offsets are live, not a pre-layout snapshot
            // --------------------------------------------------------------
            assert(hub.activePage === "wallpaper", "the hub opens on the wallpaper page");
            const offsets = hub.pageZoneOffsets;
            assert(offsets.wallpaper === 0,
                "the first zone sits at the top of the page (got " + offsets.wallpaper + ")");
            assert(offsets.palette > offsets.wallpaper
                    && offsets.mode > offsets.palette
                    && offsets.gallery > offsets.mode,
                "the zones ascend in document order ("
                    + [offsets.wallpaper, offsets.palette, offsets.mode, offsets.gallery].join(", ") + ")");
            assert(hub.activePageSection === "wallpaper",
                "the reader at the top is in the first zone (got \"" + hub.activePageSection + "\")");
            hub.activePage = "audio";
            break;
        }
        case 1:
            // Let the new page settle into its layout.
            break;
        case 2: {
            // --------------------------------------------------------------
            // A page shorter than the viewport: the offsets still resolve
            // --------------------------------------------------------------
            // This is the regression: the audio page's content fits the window,
            // so `contentHeight` never changes after the page is installed. With
            // a stale snapshot every anchor read y = 0 and the spy reported the
            // *last* zone ("visualizer") while the page was at the top.
            const page = hub.pageItem;
            assert(page && page.zones && page.zones.length === 2,
                "the audio page declares its two always-on zones");
            const offsets = hub.pageZoneOffsets;
            assert(offsets.output === 0, "audio: the output zone is at the top (got " + offsets.output + ")");
            assert(offsets.visualizer > 0,
                "audio: the visualizer zone has a real offset (got " + offsets.visualizer + ")");
            assert(hub.contentMaxOffset === 0,
                "audio: the page fits the viewport, so it cannot scroll");
            assert(hub.activePageSection === "output",
                "audio: the top of the page is the output zone, not the last one (got \""
                    + hub.activePageSection + "\")");
            hub.activePage = "system";
            break;
        }
        case 3:
            // Let the new page settle into its layout.
            break;
        case 4: {
            // --------------------------------------------------------------
            // A long page: every declared zone resolves in order
            // --------------------------------------------------------------
            const zones = hub.pageZones;
            assert(zones.length === 6, "the system page declares six zones (got " + zones.length + ")");
            let previous = -1;
            for (let i = 0; i < zones.length; ++i) {
                const y = hub.pageZoneOffsets[zones[i].id];
                assert(y !== undefined && y > previous,
                    "system: " + zones[i].id + " resolves below the previous zone (" + previous + " -> " + y + ")");
                previous = y;
            }
            assert(hub.activePageSection === "services",
                "system: the top of the page is the services zone (got \"" + hub.activePageSection + "\")");
            assert(hub.contentMaxOffset > 0, "the system page scrolls");

            // Without motion tokens (no Theme offscreen), a jump is a jump: the
            // *destination* is what matters here, and the trailing zone still
            // becomes current although its anchor cannot reach the viewport top.
            hub.scrollTo(hub.pageZoneOffsets.display);
            assert(hub.contentOffset === hub.contentMaxOffset,
                "the view reaches the end of the page (" + hub.contentOffset + " of " + hub.contentMaxOffset + ")");
            assert(hub.activePageSection === "display",
                "the trailing zone the reader asked for is current (got \"" + hub.activePageSection + "\")");

            // Back to the top, then hand the hub the tokens its harness cannot
            // load, so the next jump must animate.
            hub.scrollTo(0);
            hub.motionTokens = {
                animExpressiveFastSpatial: 350,
                animExpressiveDefaultSpatial: 500,
                curveExpressiveFastSpatial: [0.42, 1.67, 0.21, 0.9, 1.0, 1.0],
                curveExpressiveDefaultSpatial: [0.38, 1.21, 0.22, 1.0, 1.0, 1.0],
                curveExpressiveDefaultEffects: [0.34, 0.80, 0.34, 1.0, 1.0, 1.0]
            };
            break;
        }
        case 5:
            // The scroll back to the top (still token-less) has settled.
            break;
        case 6: {
            // --------------------------------------------------------------
            // Pressing a pill is what the reader does - and it must scroll
            // --------------------------------------------------------------
            // The failing report: clicking a pill in the pinned header did
            // nothing at all, because the page's request never reached the hub.
            assert(hub.contentOffset === 0, "the click test starts from the top of the page");
            const pill = testRoot.findPill(hub.contentPaneItem, "Display");
            assert(pill !== null,
                "the pinned header renders the zone pills (" + testRoot.pillLabels(hub.contentPaneItem).join(", ") + ")");
            const target = Math.min(hub.pageZoneOffsets.display, hub.contentMaxOffset);
            const expected = ScrollMotion.motionFor(hub.motionTokens, target - hub.contentOffset);
            assert(expected !== null, "the expected motion resolves from the tokens");
            pill.clicked();
            assert(hub.pendingSectionId === "display",
                "the pressed pill's request reaches the hub (nothing arrived before this test existed)");
            testRoot.expectedLongRung = expected.duration;
            break;
        }
        case 7: {
            // The request is honoured one turn later, once the offsets it reads
            // are the settled ones; one tick in, the tween is in transit.
            const target = Math.min(hub.pageZoneOffsets.display, hub.contentMaxOffset);
            assert(hub.scrollAnimating === true, "the request started a scroll");
            assert(hub.scrollAnimationDuration === testRoot.expectedLongRung,
                "and it takes the token its distance earns (" + hub.scrollAnimationDuration
                    + "ms, expected " + testRoot.expectedLongRung + "ms)");
            assert(hub.contentOffset > 0 && hub.contentOffset < target,
                "the view is mid-flight toward the pressed zone (offset " + hub.contentOffset
                    + " of " + target + ")");
            break;
        }
        case 8: {
            const target = Math.min(hub.pageZoneOffsets.display, hub.contentMaxOffset);
            assert(hub.contentOffset === target,
                "the click lands on the zone's anchor (offset " + hub.contentOffset
                    + " of " + target + ")");
            assert(hub.activePageSection === "display",
                "and the spy marks the pressed zone current (got \"" + hub.activePageSection + "\")");

            // A nearer zone takes the snappy rung instead.
            const nearPill = testRoot.findPill(hub.contentPaneItem, "Desktop");
            assert(nearPill !== null, "the pinned header renders the Desktop pill");
            const nearTarget = hub.pageZoneOffsets.desktop;
            testRoot.expectedNearRung = ScrollMotion.motionFor(hub.motionTokens, nearTarget - hub.contentOffset).duration;
            testRoot.expectedNearAnchor = nearTarget;
            nearPill.clicked();
            assert(hub.pendingSectionId === "desktop", "the second press also reaches the hub");
            break;
        }
        case 9:
            // The near jump is in flight (or already there).
            break;
        case 10: {
            assert(hub.contentOffset === testRoot.expectedNearAnchor,
                "the second click lands on its anchor too (offset " + hub.contentOffset
                    + " of " + testRoot.expectedNearAnchor + ")");
            assert(hub.scrollAnimationDuration === testRoot.expectedNearRung,
                "a near zone takes the fast rung (" + hub.scrollAnimationDuration
                    + "ms, expected " + testRoot.expectedNearRung + "ms)");
            assert(hub.activePageSection === "desktop",
                "and the spy follows the second press (got \"" + hub.activePageSection + "\")");

            // Switching pages resets the view and the highlight.
            hub.activePage = "network";
            break;
        }
        case 11:
            // Let the new page settle into its layout.
            break;
        case 12: {
            assert(hub.contentOffset === 0, "a new page starts at the top");
            assert(hub.activePageSection === "wifi",
                "network: switching pages resets the highlight to the new first zone (got \""
                    + hub.activePageSection + "\")");

            // A page whose one section is hidden rail-free: the network page's
            // second pill disappears with Wi-Fi, and pressing the first still works.
            const wifiPill = testRoot.findPill(hub.contentPaneItem, "Wi-Fi");
            assert(wifiPill !== null, "the rail renders a pill per live zone");

            // A name the page resolves but that is not a rail zone must keep
            // working: the AI page's legacy "voice" deep link lands on setup. The
            // request path cannot require the name to be a declared zone.
            // A shorter hub so the AI page has somewhere to scroll: its anchors
            // are near the bottom of this viewport otherwise.
            hub.height = 300;
            hub.activePage = "ai";
            break;
        }
        case 13:
            // Let the AI page settle into its layout.
            break;
        case 14: {
            assert(hub.contentMaxOffset > 0,
                "the AI page scrolls at this viewport height (its legacy deep link has somewhere to land)");
            assert(hub.pageItem.sectionY("voice") === hub.pageItem.sectionY("setup"),
                "the AI page still resolves its legacy voice deep link");
            hub.scrollToSection("voice");
            assert(hub.pendingSectionId === "voice", "the legacy name is parked like any other request");
            break;
        }
        case 15:
            // The alias jump is in flight.
            break;
        case 16: {
            const setupY = Math.min(hub.pageItem.sectionY("setup"), hub.contentMaxOffset);
            assert(hub.contentOffset === setupY,
                "the legacy deep link lands on the zone it aliases (offset " + hub.contentOffset
                    + " of " + setupY + ")");
            assert(hub.activePageSection === "setup",
                "and the rail marks the zone it landed on (got \"" + hub.activePageSection + "\")");

            // Back to the long page, at the normal viewport height, to check what
            // happens when the zone asked for cannot reach the top.
            hub.height = 560;
            hub.activePage = "system";
            break;
        }
        case 17:
            // Let the system page settle into its layout.
            break;
        case 18: {
            // A zone near the end of a long page: its anchor cannot become the
            // top of the viewport, so the view clamps to the page end. The pill
            // the reader pressed must stay lit - the geometry would call that
            // position "display", a zone they did not ask for.
            hub.scrollToSection("logging");
            assert(hub.pendingSectionId === "logging", "the request is parked");
            break;
        }
        case 19:
            // The clamp jump is in flight.
            break;
        case 20: {
            const geometric = SectionSpy.sectionAt(hub.pageZones, hub.pageZoneOffsets,
                hub.contentOffset + 16, hub.contentMaxOffset);
            assert(hub.contentOffset === hub.contentMaxOffset,
                "a low zone clamps to the end of the page (offset " + hub.contentOffset
                    + " of " + hub.contentMaxOffset + ")");
            assert(geometric === "display",
                "the geometry alone would report the trailing zone (got \"" + geometric + "\")");
            assert(hub.activePageSection === "logging",
                "but the pressed zone stays current (got \"" + hub.activePageSection + "\")");

            // The reader takes over: the request highlight yields to the geometry.
            hub.userScrolled(-80);
            const after = SectionSpy.sectionAt(hub.pageZones, hub.pageZoneOffsets,
                hub.contentOffset + 16, hub.contentMaxOffset);
            assert(hub.activePageSection === after,
                "a wheel scroll hands the highlight back to the geometry (got \""
                    + hub.activePageSection + "\", expected \"" + after + "\")");
            assert(after !== "logging", "and the geometry is genuinely elsewhere (" + after + ")");

            // A page switch clears any outstanding request too.
            hub.scrollToSection("logging");
            hub.activePage = "dock";
            break;
        }
        case 21:
            // Let the dock page settle into its layout.
            break;
        case 22: {
            assert(hub.activePageSection === "dock",
                "switching pages clears the request highlight (got \"" + hub.activePageSection + "\")");
            assert(hub.contentOffset === 0,
                "and a new page opens at its top, not at the old page's offset (got "
                    + hub.contentOffset + ")");
            console.log("PASS: Settings Hub Rail");
            Qt.exit(0);
            break;
        }
        default:
            break;
        }
    }

    /// Debug helper: the labels the rail currently renders.
    function pillLabels(item) {
        const labels = [];
        const walk = function (node) {
            if (!node || node.children === undefined) return;
            for (let i = 0; i < node.children.length; ++i) {
                const child = node.children[i];
                if (child.label !== undefined && typeof child.clicked === "function") labels.push(child.label);
                walk(child);
            }
        };
        walk(item);
        return labels;
    }
}
