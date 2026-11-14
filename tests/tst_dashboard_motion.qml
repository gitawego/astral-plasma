import QtQuick
import "../modules/Astral/Apps/Dashboard"
import "../modules/Astral/Kernel/theme"

// The dashboard open/close has three choreographies. All three must leave the
// content layout static (that was the measured 150%-of-a-core regression), and
// they must differ only in how the furniture moves:
//
//   slide     - content y moves with the growing card;
//   reveal    - content y stays at its final position and the clip reveals it;
//   translate - the whole panel keeps its final size and slides down from above
//               the screen edge while fading in (the reference shell's mode).
//
// The translate instance is the one that must never animate the envelope at all:
// currentDropH is dropH from the first frame and only y/opacity move.
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

    DashboardApp {
        id: translate
        dropX: 0
        dropW: 980
        visible: false
        appHost: testRoot.host("translate")
    }

    property int stage: 0
    property real slideMid: 0
    property real revealMid: 0
    property real translateMid: 0

    Timer {
        interval: 50
        running: true
        repeat: false
        onTriggered: {
            slide.offsetProgress = 0.5;
            reveal.offsetProgress = 0.5;
            translate.offsetProgress = 0.5;
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
            assert(translate.motion === "translate", "translate instance selects the translate choreography");
            assert(translate.translateMotion === true, "translate flag is on for translate mode");

            // The fused envelope morphs in slide/reveal, but is static in translate.
            assert(Math.abs(slide.currentDropH - slide.dropH * 0.5) < 0.01,
                "slide frame envelope follows offsetProgress (got " + slide.currentDropH + ")");
            assert(Math.abs(reveal.currentDropH - reveal.dropH * 0.5) < 0.01,
                "reveal frame envelope follows offsetProgress (got " + reveal.currentDropH + ")");
            assert(Math.abs(translate.currentDropH - translate.dropH) < 0.01,
                "translate envelope keeps its final height (got " + translate.currentDropH + ")");

            // Content height is final-size in all three at mid transition.
            const expectedHeight = Math.max(0, slide.dropH - slide.padLarge * 2);
            assert(Math.abs(slide.layoutItem.height - expectedHeight) < 0.01,
                "slide content keeps its final height during the transition (got "
                    + slide.layoutItem.height + ", expected " + expectedHeight + ")");
            assert(Math.abs(reveal.layoutItem.height - expectedHeight) < 0.01,
                "reveal content keeps its final height during the transition (got "
                    + reveal.layoutItem.height + ")");
            assert(Math.abs(translate.layoutItem.height - expectedHeight) < 0.01,
                "translate content keeps its final height during the transition (got "
                    + translate.layoutItem.height + ")");

            // The content's path differs per choreography.
            const slideY = slide.padLarge + Math.min(0, slide.currentDropH - slide.dropH);
            assert(Math.abs(slide.layoutItem.y - slideY) < 0.01,
                "slide content y follows the card (got " + slide.layoutItem.y
                    + ", expected " + slideY + ")");
            assert(Math.abs(reveal.layoutItem.y - slide.padLarge) < 0.01,
                "reveal content y stays at its final position (got " + reveal.layoutItem.y + ")");
            assert(Math.abs(translate.layoutItem.y - translate.padLarge) < 0.01,
                "translate content y stays at its final position inside the card (got "
                    + translate.layoutItem.y + ")");

            // Translate: the whole panel is above its resting place at half progress.
            const expectedSlideY = -(translate.dropH + 5) * 0.5;
            assert(Math.abs(translate.slideOffsetY - expectedSlideY) < 0.01,
                "translate panel offset follows the progress (got " + translate.slideOffsetY
                    + ", expected " + expectedSlideY + ")");
            assert(Math.abs(translate.y - expectedSlideY) < 0.01,
                "translate container y follows the panel offset (got " + translate.y + ")");
            assert(Math.abs(translate.contentOpacity - 0.5) < 0.01,
                "translate panel fades with the progress (got " + translate.contentOpacity + ")");

            testRoot.slideMid = slide.layoutItem.height;
            testRoot.revealMid = reveal.layoutItem.height;
            testRoot.translateMid = translate.layoutItem.height;

            slide.offsetProgress = 1.0;
            reveal.offsetProgress = 1.0;
            translate.offsetProgress = 1.0;
            settle.start();
            return;
        }

        // Settled: all three land on the same geometry; translate is fully on
        // screen, opaque, and its envelope never moved.
        assert(Math.abs(slide.layoutItem.y - slide.padLarge) < 0.01,
            "slide content lands at its final y (got " + slide.layoutItem.y + ")");
        assert(Math.abs(reveal.layoutItem.y - slide.padLarge) < 0.01,
            "reveal content lands at its final y (got " + reveal.layoutItem.y + ")");
        assert(Math.abs(translate.layoutItem.y - translate.padLarge) < 0.01,
            "translate content lands at its final y (got " + translate.layoutItem.y + ")");
        assert(Math.abs(translate.slideOffsetY) < 0.01,
            "translate panel lands at y = 0 (got " + translate.slideOffsetY + ")");
        assert(Math.abs(translate.y) < 0.01,
            "translate container lands at y = 0 (got " + translate.y + ")");
        assert(Math.abs(translate.contentOpacity - 1.0) < 0.01,
            "translate panel lands fully opaque (got " + translate.contentOpacity + ")");
        assert(Math.abs(translate.currentDropH - translate.dropH) < 0.01,
            "translate envelope is still its final height (got " + translate.currentDropH + ")");

        assert(Math.abs(slide.layoutItem.height - testRoot.slideMid) < 0.01,
            "slide content height is invariant across the transition (got "
                + slide.layoutItem.height + ", was " + testRoot.slideMid + ")");
        assert(Math.abs(reveal.layoutItem.height - testRoot.revealMid) < 0.01,
            "reveal content height is invariant across the transition (got "
                + reveal.layoutItem.height + ", was " + testRoot.revealMid + ")");
        assert(Math.abs(translate.layoutItem.height - testRoot.translateMid) < 0.01,
            "translate content height is invariant across the transition (got "
                + translate.layoutItem.height + ", was " + testRoot.translateMid + ")");

        console.log("PASS: Dashboard Motion Tests");
        Qt.exit(0);
    }
}
