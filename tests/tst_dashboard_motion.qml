import QtQuick
import "../modules/Astral/Apps/Dashboard"
import "../modules/Astral/Kernel/theme"

// The dashboard open/close has two content choreographies, and both must keep
// the fused card envelope morph while leaving the content layout static:
//
//   slide  - content y moves with the growing card;
//   reveal - content y stays at its final position and the clip reveals it.
//
// The regression this guards is the one measured live: binding the content's
// height/margins to the animated envelope reflowed the whole dashboard every
// frame (150% of a core) and made the drawer lag under load. The content height
// must therefore be independent of offsetProgress in both modes.
Item {
    id: testRoot
    width: 2560
    height: 1600

    readonly property var tabs: [
        { id: "dashboard", label: "Dashboard", icon: "dashboard", enabled: true },
        { id: "media", label: "Media", icon: "media", enabled: true }
    ]

    function host(motion) {
        return {
            state: ({
                dashboardVisible: true,
                dashboardWidth: 980,
                activeDashboardTab: "dashboard",
                dashboardMotion: motion,
                dashboardTabs: tabs
            }),
            intents: null,
            session: null,
            media: null,
            metrics: null
        };
    }

    DashboardApp {
        id: slide
        dropX: 0
        dropW: 980
        visible: false
        appHost: testRoot.host("slide")
    }

    DashboardApp {
        id: reveal
        dropX: 0
        dropW: 980
        visible: false
        appHost: testRoot.host("reveal")
    }

    property int stage: 0

    Timer {
        interval: 50
        running: true
        repeat: false
        onTriggered: {
            slide.offsetProgress = 0.5;
            reveal.offsetProgress = 0.5;
            settle.start();
        }
    }

    // The expressive spatial step (500ms) plus margin, for the Behavior to settle.
    Timer {
        id: settle
        interval: 750
        repeat: false
        onTriggered: testRoot.advance()
    }

    function assert(condition, message) {
        if (!condition) {
            console.error("FAIL: " + message);
            Qt.exit(1);
            // Qt.exit only schedules the exit; a suite that keeps running would
            // print PASS and override the code (docs/LESSONS.md 37).
            throw new Error(message);
        }
    }

    function advance() {
        if (stage === 0) {
            stage = 1;

            assert(slide.motion === "slide", "slide instance selects the slide choreography");
            assert(reveal.motion === "reveal", "reveal instance selects the reveal choreography");

            // The frame envelope still morphs in both variants.
            assert(Math.abs(slide.currentDropH - slide.dropH * 0.5) < 0.01,
                "slide frame envelope follows offsetProgress (got " + slide.currentDropH + ")");
            assert(Math.abs(reveal.currentDropH - reveal.dropH * 0.5) < 0.01,
                "reveal frame envelope follows offsetProgress (got " + reveal.currentDropH + ")");

            // The content height is final-size in both modes, at mid transition.
            const expectedHeight = Math.max(0, slide.dropH - slide.padLarge * 2);
            assert(Math.abs(slide.layoutItem.height - expectedHeight) < 0.01,
                "slide content keeps its final height during the transition (got "
                    + slide.layoutItem.height + ", expected " + expectedHeight + ")");
            assert(Math.abs(reveal.layoutItem.height - expectedHeight) < 0.01,
                "reveal content keeps its final height during the transition (got "
                    + reveal.layoutItem.height + ")");

            // Only the content's y differs between the two choreographies.
            const slideY = slide.padLarge + Math.min(0, slide.currentDropH - slide.dropH);
            assert(Math.abs(slide.layoutItem.y - slideY) < 0.01,
                "slide content y follows the card (got " + slide.layoutItem.y
                    + ", expected " + slideY + ")");
            assert(Math.abs(reveal.layoutItem.y - slide.padLarge) < 0.01,
                "reveal content y stays at its final position (got " + reveal.layoutItem.y + ")");

            const midHeight = slide.layoutItem.height;

            slide.offsetProgress = 1.0;
            reveal.offsetProgress = 1.0;
            settle.start();
            testRoot.midHeight = midHeight;
            return;
        }

        // Settled: both content paths land on the same geometry, and the height
        // never depended on the animated envelope.
        assert(Math.abs(slide.layoutItem.y - slide.padLarge) < 0.01,
            "slide content lands at its final y (got " + slide.layoutItem.y + ")");
        assert(Math.abs(reveal.layoutItem.y - slide.padLarge) < 0.01,
            "reveal content lands at its final y (got " + reveal.layoutItem.y + ")");
        assert(Math.abs(slide.layoutItem.height - midHeight) < 0.01,
            "slide content height is invariant across the transition (got "
                + slide.layoutItem.height + ", was " + midHeight + ")");
        assert(Math.abs(reveal.layoutItem.height - midHeight) < 0.01,
            "reveal content height is invariant across the transition (got "
                + reveal.layoutItem.height + ", was " + midHeight + ")");

        console.log("PASS: Dashboard Motion Tests");
        Qt.exit(0);
    }

    property real midHeight: 0
}
