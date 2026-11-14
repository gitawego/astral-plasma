import QtQuick
import "../modules/Astral/Apps/Dashboard"
import "../modules/Astral/Kernel/theme"

// The dashboard open/close has three choreographies. All must leave the
// content layout static (the measured 150%-of-a-core regression), and they
// differ only in how the content is revealed:
//
//   slide     - content y moves with the growing fused card;
//   reveal    - content y stays at its final position and the clip reveals it;
//   slideBody - the frame's welded header is static and the dashboard content
//               starts below frameInset, sliding in under the top border.
//
// In slideBody the dashboard root itself is inset below the top border, so the
// content can never overlap the edge; currentDropH stays at its final height.
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
        id: bodySlide
        dropX: 0
        dropW: 980
        frameInset: 14
        visible: false
        appHost: testRoot.host("slideBody")
    }

    property int stage: 0
    property real slideMid: 0
    property real revealMid: 0
    property real bodySlideMid: 0

    Timer {
        interval: 50
        running: true
        repeat: false
        onTriggered: {
            slide.offsetProgress = 0.5;
            reveal.offsetProgress = 0.5;
            bodySlide.offsetProgress = 0.5;
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
            assert(bodySlide.motion === "slideBody", "slideBody instance selects the static-header choreography");
            assert(bodySlide.slideBodyMotion === true, "slideBody flag is on");

            // The fused envelope morphs in slide/reveal, but is static in slideBody.
            assert(Math.abs(slide.currentDropH - slide.dropH * 0.5) < 0.01,
                "slide frame envelope follows offsetProgress (got " + slide.currentDropH + ")");
            assert(Math.abs(reveal.currentDropH - reveal.dropH * 0.5) < 0.01,
                "reveal frame envelope follows offsetProgress (got " + reveal.currentDropH + ")");
            assert(Math.abs(bodySlide.currentDropH - bodySlide.dropH) < 0.01,
                "slideBody envelope keeps its final height (got " + bodySlide.currentDropH + ")");

            // The content height is final-size in all three at mid transition.
            const expectedHeight = Math.max(0, slide.dropH - slide.padLarge * 2);
            assert(Math.abs(slide.layoutItem.height - expectedHeight) < 0.01,
                "slide content keeps its final height during the transition (got "
                    + slide.layoutItem.height + ", expected " + expectedHeight + ")");
            assert(Math.abs(reveal.layoutItem.height - expectedHeight) < 0.01,
                "reveal content keeps its final height during the transition (got "
                    + reveal.layoutItem.height + ")");
            assert(Math.abs(bodySlide.layoutItem.height - expectedHeight) < 0.01,
                "slideBody content keeps its final height during the transition (got "
                    + bodySlide.layoutItem.height + ")");

            // slide/reveal content paths.
            const slideY = slide.padLarge + Math.min(0, slide.currentDropH - slide.dropH);
            assert(Math.abs(slide.layoutItem.y - slideY) < 0.01,
                "slide content y follows the card (got " + slide.layoutItem.y
                    + ", expected " + slideY + ")");
            assert(Math.abs(reveal.layoutItem.y - reveal.padLarge) < 0.01,
                "reveal content y stays at its final position (got " + reveal.layoutItem.y + ")");

            // slideBody: the dashboard itself is clipped below the welded top
            // border, and its content is still above the clip at half progress.
            const bodyHeight = Math.max(0, bodySlide.dropH - bodySlide.frameInset);
            assert(Math.abs(bodySlide.y - bodySlide.frameInset) < 0.01,
                "slideBody dashboard starts below the top border (got " + bodySlide.y + ")");
            assert(Math.abs(bodySlide.height - bodyHeight) < 0.01,
                "slideBody dashboard is clipped to the body height (got " + bodySlide.height + ")");
            const bodySlideY = bodySlide.padLarge - bodySlide.frameInset
                - bodyHeight * (1.0 - 0.5);
            assert(Math.abs(bodySlide.layoutItem.y - bodySlideY) < 0.01,
                "slideBody content slides under the header (got " + bodySlide.layoutItem.y
                    + ", expected " + bodySlideY + ")");

            testRoot.slideMid = slide.layoutItem.height;
            testRoot.revealMid = reveal.layoutItem.height;
            testRoot.bodySlideMid = bodySlide.layoutItem.height;

            slide.offsetProgress = 1.0;
            reveal.offsetProgress = 1.0;
            bodySlide.offsetProgress = 1.0;
            settle.start();
            return;
        }

        // Settled: all land on their final geometry; heights never depended on
        // the animated envelope.
        assert(Math.abs(slide.layoutItem.y - slide.padLarge) < 0.01,
            "slide content lands at its final y (got " + slide.layoutItem.y + ")");
        assert(Math.abs(reveal.layoutItem.y - reveal.padLarge) < 0.01,
            "reveal content lands at its final y (got " + reveal.layoutItem.y + ")");
        assert(Math.abs(bodySlide.layoutItem.y - (bodySlide.padLarge - bodySlide.frameInset)) < 0.01,
            "slideBody content lands just below the header (got " + bodySlide.layoutItem.y + ")");
        assert(Math.abs(bodySlide.y - bodySlide.frameInset) < 0.01,
            "slideBody dashboard stays inset below the top border (got " + bodySlide.y + ")");
        assert(Math.abs(bodySlide.height - Math.max(0, bodySlide.dropH - bodySlide.frameInset)) < 0.01,
            "slideBody dashboard height is invariant (got " + bodySlide.height + ")");
        assert(Math.abs(bodySlide.currentDropH - bodySlide.dropH) < 0.01,
            "slideBody envelope is still its final height (got " + bodySlide.currentDropH + ")");

        assert(Math.abs(slide.layoutItem.height - testRoot.slideMid) < 0.01,
            "slide content height is invariant across the transition (got "
                + slide.layoutItem.height + ", was " + testRoot.slideMid + ")");
        assert(Math.abs(reveal.layoutItem.height - testRoot.revealMid) < 0.01,
            "reveal content height is invariant across the transition (got "
                + reveal.layoutItem.height + ", was " + testRoot.revealMid + ")");
        assert(Math.abs(bodySlide.layoutItem.height - testRoot.bodySlideMid) < 0.01,
            "slideBody content height is invariant across the transition (got "
                + bodySlide.layoutItem.height + ", was " + testRoot.bodySlideMid + ")");

        console.log("PASS: Dashboard Motion Tests");
        Qt.exit(0);
    }
}
