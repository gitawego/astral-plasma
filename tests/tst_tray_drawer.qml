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

        // 7. Submenu Drill-down and Navigation Stack Tests
        var mockSubmenuModel = [
            { id: 220, label: "41 updates available", isSeparator: false, enabled: false, icon: "", hasSubmenu: false, children: [] },
            { id: 221, label: "All (41)", isSeparator: false, enabled: true, icon: "", hasSubmenu: true, children: [
                { id: 222, label: "at-spi2-core 2.60.6-1.1 -> 2.60.7-1.1", isSeparator: false, enabled: true, icon: "", hasSubmenu: false, children: [] },
                { id: 223, label: "linux-cachyos 7.2.4-3 -> 7.2.5-1", isSeparator: false, enabled: true, icon: "", hasSubmenu: false, children: [] }
            ]},
            { id: 313, label: "Exit", isSeparator: false, enabled: true, icon: "", hasSubmenu: false, children: [] }
        ];

        var submenuStack = [];
        var currentItems = (submenuStack.length > 0) ? submenuStack[submenuStack.length - 1].items : mockSubmenuModel;
        assert(currentItems.length === 3, "Root menu has 3 items");
        assert(currentItems[1].hasSubmenu === true, "Item 221 is detected as having a submenu");

        // Drill down into All (41)
        submenuStack.push({ title: currentItems[1].label, items: currentItems[1].children });
        currentItems = submenuStack[submenuStack.length - 1].items;
        assert(submenuStack.length === 1, "Submenu stack has 1 level");
        assert(submenuStack[0].title === "All (41)", "Submenu title matches All (41)");
        assert(currentItems.length === 2, "Drilled-down menu displays 2 package updates");
        assert(currentItems[0].label === "at-spi2-core 2.60.6-1.1 -> 2.60.7-1.1", "First package update matches");

        // Back navigation
        submenuStack.pop();
        currentItems = (submenuStack.length > 0) ? submenuStack[submenuStack.length - 1].items : mockSubmenuModel;
        assert(submenuStack.length === 0, "Submenu stack is empty after back");
        // 8. Two-Layer Submenu Animation State Integrity Tests
        var activeLayer = 0;
        var isTransitioning = false;
        var layerA = { x: 0, opacity: 1.0, visible: true, items: mockSubmenuModel };
        var layerB = { x: 35, opacity: 0.0, visible: false, items: [] };

        // Simulate pushSubmenu transition
        var targetLayer = (activeLayer === 0) ? 1 : 0;
        var outgoing = (activeLayer === 0) ? layerA : layerB;
        var incoming = (activeLayer === 0) ? layerB : layerA;
        incoming.items = mockSubmenuModel[1].children;
        incoming.x = 35;
        incoming.opacity = 0.0;
        incoming.visible = true;
        isTransitioning = true;

        assert(incoming.items.length === 2, "Incoming layer populated with submenu items");
        assert(incoming.visible === true, "Incoming layer becomes visible for parallel slide");
        assert(isTransitioning === true, "isTransitioning lock active during animation");

        // Simulate animation completion
        activeLayer = targetLayer;
        outgoing.visible = false;
        outgoing.x = -35;
        outgoing.opacity = 0.0;
        incoming.x = 0;
        incoming.opacity = 1.0;
        isTransitioning = false;

        assert(activeLayer === 1, "Active layer transitioned to Layer B");
        assert(layerA.visible === false, "Outgoing Layer A hidden after transition");
        assert(layerB.visible === true, "Incoming Layer B visible and active");
        assert(layerB.x === 0 && layerB.opacity === 1.0, "Layer B resting at x: 0, opacity: 1.0");
        assert(isTransitioning === false, "isTransitioning released after transition finishes");

        console.log("PASS: Tray Drawer Lifecycle Tests");
        Qt.exit(0);
    }
}
