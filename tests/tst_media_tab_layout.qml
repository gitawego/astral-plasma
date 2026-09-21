import QtQuick
import QtQuick.Layouts
import "../components"
import "../dashboard/tabs"
import "../theme"

Item {
    id: testRoot
    width: 800
    height: 600

    MediaTab {
        id: testMediaTab
        width: 680
        visible: false
    }

    RadialCoverVisualiser {
        id: testVisualiser
        width: 240
        height: 240
        visible: false
    }

    HeatmapSpeakerPlayer {
        id: testSpeaker
        width: 240
        height: 240
        visible: false
    }

    RadialCoverRing {
        id: testRing
        innerRadius: 58
        visible: false
    }

    Timer {
        interval: 50
        running: true
        repeat: false
        onTriggered: runTests()
    }

    function assert(cond, msg) {
        if (!cond) {
            console.error("FAIL: " + msg);
            Qt.exit(1);
            throw new Error("FAIL: " + msg);
        }
    }

    function runTests() {
        console.log("RUNNING: Media Tab Layout & Visualiser Unit Tests");

        // 1. MediaTab Implicit Height
        assert(testMediaTab.implicitHeight === 260,
               "MediaTab implicitHeight should be 260px (compact fit), got: " + testMediaTab.implicitHeight);

        // 2. RadialCoverVisualiser geometry
        assert(testVisualiser.barsCount === 48,
               "RadialCoverVisualiser barsCount should be 48, got: " + testVisualiser.barsCount);
        assert(testVisualiser.coverRadius === 58,
               "RadialCoverVisualiser coverRadius should be 58, got: " + testVisualiser.coverRadius);
        assert(testVisualiser.implicitWidth === 240,
               "RadialCoverVisualiser implicitWidth should be 240, got: " + testVisualiser.implicitWidth);
        assert(testVisualiser.implicitHeight === 240,
               "RadialCoverVisualiser implicitHeight should be 240, got: " + testVisualiser.implicitHeight);

        // 3. RadialCoverVisualiser bar value calculation
        testVisualiser.isPlaying = false;
        assert(testVisualiser.getBarValue(0) === 0.0,
               "When paused, bar value must be 0.0");

        // 4. HeatmapSpeakerPlayer geometry & existence
        assert(testSpeaker.implicitWidth === 260,
               "HeatmapSpeakerPlayer implicitWidth should be 260, got: " + testSpeaker.implicitWidth);
        assert(testSpeaker.implicitHeight === 260,
               "HeatmapSpeakerPlayer implicitHeight should be 260, got: " + testSpeaker.implicitHeight);
        assert(testSpeaker.rimThickness === 14,
               "HeatmapSpeakerPlayer rimThickness should be 14, got: " + testSpeaker.rimThickness);
        assert(Math.abs(testSpeaker.speakerRadius - (240 * 0.28)) < 0.01,
               "HeatmapSpeakerPlayer speakerRadius should scale to width * 0.28");

        // 5. RadialCoverRing (Dashboard tab halo) geometry & existence
        assert(testRing.barsCount === 40,
               "RadialCoverRing barsCount should be 40, got: " + testRing.barsCount);
        assert(testRing.innerRadius === 58,
               "RadialCoverRing innerRadius should be 58, got: " + testRing.innerRadius);
        assert(testRing.baseBarHeight === 2.5,
               "RadialCoverRing baseBarHeight should be 2.5, got: " + testRing.baseBarHeight);

        console.log("PASS: All Media Tab Layout & Visualiser tests passed!");
        Qt.exit(0);
    }
}
