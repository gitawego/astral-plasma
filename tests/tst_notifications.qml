import QtQuick
import "../notifications"
import "../theme"

Item {
    id: testRoot
    width: 1920
    height: 1080

    NotificationPopup {
        id: notifPopup
        borderThickness: 14
        borderRounding: 24

        summary: "Test notification"
        timeStr: "now"
        body: "Here's a really long message to test truncation in the notification popup..."
        appName: "TestApp"
        materialIcon: "info"
        visible: true
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
        console.log("RUNNING: NotificationPopup Tests");

        // Test 1: Geometry and placement
        assert(notifPopup.width === 380, "notifPopup width should be 380");
        assert(notifPopup.fusedPanel.attachEdge === "topRight", "notifPopup attachEdge must be topRight");

        // Test 2: Inverted fillets
        assert(notifPopup.fusedPanel.fillet1.orientation === "dropdownLeft", "Left fillet must be dropdownLeft");
        assert(notifPopup.fusedPanel.fillet1.x === -24, "Left fillet x must be -24");
        assert(notifPopup.fusedPanel.fillet1.y === 14, "Left fillet y must be 14 (borderThickness)");
        assert(notifPopup.fusedPanel.fillet2.orientation === "topRight", "Bottom fillet must be topRight");

        // Test 3: Header and content
        assert(notifPopup.summary === "Test notification", "Summary title preserved");
        assert(notifPopup.timeStr === "now", "Timestamp string preserved");
        assert(notifPopup.expanded === false, "Default expanded state should be false");

        // Test 4: Expand toggle
        notifPopup.toggleExpanded();
        assert(notifPopup.expanded === true, "toggleExpanded should switch expanded to true");
        notifPopup.toggleExpanded();
        assert(notifPopup.expanded === false, "toggleExpanded should switch expanded back to false");

        // Test 5: Auto-close timer lifecycle
        assert(notifPopup.timeoutMs === 5000, "Default timeoutMs should be 5000ms");
        assert(notifPopup.autoCloseTimer.interval === 5000, "autoCloseTimer interval should be 5000");
        assert(notifPopup.autoCloseTimer.running === true, "autoCloseTimer should be running when visible and not hovered");
        assert(notifPopup.isDismissed === false, "isDismissed initially false");
        assert(notifPopup.fusedPanel.isOpen === true, "fusedPanel should be open initially");

        // Test 6: Border stroke & color fusion
        assert(notifPopup.fusedPanel.strokeWidth === 1, "fusedPanel strokeWidth must be 1 for border fusion");
        assert(notifPopup.fusedPanel.fillet1.strokeWidth === 1, "fillet1 strokeWidth must be 1");
        assert(notifPopup.fusedPanel.fillet2.strokeWidth === 1, "fillet2 strokeWidth must be 1");
        assert(notifPopup.fusedPanel.fillColor !== "transparent", "fusedPanel fillColor must not be transparent");

        // Test 7: Dismissal via close() method
        var closedSignalFired = false;
        notifPopup.closed.connect(function() {
            closedSignalFired = true;
        });

        notifPopup.close();
        assert(closedSignalFired === true, "closed() signal must be emitted when close() is invoked");
        assert(notifPopup.isDismissed === true, "isDismissed must be true after close()");
        assert(notifPopup.autoCloseTimer.running === false, "autoCloseTimer must be stopped after close()");
        assert(notifPopup.fusedPanel.isOpen === false, "fusedPanel must be closed after close()");

        console.log("PASS: NotificationPopup Tests");
        Qt.exit(0);
    }
}
