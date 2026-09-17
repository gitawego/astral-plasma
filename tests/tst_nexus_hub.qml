import QtQuick

Item {
    id: testRoot
    width: 800
    height: 600

    // Harness matching NexusHub navigation stack architecture
    QtObject {
        id: nexusHarness

        property string activePage: "wallpaper"
        property var pageHistory: []
        readonly property bool canGoBack: pageHistory.length > 0

        function navigateTo(pageId) {
            if (!pageId || pageId === activePage) return;
            let h = pageHistory.slice();
            h.push(activePage);
            pageHistory = h;
            activePage = pageId;
        }

        function goBack() {
            if (pageHistory.length > 0) {
                let h = pageHistory.slice();
                const prev = h.pop();
                pageHistory = h;
                activePage = prev;
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
            return false;
        }
        return true;
    }

    function runTests() {
        console.log("RUNNING: NexusHub Hierarchical Navigation & Back Stack Unit Tests");

        // 1. Initial State: defaults to wallpaper, cannot go back
        assert(nexusHarness.activePage === "wallpaper", "Default page must be wallpaper");
        assert(!nexusHarness.canGoBack, "Initial back stack must be empty");

        // 2. Navigate to Network page
        nexusHarness.navigateTo("network");
        assert(nexusHarness.activePage === "network", "Active page must be network");
        assert(nexusHarness.canGoBack === true, "Back stack must have 1 entry");
        assert(nexusHarness.pageHistory[0] === "wallpaper", "History entry 0 must be wallpaper");

        // 3. Drill down to Bluetooth
        nexusHarness.navigateTo("bluetooth");
        assert(nexusHarness.activePage === "bluetooth", "Active page must be bluetooth");
        assert(nexusHarness.pageHistory.length === 2, "History has 2 entries");

        // 4. Drill down to Audio
        nexusHarness.navigateTo("audio");
        assert(nexusHarness.activePage === "audio", "Active page must be audio");

        // 5. Click < Back (pop audio -> back to bluetooth)
        nexusHarness.goBack();
        assert(nexusHarness.activePage === "bluetooth", "goBack returns to bluetooth");

        // 6. Click < Back (pop bluetooth -> back to network)
        nexusHarness.goBack();
        assert(nexusHarness.activePage === "network", "goBack returns to network");

        // 7. Click < Back (pop network -> back to wallpaper)
        nexusHarness.goBack();
        assert(nexusHarness.activePage === "wallpaper", "goBack returns to root wallpaper");
        assert(!nexusHarness.canGoBack, "Back button hides when at root page");

        console.log("PASS: NexusHub Hierarchical Navigation & Back Stack Unit Tests");
        Qt.exit(0);
    }
}
