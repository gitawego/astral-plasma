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
    property var activePreviewApp: null

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

    function simulateAppHoverEnter(app, targetY) {
        testRoot.activePreviewApp = app;
        openBottomPopout("app", targetY);
    }

    function simulateAppHoverExit() {
        scheduleCloseBottomPopout();
    }

    function simulateDrawerEnter() {
        keepBottomPopout();
    }

    function simulateDrawerExit() {
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
        console.log("RUNNING: App Preview Drawer Lifecycle Tests");

        // 1. Initial State
        assert(!testRoot.bottomPopoutVisible, "Drawer must initially be closed");

        // 2. Mouse enters dock application icon
        const mockApp = {
            id: 42,
            appId: "org.kde.dolphin",
            appName: "Dolphin",
            iconName: "system-file-manager",
            materialIcon: "folder",
            desktopFile: "org.kde.dolphin.desktop",
            title: "Downloads — Dolphin",
            isRunning: true,
            isActive: false,
            isPinned: true
        };

        simulateAppHoverEnter(mockApp, 320);

        assert(testRoot.bottomPopoutVisible, "Drawer opens on app hover");
        assert(testRoot.bottomPopoutMode === "app", "Drawer mode switches to 'app'");
        assert(testRoot.popoutTargetY === 320, "Drawer targetY is aligned to hovered app's vertical center");
        assert(testRoot.activePreviewApp !== null, "activePreviewApp is set");
        assert(testRoot.activePreviewApp.appName === "Dolphin", "activePreviewApp name matches");
        assert(testRoot.activePreviewApp.title === "Downloads — Dolphin", "activePreviewApp title matches");

        // 3. Mouse moves between two app icons seamlessly without closing
        const secondMockApp = {
            id: 88,
            appId: "com.mitchellh.ghostty",
            appName: "Ghostty",
            iconName: "com.mitchellh.ghostty",
            materialIcon: "terminal",
            desktopFile: "com.mitchellh.ghostty.desktop",
            title: "zsh — /home/user",
            isRunning: true,
            isActive: true,
            isPinned: false
        };

        // Hover second app at Y=380
        simulateAppHoverEnter(secondMockApp, 380);
        assert(testRoot.bottomPopoutVisible, "Drawer remains open when transitioning between apps");
        assert(testRoot.popoutTargetY === 380, "Drawer slides vertically to new app center");
        assert(testRoot.activePreviewApp.appName === "Ghostty", "Preview switches to new app");

        // 4. Mouse moves into drawer
        simulateAppHoverExit();
        assert(testRoot.bottomPopoutVisible, "Drawer stays open during grace timer");
        assert(popoutCloseTimer.running, "Grace timer ticking");

        simulateDrawerEnter();
        assert(!popoutCloseTimer.running, "Grace timer cancelled when inside drawer");
        assert(testRoot.bottomPopoutVisible, "Drawer stays open while inside drawer");

        // 5. Mouse moves out of drawer
        simulateDrawerExit();
        assert(popoutCloseTimer.running, "Grace timer restarted on exit");

        // 6. Action click closes drawer
        closeBottomPopout();
        assert(!testRoot.bottomPopoutVisible, "Drawer closes on action selection");

        console.log("PASS: App Preview Drawer Lifecycle Tests");
        Qt.exit(0);
    }
}
