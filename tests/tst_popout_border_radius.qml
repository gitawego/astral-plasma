import QtQuick
import "../shell"
import "../config"
import "../theme"

Item {
    id: testRoot
    width: 1920
    height: 1080

    UnifiedFrame {
        id: frame
        width: parent.width
        height: parent.height
        dockW: 70
        borderT: 14
        filletR: 20
        borderColor: "#33ffffff"
        dropX: 470
        dropW: 980
        currentDropH: 300
        dropdownOffsetProgress: 0.0
        currentPopW: 280
        popoutY: 400
        popoutHeight: 240
        popoutOffsetProgress: 1.0
        fusedProgress: 0.0 // Floating state
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
        console.log("RUNNING: Popout Drawer Shoulder Fillets & Border Radius Unit Tests");

        let popSurface = frame.bottomPopoutSurfaceItem;

        // Test 1: Floating Popout State (e.g. App preview, Wi-Fi, Clock in mid-dock)
        // Must have concave inverted shoulder fillets smoothly bridging dock into drawer
        frame.fusedProgress = 0.0;
        assert(popSurface.topR === 20, "topR must be 20 when floating");
        assert(popSurface.botR === 20, "botR must be 20 when floating");
        assert(popSurface.fusedBottomFilletR === 0, "fusedBottomFilletR must be 0 when floating");
        assert(popSurface.bodyW === 281, "bodyW must be currentPopW + 1 (281)");
        assert(popSurface.width === 281, "popSurface.width must be bodyW when floating (281)");
        assert(popSurface.y === frame.popoutY - popSurface.topR, "popSurface.y must expand up by topR (380)");
        assert(popSurface.height === frame.popoutHeight + popSurface.topR + popSurface.botR, "popSurface.height must include both fillets (280)");
        assert(frame.popoutGapTop === 380, "dock gap top must align with top fillet (380)");
        assert(frame.popoutGapBottom === 660, "dock gap bottom must align with bottom fillet (660)");
        assert(popSurface.x === frame.dockW - 1, "popSurface x should be dockW - 1 (69) for seamless docking");

        // Test 2: Bottom-Fused State (e.g. Power at the bottom of the screen)
        // Top shoulder fillet remains, bottom-right concave fillet smoothly merges into bottom desktop border
        frame.fusedProgress = 1.0;
        assert(popSurface.topR === 20, "topR must be 20 when fused to bottom");
        assert(popSurface.botR === 0, "botR must be 0 when fused to bottom");
        assert(popSurface.fusedBottomFilletR === 20, "fusedBottomFilletR must be 20 when fused to bottom");
        assert(popSurface.bodyW === 281, "bodyW must be currentPopW + 1 (281)");
        assert(popSurface.width === 301, "popSurface.width must expand by fusedBottomFilletR (301)");
        assert(popSurface.y === frame.popoutY - popSurface.topR, "popSurface.y must expand up by topR (380)");
        assert(popSurface.height === frame.popoutHeight + popSurface.topR, "popSurface.height must include top fillet only (260)");
        assert(frame.popoutGapTop === 380, "dock gap top must remain 380");
        assert(frame.popoutGapBottom === 640, "dock gap bottom must be flush with drawer bottom (640)");

        console.log("PASS: Popout Drawer Shoulder Fillets & Border Radius Unit Tests");
        Qt.exit(0);
    }
}
