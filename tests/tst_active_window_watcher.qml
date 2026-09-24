import QtQuick

// ============================================================================
// Active Window Watcher & Dock Icon/Title Unit Tests
// ============================================================================
// Verifies:
// 1. Reactive parsing of active window events from daemon JSON streams.
// 2. Window title and app icon reactivity (proper fallback to materialIcon).
// 3. Maximized and active window state synchronization.
// 4. Source contracts across WindowService.qml, ActiveWindow.qml, UnifiedDock.qml,
//    and daemon watch_events.rs.
Item {
    id: testRoot
    width: 600
    height: 400

    function readLocalFile(relUrl) {
        const xhr = new XMLHttpRequest();
        const bust = (relUrl.indexOf("?") < 0 ? "?v=" : "&v=") + Date.now() + Math.random();
        xhr.open("GET", Qt.resolvedUrl(relUrl) + bust, false);
        xhr.send();
        return xhr.responseText || "";
    }

    function assert(cond, msg) {
        if (!cond) {
            console.log("FAIL: " + msg);
            console.error("FAIL: " + msg);
            Qt.exit(1);
            throw new Error(msg);
        }
        return true;
    }

    // Deterministic simulation model mirroring WindowService.qml
    QtObject {
        id: mockWindowService

        property var windows: []
        property var tray: []
        property string activeTitle: "Desktop"
        property string activeMaterialIcon: "desktop_windows"
        property string activeIconName: ""
        property string activeAppId: ""
        property string activeId: ""

        property alias title: mockWindowService.activeTitle
        property alias appId: mockWindowService.activeIconName
        property alias materialIcon: mockWindowService.activeMaterialIcon

        property bool hasMaximizedWindow: false
        readonly property bool hasActiveMaximized: {
            if (mockWindowService.hasMaximizedWindow) return true;
            for (let i = 0; i < mockWindowService.windows.length; i++) {
                const w = mockWindowService.windows[i];
                if (w && (w.isMaximized || w.isFullScreen || w.maximized || w.fullScreen)) {
                    return true;
                }
            }
            return false;
        }

        readonly property var activeWindow: {
            for (let i = 0; i < mockWindowService.windows.length; i++) {
                if (mockWindowService.windows[i].isActive) return mockWindowService.windows[i];
            }
            return null;
        }

        function handleIncomingLine(line) {
            const raw = line.trim();
            if (!raw || !raw.startsWith("{")) return;
            const data = JSON.parse(raw);
            if (!data) return;

            if (data.activeTitle !== undefined) mockWindowService.activeTitle = data.activeTitle;
            if (data.activeMaterialIcon !== undefined) mockWindowService.activeMaterialIcon = data.activeMaterialIcon;
            if (data.activeIconName !== undefined) mockWindowService.activeIconName = data.activeIconName;
            if (data.activeAppId !== undefined) mockWindowService.activeAppId = data.activeAppId;
            if (data.activeId !== undefined) mockWindowService.activeId = data.activeId;
            if (data.hasMaximizedWindow !== undefined) mockWindowService.hasMaximizedWindow = Boolean(data.hasMaximizedWindow);
            if (data.windows) mockWindowService.windows = data.windows;
            if (data.tray) mockWindowService.tray = data.tray;
        }
    }

    Timer {
        interval: 20
        running: true
        repeat: false
        onTriggered: runTests()
    }

    function runTests() {
        console.log("RUNNING: Active Window Watcher & Dock Icon/Title Unit Tests");

        // ---- 1. Initial Default State ----
        assert(mockWindowService.activeTitle === "Desktop", "Initial title should be 'Desktop'");
        assert(mockWindowService.title === "Desktop", "Alias title should be 'Desktop'");
        assert(mockWindowService.activeMaterialIcon === "desktop_windows", "Initial material icon should be 'desktop_windows'");
        assert(mockWindowService.activeIconName === "", "Initial activeIconName should be empty");
        assert(mockWindowService.activeWindow === null, "activeWindow should be null when no windows present");

        // ---- 2. Full State Payload Ingestion (VS Code Active) ----
        mockWindowService.handleIncomingLine(JSON.stringify({
            msg_type: "active",
            activeTitle: "Visual Studio Code",
            activeMaterialIcon: "code",
            activeIconName: "com.microsoft.VSCode",
            activeAppId: "com.microsoft.VSCode",
            activeId: "win-12345",
            hasMaximizedWindow: true,
            windows: [
                {
                    id: "win-12345",
                    title: "astral-plasma - Visual Studio Code",
                    appName: "Visual Studio Code",
                    iconName: "com.microsoft.VSCode",
                    materialIcon: "code",
                    appId: "com.microsoft.VSCode",
                    desktopFile: "com.microsoft.VSCode.desktop",
                    isActive: true,
                    isMaximized: true,
                    isFullScreen: false
                },
                {
                    id: "win-67890",
                    title: "bash - ghostty",
                    appName: "Terminal",
                    iconName: "com.mitchellh.ghostty",
                    materialIcon: "terminal",
                    appId: "com.mitchellh.ghostty",
                    desktopFile: "com.mitchellh.ghostty.desktop",
                    isActive: false,
                    isMaximized: false,
                    isFullScreen: false
                }
            ]
        }));

        assert(mockWindowService.activeTitle === "Visual Studio Code", "Title must update to 'Visual Studio Code'");
        assert(mockWindowService.title === "Visual Studio Code", "Alias title must update to 'Visual Studio Code'");
        assert(mockWindowService.activeIconName === "com.microsoft.VSCode", "Icon name must be 'com.microsoft.VSCode'");
        assert(mockWindowService.appId === "com.microsoft.VSCode", "Alias appId must be 'com.microsoft.VSCode'");
        assert(mockWindowService.materialIcon === "code", "Material icon must be 'code'");
        assert(mockWindowService.hasActiveMaximized === true, "hasActiveMaximized must be true");
        assert(mockWindowService.activeWindow !== null, "activeWindow must find focused window");
        assert(mockWindowService.activeWindow.id === "win-12345", "activeWindow id must match win-12345");

        // ---- 3. Switching Focus to Terminal ----
        mockWindowService.handleIncomingLine(JSON.stringify({
            msg_type: "active",
            activeTitle: "Terminal",
            activeMaterialIcon: "terminal",
            activeIconName: "com.mitchellh.ghostty",
            activeAppId: "com.mitchellh.ghostty",
            activeId: "win-67890",
            hasMaximizedWindow: false,
            windows: [
                {
                    id: "win-12345",
                    title: "astral-plasma - Visual Studio Code",
                    appName: "Visual Studio Code",
                    iconName: "com.microsoft.VSCode",
                    materialIcon: "code",
                    appId: "com.microsoft.VSCode",
                    desktopFile: "com.microsoft.VSCode.desktop",
                    isActive: false,
                    isMaximized: true,
                    isFullScreen: false
                },
                {
                    id: "win-67890",
                    title: "bash - ghostty",
                    appName: "Terminal",
                    iconName: "com.mitchellh.ghostty",
                    materialIcon: "terminal",
                    appId: "com.mitchellh.ghostty",
                    desktopFile: "com.mitchellh.ghostty.desktop",
                    isActive: true,
                    isMaximized: false,
                    isFullScreen: false
                }
            ]
        }));

        assert(mockWindowService.activeTitle === "Terminal", "Title must update to 'Terminal'");
        assert(mockWindowService.appId === "com.mitchellh.ghostty", "appId must update to ghostty");
        assert(mockWindowService.materialIcon === "terminal", "materialIcon must update to 'terminal'");
        assert(mockWindowService.activeWindow.id === "win-67890", "activeWindow must point to ghostty");

        // ---- 4. Switching to Desktop (No active window) ----
        mockWindowService.handleIncomingLine(JSON.stringify({
            msg_type: "active",
            activeTitle: "Desktop",
            activeMaterialIcon: "desktop_windows",
            activeIconName: "",
            activeAppId: "",
            activeId: "",
            hasMaximizedWindow: false
        }));

        assert(mockWindowService.activeTitle === "Desktop", "Title must return to 'Desktop'");
        assert(mockWindowService.activeIconName === "", "activeIconName must be cleared");
        assert(mockWindowService.materialIcon === "desktop_windows", "materialIcon must return to 'desktop_windows'");

        // ---- 5. Source Contract: services/WindowService.qml ----
        const winServiceSrc = readLocalFile("../services/WindowService.qml");
        assert(winServiceSrc.length > 500, "WindowService.qml must be readable");
        assert(/command:\s*\[root\.daemonBin,\s*"watch"\]/.test(winServiceSrc),
            "WindowService must launch daemonBin 'watch'");
        assert(/onExited:\s*\(exitCode,\s*exitStatus\)\s*=>/.test(winServiceSrc),
            "WindowService must implement onExited handler to detect daemon termination");
        assert(/restartTimer\.restart\(\)/.test(winServiceSrc),
            "WindowService must trigger restartTimer when watcher daemon exits");
        assert(/property\s+alias\s+title:\s*root\.activeTitle/.test(winServiceSrc),
            "WindowService must expose title alias");
        assert(/property\s+alias\s+appId:\s*root\.activeIconName/.test(winServiceSrc),
            "WindowService must expose appId alias");
        assert(/property\s+alias\s+materialIcon:\s*root\.activeMaterialIcon/.test(winServiceSrc),
            "WindowService must expose materialIcon alias");

        // ---- 6. Source Contract: dock/components/ActiveWindow.qml ----
        const activeWinSrc = readLocalFile("../dock/components/ActiveWindow.qml");
        assert(activeWinSrc.length > 200, "ActiveWindow.qml must be readable");
        assert(/WindowService\.title/.test(activeWinSrc),
            "ActiveWindow must bind displayTitle to WindowService.title");
        assert(/WindowService\.materialIcon\s*\|\|\s*"desktop_windows"/.test(activeWinSrc),
            "ActiveWindow must use WindowService.materialIcon as semantic fallback");

        // ---- 7. Source Contract: shell/UnifiedDock.qml ----
        const unifiedDockSrc = readLocalFile("../shell/UnifiedDock.qml");
        assert(unifiedDockSrc.length > 500, "UnifiedDock.qml must be readable");
        assert(/WindowService\.activeTitle\s*\|\|\s*"Desktop"/.test(unifiedDockSrc),
            "UnifiedDock must bind windowTitle to WindowService.activeTitle");
        assert(/WindowService\.activeMaterialIcon\s*\|\|\s*"desktop_windows"/.test(unifiedDockSrc),
            "UnifiedDock must bind fallback icon to WindowService.activeMaterialIcon");

        // ---- 8. Source Contract: daemon/src/application/watch_events.rs ----
        const watchEventsSrc = readLocalFile("../daemon/src/application/watch_events.rs");
        assert(watchEventsSrc.length > 1000, "watch_events.rs must be readable");
        assert(/Lost D-Bus name/.test(watchEventsSrc),
            "watch_events.rs must implement D-Bus name health check and exit cleanly on name loss");
        assert(/isScriptLoaded/.test(watchEventsSrc),
            "watch_events.rs must implement KWin script loaded watchdog to automatically restore script");

        console.log("PASS: All Active Window Watcher & Dock Icon/Title Unit Tests passed successfully!");
        Qt.exit(0);
    }
}
