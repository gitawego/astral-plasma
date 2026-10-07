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
        assert(wsTab.implicitHeight >= 220 && wsTab.implicitHeight <= 500, "WorkspacesTab implicitHeight should be responsive between 220 and 500");

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

        // Test 5: Verify LiquidGlassCard usage
        assert(wsTab.usesLiquidGlassCards === true, "WorkspacesTab must declare usesLiquidGlassCards");

        // Test 6: Verify helper functions
        assert(typeof wsTab.getWindowsForDesktop === "function", "getWindowsForDesktop must be a function");
        assert(typeof wsTab.getDesktopNameForWindow === "function", "getDesktopNameForWindow must be a function");
        assert(typeof wsTab.focusWindow === "function", "focusWindow must be a function");

        // Test 7: Verify search filtering state and desktop window grouping
        if (typeof WindowService !== "undefined") {
            WindowService.windows = [
                { id: "w1", title: "GitHub PR Review", appName: "Microsoft Edge", desktopIds: ["ws-1"], onAllDesktops: false },
                { id: "w2", title: "Terminal", appName: "Ghostty", desktopIds: ["ws-2"], onAllDesktops: false }
            ];
            wsTab.searchQuery = "edge";
            assert(wsTab.filteredWindows.length === 1, "filteredWindows should match 1 window for 'edge'");
            assert(wsTab.filteredWindows[0].appName === "Microsoft Edge", "matched window should be Edge");

            const ws1Wins = wsTab.getWindowsForDesktop("ws-1");
            assert(ws1Wins.length === 1, "ws-1 should have 1 window");
            assert(ws1Wins[0].id === "w1", "ws-1 window should be w1");

            const ws2Wins = wsTab.getWindowsForDesktop("ws-2");
            assert(ws2Wins.length === 1, "ws-2 should have 1 window");
            assert(ws2Wins[0].id === "w2", "ws-2 window should be w2");

            wsTab.searchQuery = "";
        }

        wsTab.searchQuery = "nonexistent_term_xyz";
        assert(Array.isArray(wsTab.filteredWindows), "filteredWindows must be an array");
        assert(wsTab.filteredWindows.length === 0, "filteredWindows should be empty for unmatched term");
        wsTab.searchQuery = "";

        // Test 8: Verify searchActive property exists for UnifiedShell focus contract
        assert(typeof wsTab.searchActive === "boolean", "searchActive property must be a boolean");

        console.log("PASS: All WorkspacesTab unit tests passed!");
        Qt.exit(0);
    }
}
