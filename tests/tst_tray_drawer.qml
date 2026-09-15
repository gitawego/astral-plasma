import QtQuick
import "../components"
import "../theme"

Item {
    id: testRoot
    width: 800
    height: 600

    property bool bottomPopoutVisible: false
    property string bottomPopoutMode: "default"
    property real popoutTargetY: 0
    property var activeTrayItem: null
    property var activeTrayMenuItems: []
    property bool activeTrayLoading: false

    // Simulated popoutCloseTimer matching Config.qml
    Timer {
        id: popoutCloseTimer
        interval: 450
        repeat: false
        onTriggered: testRoot.bottomPopoutVisible = false
    }

    function openBottomPopout(mode, targetY) {
        popoutCloseTimer.stop();
        if (mode) testRoot.bottomPopoutMode = mode;
        if (targetY !== undefined && targetY > 0) testRoot.popoutTargetY = targetY;
        testRoot.bottomPopoutVisible = true;
    }

    function keepBottomPopout() {
        popoutCloseTimer.stop();
    }

    function scheduleCloseBottomPopout() {
        popoutCloseTimer.restart();
    }

    function closeBottomPopout() {
        popoutCloseTimer.stop();
        testRoot.bottomPopoutVisible = false;
    }

    function simulateTrayEnter(item, targetY) {
        testRoot.activeTrayItem = item;
        testRoot.activeTrayLoading = false;
        testRoot.activeTrayMenuItems = [
            { id: 1, label: "Open Graphical Dashboard", isSeparator: false, enabled: true, icon: "" },
            { id: 2, label: "", isSeparator: true, enabled: true, icon: "" },
            { id: 3, label: "Quit", isSeparator: false, enabled: true, icon: "" }
        ];
        openBottomPopout("tray", targetY);
    }

    function simulateTrayLeave() {
        scheduleCloseBottomPopout();
    }

    function simulateDrawerEnter() {
        keepBottomPopout();
    }

    function simulateDrawerLeave() {
        scheduleCloseBottomPopout();
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
        console.log("RUNNING: Tray Drawer Lifecycle Tests");

        // 1. Initial State
        assert(!testRoot.bottomPopoutVisible, "Drawer must initially be closed");

        // 2. Mouse enters system tray icon
        const mockItem = {
            id: "token-tracker",
            title: "Token Tracker",
            service: "org.kde.StatusNotifierItem-3565-1",
            menuPath: "/MenuBar",
            materialIcon: "toll"
        };
        simulateTrayEnter(mockItem, 750);

        assert(testRoot.bottomPopoutVisible, "Drawer opens when hovering tray icon");
        assert(testRoot.bottomPopoutMode === "tray", "Drawer mode is 'tray'");
        assert(testRoot.popoutTargetY === 750, "Drawer targetY is aligned to icon center");
        assert(testRoot.activeTrayItem !== null, "activeTrayItem is set");
        assert(testRoot.activeTrayMenuItems.length === 3, "activeTrayMenuItems loaded");

        // 3. Mouse moves from tray icon towards drawer (in transit)
        simulateTrayLeave();
        assert(testRoot.bottomPopoutVisible, "Drawer stays visible during transit interval");
        assert(popoutCloseTimer.running, "Grace close timer is ticking");

        // 4. Mouse enters the drawer
        simulateDrawerEnter();
        assert(!popoutCloseTimer.running, "Grace timer stopped when mouse enters drawer");
        assert(testRoot.bottomPopoutVisible, "Drawer stays open while hovered");

        // 5. Mouse leaves drawer (outside of drawer and tray)
        simulateDrawerLeave();
        assert(popoutCloseTimer.running, "Grace timer ticking after leaving drawer");

        // 6. Explicit item click inside drawer closes drawer
        closeBottomPopout();
        assert(!testRoot.bottomPopoutVisible, "Drawer closes immediately upon item click");

        console.log("PASS: Tray Drawer Lifecycle Tests");
        Qt.exit(0);
    }
}
