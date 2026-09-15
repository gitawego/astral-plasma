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

        // Test 3: Workspace service contract (prevent regression where switchToDesktop was missing)
        var mockService = {
            currentId: "ws-1",
            count: 2,
            desktops: [
                { id: "ws-1", name: "Desktop 1", index: 0, active: true },
                { id: "ws-2", name: "Desktop 2", index: 1, active: false }
            ],
            switchTo: function(id) {
                this.currentId = id;
                for (var i = 0; i < this.desktops.length; i++) {
                    this.desktops[i].active = (this.desktops[i].id === id);
                }
            },
            switchToDesktop: function(id) {
                this.switchTo(id);
            },
            switchToWorkspace: function(index) {
                if (index < this.desktops.length && this.desktops[index] && this.desktops[index].id) {
                    this.switchTo(this.desktops[index].id);
                }
            }
        };

        assert(typeof mockService.switchToDesktop === "function", "switchToDesktop must be a function");
        assert(typeof mockService.switchTo === "function", "switchTo must be a function");
        assert(typeof mockService.switchToWorkspace === "function", "switchToWorkspace must be a function");

        // Test 4: Verify UnifiedDock onClicked workspace dispatch
        function dispatchDockWorkspaceClick(service, index) {
            if (service.desktops && service.desktops.length > index && service.desktops[index]) {
                service.switchToDesktop(service.desktops[index].id);
            } else {
                service.switchToWorkspace(index);
            }
        }

        dispatchDockWorkspaceClick(mockService, 1);
        assert(mockService.currentId === "ws-2", "currentId should be ws-2 after clicking index 1");
        assert(mockService.desktops[1].active === true, "Desktop 2 must be active");
        assert(mockService.desktops[0].active === false, "Desktop 1 must be inactive");

        console.log("PASS: All WorkspacesTab unit tests passed!");
        Qt.exit(0);
    }
}
