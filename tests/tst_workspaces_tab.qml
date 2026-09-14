import QtQuick
import QtQuick.Layouts
import "../components"
import "../theme"
import "../config"
import "../dashboard/tabs"

Item {
    id: testRoot
    width: 1000
    height: 800

    WorkspacesTab {
        id: wsTab
        visible: true
        anchors.fill: parent
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
        console.log("RUNNING: WorkspacesTab Unit Tests");

        // Test 1: WorkspacesTab root should NOT have an outer border / Card border
        // to prevent double borders inside the drawer
        assert(typeof wsTab.border === "undefined" || wsTab.border.width === 0,
               "WorkspacesTab must NOT have an outer border (must be seamless Item or borderless)");

        // Test 2: Verify WorkspacesTab implicit dimensions
        assert(wsTab.implicitWidth === 680, "WorkspacesTab implicitWidth should be 680");
        assert(wsTab.implicitHeight === 320, "WorkspacesTab implicitHeight should be 320");

        console.log("PASS: All WorkspacesTab unit tests passed!");
        Qt.exit(0);
    }
}
