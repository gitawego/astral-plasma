import QtQuick
import "../modules/Astral/Kernel/components"

// ============================================================================
// macOS-style overlay scroll indicator
// ============================================================================
// A wheel-driven scroll does not set Flickable.moving, so the indicator must
// follow the shared handler's animating state, stay visible briefly after the
// momentum stops, then fade out.
Item {
    id: testRoot
    width: 400
    height: 300

    SmoothFlickable {
        id: page
        width: 240
        height: 200
        contentHeight: 1000
        contentWidth: width

        Rectangle {
            width: 240
            height: 1000
            color: "#333"
        }
    }

    GlassScrollIndicator {
        id: indicator
        anchors.right: page.right
        anchors.top: page.top
        anchors.bottom: page.bottom
        flickable: page
        restingOpacity: 0
        activeOpacity: 0.8
    }

    function assert(condition, message) {
        if (!condition) {
            console.error("FAIL: " + message);
            Qt.exit(1);
            throw new Error(message);
        }
    }

    Component.onCompleted: {
        assert(indicator.active === false, "the bar rests before a wheel event");
        assert(indicator.barItem.opacity === 0, "a transient bar rests at opacity 0");
        page.wheelHandler.scrollEnded.connect(testRoot.onScrollEnded);
        page.wheelHandler.scrollBy(0, -120);
    }

    Timer {
        interval: 80
        running: true
        repeat: false
        onTriggered: checkActive()
    }

    Timer {
        id: holdCheckTimer
        interval: 50
        repeat: false
        onTriggered: {
            assert(indicator.scrollHold === true,
                "the bar holds briefly after the momentum stops");
            assert(indicator.active === true,
                "the hold keeps the bar visible");
            assert(Math.abs(indicator.barItem.opacity - 0.8) < 0.01,
                "the bar reaches active opacity during the hold");
            restCheckTimer.start();
        }
    }

    Timer {
        id: restCheckTimer
        interval: 1000
        repeat: false
        onTriggered: checkRest()
    }

    function checkActive() {
        assert(page.wheelHandler.animating === true,
            "the wheel handler is gliding");
        assert(indicator.active === true,
            "the bar is active while the wheel handler glides");
        assert(indicator.barItem.opacity > 0,
            "the bar fades in during the glide");
    }

    function onScrollEnded() {
        assert(page.wheelHandler.animating === false,
            "the momentum has settled");
        assert(indicator.scrollHold === true,
            "the scroll-end starts the hold");
        holdCheckTimer.start();
    }

    function checkRest() {
        assert(indicator.scrollHold === false,
            "the hold expires");
        assert(indicator.active === false,
            "the bar returns to rest");
        assert(indicator.barItem.opacity === 0,
            "the transient bar fades out");
        console.log("PASS: macOS-style scroll indicator");
        Qt.exit(0);
    }
}
