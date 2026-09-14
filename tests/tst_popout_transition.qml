import QtQuick
import "../components"
import "../theme"

Item {
    id: testRoot
    width: 1920
    height: 1080

    readonly property real borderT: 14
    readonly property real dockW: 70
    readonly property real filletR: 24

    // Active mode state
    property string activeMode: "default"

    // Target sizes per mode
    readonly property real targetPopW: {
        switch (activeMode) {
            case "bluetooth": return 300;
            case "network": return 300;
            case "audio": return 280;
            case "power": return 260;
            default: return 280;
        }
    }

    readonly property real targetContentH: {
        switch (activeMode) {
            case "bluetooth": return 380;
            case "network": return 260;
            case "audio": return 140;
            case "power": return 190;
            default: return 150;
        }
    }

    // Simulated popout wrapper
    Item {
        id: popoutWrapper
        x: testRoot.dockW
        y: Math.max(testRoot.borderT + 10, testRoot.height - testRoot.borderT - targetHeight)
        width: popWidth
        height: targetHeight

        property real popWidth: testRoot.targetPopW
        property real targetHeight: testRoot.targetContentH
    }

    // Simulated bottom popout surface in desktopFrame
    Item {
        id: popoutSurface
        x: testRoot.dockW
        y: popoutWrapper.y
        width: popoutWrapper.width
        height: popoutWrapper.height + testRoot.borderT

        CornerFillet {
            id: tlFillet
            x: 0
            y: -testRoot.filletR
            orientation: "bottomLeft"
            cornerRadius: testRoot.filletR
            fillColor: Colors.surface
        }

        Rectangle {
            id: bodyRect
            x: 0
            y: 0
            width: popoutSurface.width
            height: popoutSurface.height
            color: Colors.surface
        }

        CornerFillet {
            id: brFillet
            x: popoutSurface.width
            y: popoutWrapper.height - testRoot.filletR
            orientation: "bottomLeft"
            cornerRadius: testRoot.filletR
            fillColor: Colors.surface
        }
    }

    Timer {
        interval: 50
        running: true
        repeat: false
        onTriggered: runTests()
    }

    function assert(condition, message) {
        if (!condition) {
            console.error("FAIL: " + message);
            Qt.exit(1);
        }
    }

    function runTests() {
        console.log("RUNNING: Popout Transition & Morphing Tests");

        // Test 1: Default Mode Geometry
        assert(popoutWrapper.width === 280, "Default width must be 280");
        assert(popoutWrapper.height === 150, "Default height must be 150");
        assert(popoutSurface.height === 150 + testRoot.borderT, "popoutSurface height must include borderT");
        assert(brFillet.x === 280, "brFillet x must match width 280");
        assert(brFillet.y === 150 - testRoot.filletR, "brFillet y must be 150 - filletR");
        assert(tlFillet.y === -testRoot.filletR, "tlFillet y must sit at -filletR relative to popoutSurface");

        // Test 2: Switch to Bluetooth Mode (Taller & Wider)
        activeMode = "bluetooth";
        assert(popoutWrapper.width === 300, "Bluetooth width must be 300");
        assert(popoutWrapper.height === 380, "Bluetooth height must be 380");
        assert(popoutWrapper.y === 1080 - 14 - 380, "popoutWrapper y must morph upwards to 686");
        assert(popoutSurface.y === popoutWrapper.y, "popoutSurface y must follow popoutWrapper y");
        assert(popoutSurface.height === 380 + testRoot.borderT, "popoutSurface height must be 380 + borderT");
        assert(brFillet.x === 300, "brFillet x must track new width 300");
        assert(brFillet.y === 380 - testRoot.filletR, "brFillet y must track new height 380 - filletR");

        // Test 3: Switch to Power Mode (Narrower & Medium height)
        activeMode = "power";
        assert(popoutWrapper.width === 260, "Power width must be 260");
        assert(popoutWrapper.height === 190, "Power height must be 190");
        assert(popoutWrapper.y === 1080 - 14 - 190, "popoutWrapper y must morph downwards to 876");
        assert(popoutSurface.y === popoutWrapper.y, "popoutSurface y must follow popoutWrapper y");
        assert(brFillet.x === 260, "brFillet x must track new width 260");
        assert(brFillet.y === 190 - testRoot.filletR, "brFillet y must track new height 190 - filletR");

        console.log("PASS: Popout transition and border morphing verified");
        Qt.exit(0);
    }
}
