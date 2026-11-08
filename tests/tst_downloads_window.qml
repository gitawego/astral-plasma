import QtQuick

/// The download manager is a real desktop window, opened from the drawer.
///
/// The drawer (`DownloadsTab`) stays the quick view; the dedicated window is a
/// normal xdg-toplevel like the Copilot and Settings windows, so it stacks,
/// moves, resizes and appears in Alt+Tab. Both hosts render the same tab, and
/// the drawer's "open in window" action closes the layer-shell drawer first
/// (a layer surface would otherwise stay above the new window).
Item {
    id: testRoot
    width: 800
    height: 600

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

    Component.onCompleted: {
        console.log("RUNNING: Downloads Window Toplevel Contract");

        // 1. The window itself: a real toplevel, not a layer surface.
        const winSrc = readLocalFile("../shell/DownloadsWindow.qml");
        assert(winSrc.length > 1000, "DownloadsWindow.qml must exist");
        assert(/FloatingWindow\s*\{/.test(winSrc),
            "DownloadsWindow must be a FloatingWindow (real xdg-toplevel), like the Copilot");
        assert(!/PanelWindow\s*\{/.test(winSrc) && !/WlrLayershell/.test(winSrc),
            "DownloadsWindow must not be a layer-shell surface: those never appear in Alt+Tab");
        assert(/title:\s*"Astral Downloads"/.test(winSrc),
            "DownloadsWindow must carry a window title for Alt+Tab and taskbars");
        assert(/visible:\s*Config\.downloadsWindowVisible/.test(winSrc),
            "DownloadsWindow must map exactly while the manager is open");
        assert(/screen:\s*targetScreen/.test(winSrc),
            "DownloadsWindow must place the toplevel on the target screen");
        assert(/implicitWidth:/.test(winSrc) && /implicitHeight:/.test(winSrc),
            "DownloadsWindow must publish its opening size before mapping");
        assert(/minimumSize:/.test(winSrc) && /maximumSize:/.test(winSrc),
            "DownloadsWindow must travel its resize limits as size hints");
        assert(/BackgroundEffect\.blurRegion/.test(winSrc),
            "DownloadsWindow must apply compositor blurRegion to its glass card");
        assert(/DownloadsTab\s*\{/.test(winSrc) && /windowMode:\s*true/.test(winSrc),
            "DownloadsWindow must host the same DownloadsTab in window mode");
        assert(/onCloseRequested:\s*Config\.closeDownloadsWindow\(\)/.test(winSrc),
            "the window close control must close the manager");

        // Re-clicking the drawer action while the window is already open must
        // bring it back to the foreground, not silently do nothing.
        assert(/function raiseWindow\(\)/.test(winSrc),
            "DownloadsWindow must expose raiseWindow()");
        assert(winSrc.indexOf("WindowService.activateWindowByTitle") >= 0,
            "raiseWindow must activate the toplevel by caption (shell windows have no UUID in the watcher list)");
        const windowSvcSrc = readLocalFile("../modules/Astral/Kernel/services/WindowService.qml");
        assert(/function activateWindowByTitle\(title\)/.test(windowSvcSrc)
               && windowSvcSrc.indexOf("\"activate-title\"") >= 0,
            "WindowService must route caption activation to the daemon's activate-title verb");
        assert(/onDownloadsWindowRequested/.test(winSrc),
            "the window must listen for the open/raise request");

        // 2. State + transitions in Config.
        const cfgSrc = readLocalFile("../modules/Astral/Kernel/config/Config.qml");
        assert(/property bool downloadsWindowVisible/.test(cfgSrc),
            "Config must own the downloads window visibility");
        for (const fn of ["openDownloadsWindow", "closeDownloadsWindow", "toggleDownloadsWindow"]) {
            assert(cfgSrc.indexOf("function " + fn + "(") >= 0,
                "Config must expose " + fn + "()");
        }
        const openBlock = /function openDownloadsWindow\(\)\s*\{([\s\S]*?)\n    \}/.exec(cfgSrc);
        assert(openBlock !== null, "openDownloadsWindow must have a body");
        assert(/downloadsWindowVisible\s*=\s*true/.test(openBlock[1]),
            "openDownloadsWindow must show the window");
        assert(/dashboardVisible\s*=\s*false/.test(openBlock[1]),
            "openDownloadsWindow must close the layer-shell drawer first");
        assert(/downloadsWindowRequested\(\)/.test(openBlock[1]),
            "every open request must signal the window to raise itself");

        // 3. The drawer exposes the action and adapts to its host.
        const tabSrc = readLocalFile("../dashboard/tabs/DownloadsTab.qml");
        assert(/property bool windowMode/.test(tabSrc),
            "DownloadsTab must know whether it is hosted in the window");
        assert(/property var windowHandle/.test(tabSrc),
            "DownloadsTab must receive the hosting window for native drag");
        assert(/signal closeRequested\(\)/.test(tabSrc),
            "DownloadsTab must signal the window close action");
        assert(/Config\.openDownloadsWindow\(\)/.test(tabSrc),
            "the drawer header must offer opening the dedicated window");
        assert(/startSystemMove/.test(tabSrc),
            "the window header must start a compositor-native move");
        assert(/Layout\.fillHeight:\s*true/.test(tabSrc),
            "the task list must fill the taller window instead of staying at four rows");

        // 4. The shell mounts the window and exposes IPC for scripts/tests.
        const shellSrc = readLocalFile("../shell.qml");
        assert(/DownloadsWindow\s*\{/.test(shellSrc),
            "shell.qml must mount the downloads window");
        assert(/target:\s*"downloads"/.test(shellSrc),
            "shell.qml must expose a downloads IPC target");
        assert(/function open\(\)[\s\S]{0,120}openDownloadsWindow\(\)/.test(shellSrc),
            "the downloads IPC must open the window");

        console.log("PASS: Downloads Window Toplevel Contract");
        Qt.exit(0);
    }
}
