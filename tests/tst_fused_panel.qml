import QtQuick
import "../components"
import "../theme"

Item {
    id: testRoot
    width: 1920
    height: 1080

    // Test Panel 1: Top-fused Central Dashboard
    FusedPanel {
        id: topPanel
        attachEdge: "top"
        panelWidth: 980
        panelHeight: 520
        borderThickness: 14
        borderRounding: 24
        isOpen: true
    }

    // Test Panel 2: Top-right fused Notification Popup
    FusedPanel {
        id: notifPanel
        attachEdge: "topRight"
        panelWidth: 380
        panelHeight: 120
        borderThickness: 14
        borderRounding: 24
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
        console.log("RUNNING: FusedPanel Tests");

        // Test 1: Top-fused panel (Dashboard) geometry
        assert(topPanel.card.width === 980, "topPanel card width should be 980");
        assert(topPanel.card.height === 520, "topPanel card height should be 520");
        assert(topPanel.card.bottomLeftRadius === 24, "topPanel card bottomLeftRadius should match borderRounding");
        assert(topPanel.card.bottomRightRadius === 24, "topPanel card bottomRightRadius should match borderRounding");
        assert(topPanel.card.topLeftRadius === 0, "topPanel card topLeftRadius must be 0 (fused)");
        assert(topPanel.card.topRightRadius === 0, "topPanel card topRightRadius must be 0 (fused)");

        // Test 2: Top-fused fillets
        // Left fillet must sit at x = -borderRounding, y = borderThickness
        assert(topPanel.fillet1 !== null, "topPanel left fillet must exist");
        assert(topPanel.fillet1.x === -24, "topPanel left fillet x must be -24");
        assert(topPanel.fillet1.y === 14, "topPanel left fillet y must be 14 (borderThickness, NOT 0)");
        assert(topPanel.fillet1.orientation === "dropdownLeft", "topPanel left fillet orientation");

        // Right fillet must sit at x = panelWidth, y = borderThickness
        assert(topPanel.fillet2 !== null, "topPanel right fillet must exist");
        assert(topPanel.fillet2.x === 980, "topPanel right fillet x must be 980");
        assert(topPanel.fillet2.y === 14, "topPanel right fillet y must be 14 (borderThickness, NOT 0)");
        assert(topPanel.fillet2.orientation === "dropdownRight", "topPanel right fillet orientation");

        // Test 3: Top-right fused panel (Notifications) geometry
        assert(notifPanel.card.width === 380, "notifPanel width should be 380");
        assert(notifPanel.card.height === 120, "notifPanel height should be 120");
        assert(notifPanel.card.bottomLeftRadius === 24, "notifPanel bottomLeftRadius should be 24");
        assert(notifPanel.card.topLeftRadius === 0, "notifPanel topLeftRadius must be 0 (fused to top border)");
        assert(notifPanel.card.topRightRadius === 0, "notifPanel topRightRadius must be 0 (fused to screen corner)");
        assert(notifPanel.card.bottomRightRadius === 0, "notifPanel bottomRightRadius must be 0 (fused to right border)");

        // Test 4: Top-right fillets
        // Left fillet (connecting to top border): x = -24, y = 14
        assert(notifPanel.fillet1.x === -24, "notifPanel left fillet x must be -24");
        assert(notifPanel.fillet1.y === 14, "notifPanel left fillet y must be 14");
        assert(notifPanel.fillet1.orientation === "dropdownLeft", "notifPanel top-left fillet orientation");

        // Bottom fillet (connecting to right border): x = 380 - 14 - 24 = 342, y = 120
        assert(notifPanel.fillet2.x === 342, "notifPanel bottom fillet x must be 342");
        assert(notifPanel.fillet2.y === 120, "notifPanel bottom fillet y must be 120");
        assert(notifPanel.fillet2.orientation === "topRight", "notifPanel bottom-right fillet orientation");

        console.log("PASS: FusedPanel Tests");
        Qt.exit(0);
    }
}
