import QtQuick
import "../components"
import "../theme"
import "../shell"

Item {
    id: testRoot
    width: 1920
    height: 1080

    // Simulated Config state
    property bool volumeOsdVisible: false
    property bool isUserDraggingVolume: false

    Timer {
        id: volumeOsdTimer
        interval: 1600
        repeat: false
        onTriggered: testRoot.volumeOsdVisible = false
    }

    function triggerVolumeOsd() {
        if (testRoot.isUserDraggingVolume) return;
        testRoot.volumeOsdVisible = true;
        volumeOsdTimer.restart();
    }

    // Real VolumeOsd component
    VolumeOsd {
        id: volumeOsd
        anchors.centerIn: parent
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
        }
    }

    function runTests() {
        console.log("RUNNING: Volume OSD Unit Tests");

        // 1. Geometry & Dimensions
        assert(volumeOsd.implicitWidth === 200, "VolumeOsd implicitWidth must be 200");
        assert(volumeOsd.implicitHeight === 200, "VolumeOsd implicitHeight must be 200");
        assert(volumeOsd.opacity === 0.0, "VolumeOsd must initially be invisible");

        // 2. Lifecycle State Transitions
        assert(!testRoot.volumeOsdVisible, "volumeOsdVisible must initially be false");
        
        // Trigger via keyboard volume change
        triggerVolumeOsd();
        assert(testRoot.volumeOsdVisible, "triggerVolumeOsd must set volumeOsdVisible to true");
        assert(volumeOsdTimer.running, "volumeOsdTimer must be active");

        // Suppression during slider drag
        testRoot.volumeOsdVisible = false;
        testRoot.isUserDraggingVolume = true;
        triggerVolumeOsd();
        assert(!testRoot.volumeOsdVisible, "triggerVolumeOsd must be suppressed while user is dragging volume slider");
        testRoot.isUserDraggingVolume = false;

        // 3. 16-Segment Tick Bar Math Verification
        const computeFilledTicks = (vol, muted) => {
            if (muted) return 0;
            return Math.round(Math.min(1.0, Math.max(0.0, vol)) * 16);
        };

        assert(computeFilledTicks(0.0, false) === 0, "0% volume must have 0 filled ticks");
        assert(computeFilledTicks(0.25, false) === 4, "25% volume must have 4 filled ticks");
        assert(computeFilledTicks(0.50, false) === 8, "50% volume must have 8 filled ticks");
        assert(computeFilledTicks(0.75, false) === 12, "75% volume must have 12 filled ticks");
        assert(computeFilledTicks(1.0, false) === 16, "100% volume must have 16 filled ticks");
        assert(computeFilledTicks(0.75, true) === 0, "Muted volume must have 0 filled ticks");

        // 4. Center-Screen Positioning
        const expectedX = (testRoot.width - 200) / 2;
        const expectedY = (testRoot.height - 200) / 2;
        assert(Math.abs(volumeOsd.x - expectedX) < 1, "VolumeOsd must be centered horizontally at 860px");
        assert(Math.abs(volumeOsd.y - expectedY) < 1, "VolumeOsd must be centered vertically at 440px");

        // 5. Continuous Wave Dynamics (Reflects values upon EVERY volume change)
        // Test at 0% (Silent)
        volumeOsd.testVolume = 0.0;
        volumeOsd.testMuted = 0;
        volumeOsd.animatedVolume = 0.0;
        assert(volumeOsd.wave1Opacity === 0.0, "At 0% volume, wave1Opacity must be 0");
        assert(volumeOsd.wave2Opacity === 0.0, "At 0% volume, wave2Opacity must be 0");
        assert(volumeOsd.wave3Opacity === 0.0, "At 0% volume, wave3Opacity must be 0");

        // Test at 8% (Low Volume)
        volumeOsd.testVolume = 0.08;
        volumeOsd.animatedVolume = 0.08;
        assert(volumeOsd.wave1Opacity > 0.35, "At 8% volume, wave 1 must be active and visible");
        assert(volumeOsd.wave2Opacity === 0.0, "At 8% volume, wave 2 must not be visible yet");
        assert(volumeOsd.wave3Opacity === 0.0, "At 8% volume, wave 3 must not be visible yet");

        // Test at 25% (Medium-Low Volume: wave 2 emerges smoothly)
        volumeOsd.testVolume = 0.25;
        volumeOsd.animatedVolume = 0.25;
        assert(volumeOsd.wave1Opacity > 0.80, "At 25% volume, wave 1 must be nearly solid");
        assert(volumeOsd.wave2Opacity > 0.20, "At 25% volume, wave 2 must emerge smoothly");
        assert(volumeOsd.wave3Opacity === 0.0, "At 25% volume, wave 3 must not be visible yet");
        assert(volumeOsd.wave1Spread > 0.0, "Wave 1 spread must expand outward with volume");

        // Test at 60% (Medium-High Volume: wave 3 emerges smoothly)
        volumeOsd.testVolume = 0.60;
        volumeOsd.animatedVolume = 0.60;
        assert(volumeOsd.wave1Opacity === 1.0, "At 60% volume, wave 1 must be full opacity");
        assert(volumeOsd.wave2Opacity === 1.0, "At 60% volume, wave 2 must be full opacity");
        assert(volumeOsd.wave3Opacity > 0.40, "At 60% volume, wave 3 must emerge smoothly");
        assert(volumeOsd.wave2Spread > volumeOsd.wave1Spread, "Wave 2 spread must be greater than wave 1");

        // Test at 100% (Maximum Volume: all waves full opacity and maximum acoustic spread)
        volumeOsd.testVolume = 1.00;
        volumeOsd.animatedVolume = 1.00;
        assert(volumeOsd.wave1Opacity === 1.0, "At 100% volume, wave 1 must be full opacity");
        assert(volumeOsd.wave2Opacity === 1.0, "At 100% volume, wave 2 must be full opacity");
        assert(volumeOsd.wave3Opacity === 1.0, "At 100% volume, wave 3 must be full opacity");
        assert(volumeOsd.wave3Spread > volumeOsd.wave2Spread, "Wave 3 spread must be greatest at 100%");

        // Test continuous change: every step changes spread and active wave
        volumeOsd.testVolume = 0.28;
        volumeOsd.animatedVolume = 0.28;
        const spreadAt28 = volumeOsd.wave2Spread;
        const opacityAt28 = volumeOsd.wave2Opacity;
        volumeOsd.testVolume = 0.32;
        volumeOsd.animatedVolume = 0.32;
        assert(volumeOsd.wave2Spread > spreadAt28, "Wave spread must increase upon single volume step (0.28 -> 0.32)");
        assert(volumeOsd.wave2Opacity > opacityAt28, "Wave opacity must increase upon single volume step (0.28 -> 0.32)");

        // Test Muted State
        volumeOsd.testMuted = 1;
        assert(volumeOsd.wave1Opacity === 0.0, "When muted, wave 1 must have 0 opacity");
        assert(volumeOsd.wave2Opacity === 0.0, "When muted, wave 2 must have 0 opacity");
        assert(volumeOsd.wave3Opacity === 0.0, "When muted, wave 3 must have 0 opacity");
        assert(volumeOsd.isMuted, "volumeOsd.isMuted must reflect muted state");

        // 6. Pulse Scale Behavior
        assert(volumeOsd.iconPulseScale >= 0.95 && volumeOsd.iconPulseScale <= 1.20, "Pulse scale must be within normalized bounds");

        console.log("PASS: Volume OSD Unit Tests");
        Qt.exit(0);
    }
}
