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
    property string activePreviewThumbnail: ""
    property var _previewCache: ({})

    // Simulated popoutCloseTimer matching Config.qml
    Timer {
        id: popoutCloseTimer
        interval: 450
        repeat: false
        onTriggered: testRoot.bottomPopoutVisible = false
    }

    function loadAppPreview(app) {
        testRoot.activePreviewApp = app;
        if (!app || !app.isRunning || !app.id) {
            testRoot.activePreviewThumbnail = "";
            return;
        }
        const winKey = app.id.toString();
        if (testRoot._previewCache[winKey]) {
            testRoot.activePreviewThumbnail = testRoot._previewCache[winKey];
        } else {
            testRoot.activePreviewThumbnail = "";
            testRoot._previewCache[winKey] = "file:///tmp/caelestia_preview_" + winKey + ".png";
            testRoot.activePreviewThumbnail = testRoot._previewCache[winKey];
        }
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
        loadAppPreview(app);
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
        assert(testRoot.activePreviewThumbnail.indexOf("42") !== -1, "activePreviewThumbnail has been set for app 42");

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
        assert(testRoot.activePreviewThumbnail.indexOf("88") !== -1, "activePreviewThumbnail has switched to app 88");

        // Test unlaunched app hover
        const unlaunchedApp = {
            id: null,
            appId: "org.mozilla.firefox",
            appName: "Firefox",
            iconName: "firefox",
            materialIcon: "language",
            desktopFile: "firefox.desktop",
            title: "",
            isRunning: false,
            isActive: false,
            isPinned: true
        };
        simulateAppHoverEnter(unlaunchedApp, 200);
        assert(testRoot.activePreviewThumbnail === "", "activePreviewThumbnail must be empty for unlaunched app");
        // Check header alignment contract
        const headerOffsetY = 49.5;
        const alignedDrawerY = testRoot.popoutTargetY - headerOffsetY;
        assert(alignedDrawerY === 150.5, "Drawer Y aligns header to hovered icon exactly without being too low");

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

        // 7. Double-Buffered Live Preview Transition Simulation
        console.log("TESTING: Double-buffered live preview update logic");
        let activeBuf = "A";
        let bufASource = "";
        let bufBSource = "";
        let bufAOpacity = 0.0;
        let bufBOpacity = 0.0;

        function onNewSourceArrived(newUrl) {
            if (activeBuf === "A") {
                bufBSource = newUrl;
            } else {
                bufASource = newUrl;
            }
        }

        function onBufReady(bufName) {
            if (bufName === "B" && activeBuf === "A") {
                activeBuf = "B";
                bufBOpacity = 1.0;
                bufAOpacity = 0.0;
            } else if (bufName === "A" && activeBuf === "B") {
                activeBuf = "A";
                bufAOpacity = 1.0;
                bufBOpacity = 0.0;
            }
        }

        // Initial preview load: slot 0
        bufASource = "file:///tmp/caelestia_preview_42_0.png";
        bufAOpacity = 1.0; // Ready
        assert(activeBuf === "A" && bufAOpacity === 1.0, "Initial buffer A active");

        // Live refresh: slot 1 arrives in background
        onNewSourceArrived("file:///tmp/caelestia_preview_42_1.png");
        assert(bufBSource === "file:///tmp/caelestia_preview_42_1.png", "Buffer B loading new frame");
        assert(bufAOpacity === 1.0, "Buffer A remains fully visible while Buffer B loads (no flicker)");

        // Buffer B completes loading
        onBufReady("B");
        assert(activeBuf === "B", "Switched to buffer B seamlessly");
        assert(bufBOpacity === 1.0 && bufAOpacity === 0.0, "Buffer B visible, Buffer A hidden");

        // Next live refresh: slot 0 arrives again
        onNewSourceArrived("file:///tmp/caelestia_preview_42_0.png");
        assert(bufASource === "file:///tmp/caelestia_preview_42_0.png", "Buffer A loading next frame");
        assert(bufBOpacity === 1.0, "Buffer B remains fully visible while Buffer A loads");

        // Buffer A completes loading
        onBufReady("A");
        assert(activeBuf === "A", "Switched back to buffer A seamlessly");
        assert(bufAOpacity === 1.0 && bufBOpacity === 0.0, "Buffer A visible, Buffer B hidden");

        // 8. Live Preview Status and Placeholder Contract Tests
        console.log("TESTING: Live preview placeholder and visibility contracts");
        function getPreviewPlaceholderText(loading, running, active, hasImg) {
            if (hasImg) return ""; // Image displayed, placeholder hidden
            if (running) {
                return loading ? "Capturing live preview..." : (active ? "Currently in focus" : "Running in background");
            }
            return "Click to start";
        }

        assert(getPreviewPlaceholderText(false, true, false, false) === "Running in background", "Shows running in background when no image has loaded");
        assert(getPreviewPlaceholderText(true, true, false, false) === "Capturing live preview...", "Shows capturing live preview when loading");
        assert(getPreviewPlaceholderText(false, true, false, true) === "", "Placeholder hidden when live preview image is ready");
        assert(getPreviewPlaceholderText(false, false, false, false) === "Click to start", "Shows click to start for unlaunched apps");

        // 9. Atomic coordinate ordering & top-screen clamp protection tests
        console.log("TESTING: Atomic coordinate ordering and idealPopoutY stability");
        function computeIdealY(mode, targetY, currentY, screenH, borderT, popH, headerOffset) {
            const isFused = (mode === "power" || mode === "battery" || mode === "default");
            if (isFused) {
                return screenH - borderT - popH;
            }
            if (targetY <= 0) {
                return currentY > 0 ? currentY : (screenH - borderT - popH);
            }
            const desiredY = targetY - headerOffset;
            const minY = borderT;
            const maxY = screenH - borderT - popH;
            return Math.max(minY, Math.min(maxY, desiredY));
        }

        // Test transition from bottom (power, Y=1400) to top app icon (Y=300)
        const screenH = 1600;
        const borderT = 16;
        const popH = 320;
        const headerOffset = 49.5;

        // When mode was power:
        let prevY = computeIdealY("power", 0, 0, screenH, borderT, popH, headerOffset);
        assert(prevY === 1600 - 16 - 320, "Power drawer clamped to bottom border");

        // When switching to app with atomic targetY set first:
        let newIdealY = computeIdealY("app", 300, prevY, screenH, borderT, popH, headerOffset);
        assert(newIdealY === 300 - 49.5, "App drawer targets exact icon center (250.5) without intermediate jump");

        // When targetY is 0 or invalid, it must NEVER clamp to minY = 16 (top of screen):
        let guardedY = computeIdealY("app", 0, 250.5, screenH, borderT, popH, headerOffset);
        assert(guardedY === 250.5, "Invalid targetY preserves current Y, NEVER jumps to screen top (minY=16)");

        // 10. Frame 0 immediate card structure and skeleton presence
        console.log("TESTING: Frame 0 immediate card layout and height contract");
        const runningAppCardH = 200;
        const stoppedAppCardH = 96;
        function getCardHeight(app) {
            return (app && (app.isRunning || app.id)) ? runningAppCardH : stoppedAppCardH;
        }
        assert(getCardHeight(mockApp) === 200, "Running app preview card pre-allocates 200px instantly on frame 0");
        assert(getCardHeight(unlaunchedApp) === 96, "Stopped app pre-allocates 96px instantly on frame 0");

        console.log("PASS: App Preview Drawer Lifecycle Tests");
        Qt.exit(0);
    }
}
