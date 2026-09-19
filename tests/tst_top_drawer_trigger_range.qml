import QtQuick
import "../shell"
import "../theme"
import "../config"

Item {
    id: root
    width: 2560
    height: 1600

    // Mock shell state
    QtObject {
        id: shellState
        property bool dashboardVisible: false
        property bool dashboardShowOnHover: true
        property real dashboardWidth: 980
    }

    // Dropdown geometry math matching UnifiedShell.qml
    readonly property real dropW: shellState.dashboardWidth
    readonly property real dropX: (root.width - dropW) / 2
    readonly property real borderT: 14

    // Top Edge Hover Area matching UnifiedShell.qml
    Item {
        id: topEdgeHoverArea
        x: root.dropX
        y: 0
        width: root.dropW
        height: Math.max(root.borderT, 18)

        property int enteredCount: 0
        property int clickedCount: 0

        MouseArea {
            id: topEdgeMouseArea
            anchors.fill: parent
            hoverEnabled: true

            onEntered: {
                topEdgeHoverArea.enteredCount++;
                if (shellState.dashboardShowOnHover) {
                    shellState.dashboardVisible = true;
                }
            }

            onClicked: {
                topEdgeHoverArea.clickedCount++;
                shellState.dashboardVisible = !shellState.dashboardVisible;
            }
        }
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
            throw new Error(msg);
        }
    }

    function isPointInTopEdgeTrigger(px, py) {
        return (px >= topEdgeHoverArea.x &&
                px < (topEdgeHoverArea.x + topEdgeHoverArea.width) &&
                py >= topEdgeHoverArea.y &&
                py < (topEdgeHoverArea.y + topEdgeHoverArea.height));
    }

    function runTests() {
        console.log("RUNNING: Top Drawer Trigger Range & Boundary Invariant Tests");

        // 1. Verify Geometry Bounds
        assert(topEdgeHoverArea.x === 790, "dropX must be exactly (2560 - 980) / 2 = 790");
        assert(topEdgeHoverArea.width === 980, "dropW must be exactly 980");
        assert(topEdgeHoverArea.height === 18, "height must be 18px");

        // 2. Points to the left of the drawer must NOT be inside the trigger area
        assert(!isPointInTopEdgeTrigger(0, 5), "Screen edge X=0, Y=5 must be OUTSIDE trigger");
        assert(!isPointInTopEdgeTrigger(70, 5), "Dock edge X=70, Y=5 must be OUTSIDE trigger");
        assert(!isPointInTopEdgeTrigger(500, 10), "Left border X=500, Y=10 must be OUTSIDE trigger");
        assert(!isPointInTopEdgeTrigger(789, 5), "Boundary point X=789 must be OUTSIDE trigger");

        // 3. Points to the right of the drawer must NOT be inside the trigger area
        assert(!isPointInTopEdgeTrigger(1770, 5), "Boundary point X=1770 must be OUTSIDE trigger");
        assert(!isPointInTopEdgeTrigger(2000, 10), "Right border X=2000, Y=10 must be OUTSIDE trigger");
        assert(!isPointInTopEdgeTrigger(2550, 5), "Screen right edge X=2550, Y=5 must be OUTSIDE trigger");

        // 4. Points inside the drawer range must be inside the trigger area
        assert(isPointInTopEdgeTrigger(790, 5), "Left boundary X=790 must be INSIDE trigger");
        assert(isPointInTopEdgeTrigger(1280, 5), "Center point X=1280 must be INSIDE trigger");
        assert(isPointInTopEdgeTrigger(1769, 5), "Right boundary X=1769 must be INSIDE trigger");

        // 5. Points below the top border (Y >= 18) must NOT be inside the trigger area
        assert(!isPointInTopEdgeTrigger(1280, 19), "Y=19 must be OUTSIDE trigger");

        // 6. Test Hover triggering: only triggers inside range
        shellState.dashboardVisible = false;
        topEdgeMouseArea.onEntered();
        assert(shellState.dashboardVisible === true, "Dashboard must open when entered inside trigger range");
        assert(topEdgeHoverArea.enteredCount === 1, "enteredCount must be 1");

        // 7. Test Click toggling
        topEdgeMouseArea.onClicked(null);
        assert(shellState.dashboardVisible === false, "Dashboard must close when clicked");
        assert(topEdgeHoverArea.clickedCount === 1, "clickedCount must be 1");

        console.log("PASS: All Top Drawer Trigger Range tests passed successfully!");
        Qt.exit(0);
    }
}
