import QtQuick
import "../components"
import "../theme"

Item {
    id: testRoot
    width: 2560
    height: 1600

    readonly property real borderT: 14
    readonly property real filletR: 24
    readonly property real dropW: 980
    readonly property real dropX: (width - dropW) / 2

    // Simulated Top Border
    Rectangle {
        id: topBorder
        x: 0
        y: 0
        width: parent.width
        height: testRoot.borderT
        color: Colors.surface
    }

    // Generic Fused Dashboard Panel
    FusedPanel {
        id: dashboardPanel
        x: testRoot.dropX
        y: 0
        attachEdge: "top"
        panelWidth: testRoot.dropW
        panelHeight: 560
        borderThickness: testRoot.borderT
        borderRounding: testRoot.filletR
        isOpen: true
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
        console.log("RUNNING: Dashboard Fusion Tests");

        // Verify that top border and panel share exact boundary at y = 14
        assert(topBorder.height === 14, "topBorder height is 14");
        assert(dashboardPanel.borderThickness === 14, "dashboardPanel borderThickness is 14");
        assert(dashboardPanel.card.y === 0, "dashboardPanel card starts at y = 0");
        assert(dashboardPanel.card.border.width === 0, "dashboardPanel card must have 0 border width to avoid dividing seams");

        // Verify fillet 1 (left) connects exactly at y = 14
        assert(dashboardPanel.fillet1.y === 14, "Left fillet y must be 14, flush with bottom of topBorder");
        assert(dashboardPanel.fillet1.x === -24, "Left fillet x must be -24 relative to panel");
        assert(dashboardPanel.fillet1.orientation === "dropdownLeft", "Left fillet orientation");

        // Verify fillet 2 (right) connects exactly at y = 14
        assert(dashboardPanel.fillet2.y === 14, "Right fillet y must be 14, flush with bottom of topBorder");
        assert(dashboardPanel.fillet2.x === 980, "Right fillet x must be 980 relative to panel");
        assert(dashboardPanel.fillet2.orientation === "dropdownRight", "Right fillet orientation");

        // Verify absolute screen coordinates of fillets
        const absFillet1X = dashboardPanel.x + dashboardPanel.fillet1.x;
        const absFillet1Y = dashboardPanel.y + dashboardPanel.fillet1.y;
        assert(absFillet1X === (testRoot.dropX - 24), "Absolute screen X of left fillet");
        assert(absFillet1Y === 14, "Absolute screen Y of left fillet");

        const absFillet2X = dashboardPanel.x + dashboardPanel.fillet2.x;
        const absFillet2Y = dashboardPanel.y + dashboardPanel.fillet2.y;
        assert(absFillet2X === (testRoot.dropX + 980), "Absolute screen X of right fillet");
        assert(absFillet2Y === 14, "Absolute screen Y of right fillet");

        // Verify overshoot behavior (progress = 1.21 during spring bounce)
        dashboardPanel.offsetProgress = 1.21;
        assert(dashboardPanel.card.y === 0, "Card y must REMAIN at 0 during spring overshoot - zero disconnection!");
        assert(dashboardPanel.card.height > 560, "Card height expands elastically during spring bounce");
        assert(dashboardPanel.fillet1.y === 14, "Left fillet remains welded to top border during overshoot");
        assert(dashboardPanel.fillet2.y === 14, "Right fillet remains welded to top border during overshoot");

        // Verify partial morphing behavior (progress = 0.5)
        dashboardPanel.offsetProgress = 0.5;
        assert(dashboardPanel.card.y === 0, "Card y must be 0 at midway morphing");
        const expectedMidHeight = 14 + (560 - 14) * 0.5;
        assert(Math.abs(dashboardPanel.card.height - expectedMidHeight) < 0.01, "Card height matches morphing formula at progress 0.5");
        assert(dashboardPanel.filletFactor === 1.0, "Fillet is at full strength once height exceeds borderT + filletR");

        console.log("PASS: Dashboard Fusion Tests");
        Qt.exit(0);
    }
}
