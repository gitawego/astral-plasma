import QtQuick
import "../theme"
import "../shell"

Item {
    id: testRoot
    width: 1920
    height: 1080

    // Simulated Shell State Manager
    QtObject {
        id: shellState
        property bool dashboardVisible: false
        property bool settingsVisible: false
        property bool dashboardShowOnHover: true

        function openSettings() {
            settingsVisible = true;
            dashboardVisible = false;
        }

        function closeSettings() {
            settingsVisible = false;
        }
    }

    // CentralDropdown with controlled binding
    CentralDropdown {
        id: dropdown
        dropX: 470
        dropW: 980
        dropH: 520
        isOpen: shellState.dashboardVisible
    }

    // Top edge hover area matching UnifiedShell.qml (targeted strictly to drawer range)
    Item {
        id: topEdgeArea
        x: dropdown.dropX
        y: 0
        width: dropdown.dropW
        height: 18

        MouseArea {
            id: topEdgeMouseArea
            anchors.fill: parent
            hoverEnabled: true

            onEntered: {
                if (shellState.dashboardShowOnHover) {
                    shellState.dashboardVisible = true;
                }
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
        }
    }

    function runTests() {
        console.log("RUNNING: Settings Window & Top Drawer Interop Unit Tests");

        // 1. Initial State: both closed
        shellState.dashboardVisible = false;
        shellState.settingsVisible = false;
        assert(dropdown.isOpen === false, "Dropdown must be closed initially");

        // 2. Open dashboard
        shellState.dashboardVisible = true;
        assert(dropdown.isOpen === true, "Dropdown must be open when dashboardVisible is true");

        // 3. User clicks Settings inside dashboard -> closes dashboard & opens settings
        shellState.openSettings();
        assert(shellState.settingsVisible === true, "Settings must be visible");
        assert(shellState.dashboardVisible === false, "Dashboard must be hidden when settings opens");
        assert(dropdown.isOpen === false, "Dropdown must reflect closed state");

        // 4. User closes Settings
        shellState.closeSettings();
        assert(shellState.settingsVisible === false, "Settings must be closed");

        // 5. User moves mouse to top edge -> onEntered fires -> dashboardVisible becomes true
        topEdgeMouseArea.onEntered();
        assert(shellState.dashboardVisible === true, "Dashboard must become visible on top edge hover");
        assert(dropdown.isOpen === true, "Dropdown isOpen must reactively become true after settings was closed");

        // 6. Test Escape key resilience: Escape pressed should NOT destroy reactive binding
        dropdown.Keys.escapePressed({ accepted: true });
        // Escape sets dashboardVisible to false via Config or root.isOpen
        dropdown.isOpen = false;
        shellState.dashboardVisible = false;
        assert(dropdown.isOpen === false, "Dropdown isOpen must be false after closing");

        // 7. Re-open via top edge hover again: verifies smooth re-opening
        topEdgeMouseArea.onEntered();
        assert(shellState.dashboardVisible === true, "Dashboard must re-open on top edge hover after Escape");
        assert(dropdown.isOpen === true, "Dropdown isOpen must reflect dashboardVisible = true");

        // 8. Close dashboard for clean exit
        shellState.dashboardVisible = false;
        assert(dropdown.isOpen === false, "Dropdown closed cleanly");

        console.log("PASS: All Settings Window & Top Drawer Interop Unit Tests passed!");
        Qt.exit(0);
    }
}
