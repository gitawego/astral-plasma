import QtQuick
import "../dock/components"
import "../theme"

// ============================================================================
// Dock Scroll Capsule Contract
// ============================================================================
// The dock's taskbar grows with the number of running apps. Unbounded, it
// collides with the modules below it (system tray, clock, status pill) and with
// the active-window label above; and a plain Flickable gives no hint that more
// icons exist.
//
// The capsule must therefore:
//   1. never exceed the height it is given (`maxHeight`),
//   2. snap its viewport to WHOLE items, so scrolling never shows half an icon,
//   3. honour an explicit item cap (`maxVisibleItems`) when configured,
//   4. expose the overflow with a scrollbar thumb whose size and position track
//      the content, and end chevrons that appear only in the scrollable
//      direction.
Item {
    id: testRoot
    width: 800
    height: 600

    function assert(condition, message) {
        if (!condition) {
            console.log("FAIL: " + message);
            console.error("FAIL: " + message);
            Qt.exit(1);
            throw new Error(message);
        }
    }

    // Ten 40px items, 4px apart, 10px padding: 488px of content.
    DockScrollCapsule {
        id: overflowingCapsule
        width: 48
        itemSize: 40
        itemSpacing: 4
        vPad: 10
        maxHeight: 200

        Repeater {
            model: 10
            delegate: Rectangle { width: 40; height: 40 }
        }
    }

    // The same capsule with an explicit item cap.
    DockScrollCapsule {
        id: cappedCapsule
        width: 48
        itemSize: 40
        itemSpacing: 4
        vPad: 10
        maxHeight: 200
        maxVisibleItems: 2

        Repeater {
            model: 10
            delegate: Rectangle { width: 40; height: 40 }
        }
    }

    // Three items: 20 + 3*44 - 4 = 148px, comfortably inside the cap.
    DockScrollCapsule {
        id: fittingCapsule
        width: 48
        itemSize: 40
        itemSpacing: 4
        vPad: 10
        maxHeight: 200

        Repeater {
            model: 3
            delegate: Rectangle { width: 40; height: 40 }
        }
    }

    // Filling mode: the capsule spans the height it is granted (the dock taskbar
    // fills the bar) even when its content is shorter.
    DockScrollCapsule {
        id: fillingCapsule
        width: 48
        itemSize: 40
        itemSpacing: 4
        vPad: 10
        maxHeight: 300
        fillHeight: true

        Repeater {
            model: 3
            delegate: Rectangle { width: 40; height: 40 }
        }
    }

    Timer {
        interval: 50
        running: true
        repeat: false
        onTriggered: runTests()
    }

    function runTests() {
        console.log("RUNNING: Dock Scroll Capsule Contract");

        // ---- 1. Whole-item snapping and the height cap -------------------
        const stride = 44; // itemSize + itemSpacing
        const expectedVisible = Math.floor((200 - 20 + 4) / stride); // 4
        assert(overflowingCapsule.visibleItemCount === expectedVisible,
            "visibleItemCount must snap to whole items (expected " + expectedVisible
            + ", got " + overflowingCapsule.visibleItemCount + ")");
        assert(overflowingCapsule.implicitHeight === 10 * 2 + expectedVisible * stride - 4,
            "the capsule must size itself to whole items (expected "
            + (20 + expectedVisible * stride - 4) + ", got " + overflowingCapsule.implicitHeight + ")");
        assert(overflowingCapsule.implicitHeight <= overflowingCapsule.maxHeight,
            "the capsule must never exceed maxHeight (got " + overflowingCapsule.implicitHeight
            + " vs " + overflowingCapsule.maxHeight + ")");
        assert(overflowingCapsule.overflowing === true,
            "ten items in a 200px capsule must report overflow");

        // ---- 2. Explicit item cap ---------------------------------------
        assert(cappedCapsule.visibleItemCount === 2,
            "maxVisibleItems must cap the visible count (got " + cappedCapsule.visibleItemCount + ")");
        assert(cappedCapsule.implicitHeight === 20 + 2 * stride - 4,
            "the capped capsule must size to exactly two items (got "
            + cappedCapsule.implicitHeight + ")");

        // ---- 3. No overflow, no chrome ----------------------------------
        assert(fittingCapsule.overflowing === false,
            "three items inside the cap must not report overflow");
        assert(fittingCapsule.implicitHeight === 20 + 3 * stride - 4,
            "a fitting capsule must take its natural height (got "
            + fittingCapsule.implicitHeight + ")");
        assert(fittingCapsule.thumbItem.visible === false,
            "no scrollbar thumb without overflow");
        assert(fittingCapsule.moreDownItem.visible === false && fittingCapsule.moreUpItem.visible === false,
            "no end chevrons without overflow");

        // ---- 3b. Filling mode -------------------------------------------
        assert(fillingCapsule.implicitHeight === 300,
            "a filling capsule must span the height it is granted (got "
            + fillingCapsule.implicitHeight + ")");
        assert(fillingCapsule.overflowing === false,
            "three items inside a filling capsule still do not overflow");
        assert(fillingCapsule.flickable.contentY === 0
            && fillingCapsule.flickable.contentHeight < fillingCapsule.flickable.height,
            "the icons start at the top of a filling capsule, not centred");
        assert(fillingCapsule.thumbItem.visible === false,
            "a filling capsule without overflow shows no thumb");

        // ---- 4. Overflow affordances ------------------------------------
        assert(overflowingCapsule.thumbItem.visible === true,
            "overflow must show the scrollbar thumb");
        const track = overflowingCapsule.thumbTrackItem;
        const thumb = overflowingCapsule.thumbItem;
        assert(thumb.height >= 18 && thumb.height <= track.height,
            "thumb height must stay within the track (got " + thumb.height + ")");
        const expectedThumb = Math.max(18, track.height * (overflowingCapsule.listHeight / overflowingCapsule.contentHeight));
        assert(Math.abs(thumb.height - expectedThumb) <= 1.0,
            "thumb height must be proportional to the visible fraction (expected "
            + expectedThumb.toFixed(1) + ", got " + thumb.height + ")");

        assert(overflowingCapsule.atTop === true && overflowingCapsule.atBottom === false,
            "a fresh list must report atTop");
        assert(overflowingCapsule.moreUpItem.visible === false && overflowingCapsule.moreDownItem.visible === true,
            "at the top, only the 'more below' chevron may show");

        // Scroll to the end: the affordances must flip.
        overflowingCapsule.scrollToBottom();
        assert(overflowingCapsule.atBottom === true && overflowingCapsule.atTop === false,
            "scrollToBottom must reach the end of the list");
        assert(overflowingCapsule.moreDownItem.visible === false && overflowingCapsule.moreUpItem.visible === true,
            "at the end, only the 'more above' chevron may show");
        assert(Math.abs(thumb.y - (track.y + track.height - thumb.height)) <= 1.0,
            "the thumb must sit at the end of the track when scrolled to the bottom");

        overflowingCapsule.scrollToTop();
        assert(overflowingCapsule.atTop === true, "scrollToTop must return to the start");
        assert(Math.abs(thumb.y - track.y) <= 1.0,
            "the thumb must sit at the start of the track when scrolled to the top");

        console.log("PASS: Dock Scroll Capsule Contract (whole-item cap, proportional thumb, "
            + "directional chevrons, no chrome without overflow)");
        Qt.exit(0);
    }
}
