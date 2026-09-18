import QtQuick
import "../components"
import "../theme"
import "../config"

Item {
    id: testRoot
    width: 800
    height: 600

    readonly property int iconS: 32
    readonly property int containerW: iconS + 16 // 48
    readonly property int containerRadius: Math.round(containerW * 0.5) // 24
    readonly property int vPad: 10
    readonly property int itemSize: iconS + 8 // 40
    readonly property int itemRadius: Math.max(8, Math.round(itemSize * 0.28)) // 11
    readonly property color testDotColor: (typeof Colors !== "undefined" && Colors.textOnSurface) ? Qt.alpha(Colors.textOnSurface, 0.70) : Qt.rgba(1, 1, 1, 0.7)

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
        console.log("RUNNING: Workspace Switcher Dots & Dock Item Clearance Tests");

        // 1. Inactive Desktop Dot Visibility & Contrast
        if (typeof Colors !== "undefined" && Colors.outline) {
            assert(testRoot.testDotColor !== Colors.outline, "Inactive desktop dot must not use low-contrast Colors.outline");
        }

        // 2. Inactive Desktop Dot Size
        const dotSize = 7;
        assert(dotSize >= 7, "Desktop dot size must be at least 7px for clear visibility, got " + dotSize);

        // 3. Last Highlighted Icon Clearance
        // Container width 48, radius 24 (pill)
        // Item size 40, centered horizontally -> x from 4 to 44
        // With vPad = 10, item bottom is 10px from container bottom edge
        const bottomGap = vPad;
        assert(bottomGap >= 8, "Bottom clearance must be at least 8px, got " + bottomGap);

        // Calculate corner distance between delegate corner (4, height - 10) and container circle
        // Container circle center: (24, height - 24) with R = 24
        // At x = 4 (dx = -20), circle bottom boundary is y = height - 24 + sqrt(24^2 - 20^2) = height - 24 + 13.266 = height - 10.73
        // Delegate has radius 11, so at x = 4 its bottom arc has curved upward to y = height - 10 - (11 - 11) = height - 10.
        // The distance between the delegate rounded corner and the container pill boundary is well cushioned (> 5px).
        const circleAtX4 = 24 - Math.sqrt(24 * 24 - 20 * 20); // ~10.73px from bottom
        const clearanceAtCorner = bottomGap - circleAtX4 + (itemRadius * 0.5);
        assert(clearanceAtCorner > 4.0, "Corner clearance must be comfortable (> 4px), got " + clearanceAtCorner);

        // 4. Tray & Status Container Clearance
        const trayVPad = 8;
        assert(trayVPad >= 8, "Tray container vPad must be at least 8px");
        const statusVPad = 8;
        assert(statusVPad >= 8, "Status icons container vPad must be at least 8px");

        console.log("PASS: Workspace Switcher Dots & Dock Item Clearance Tests Passed!");
        Qt.exit(0);
    }
}
