import QtQuick

// Source contracts for the DSH web launcher.
//
// The default path opens the DSH URL as a chromeless app window in the user's
// browser (Chrome, Chromium, Edge, Firefox, in that order); the embedded
// QtWebEngine view remains as an opt-in. The safety-critical contract is that
// the embedded window is loaded ONLY when the host reports WebEngine support
// and the mode explicitly asks for it: stock Quickshell aborts on a
// WebEngineView.
Item {
    id: testRoot
    width: 400
    height: 200

    function readLocalFile(relUrl) {
        const xhr = new XMLHttpRequest();
        const bust = (relUrl.indexOf("?") < 0 ? "?v=" : "&v=") + Date.now() + Math.random();
        xhr.open("GET", Qt.resolvedUrl(relUrl) + bust, false);
        xhr.send();
        return xhr.responseText || "";
    }

    function assert(cond, msg) {
        if (!cond) {
            console.error("FAIL: " + msg);
            Qt.exit(1);
            throw new Error(msg);
        }
        return true;
    }

    Timer {
        interval: 20
        running: true
        repeat: false
        onTriggered: runTests()
    }

    function runTests() {
        // --- service: server handling + browser launch ----------------------
        const service = readLocalFile("../services/DshWebService.qml");
        assert(service.length > 1000, "DshWebService.qml must be readable");
        assert(service.indexOf("parseDshUrlLine") !== -1,
            "service must parse the authenticated URL dsh web prints");
        assert(service.indexOf("classifyProbe") !== -1,
            "service must classify the health probe");
        assert(service.indexOf("resolveCommand") !== -1,
            "service must resolve the dsh/npx start command");
        assert(service.indexOf("adoptExisting") !== -1,
            "service must adopt a server that is already running");
        assert(service.indexOf("startServer") !== -1,
            "service must start a server when none is running");
        assert(service.indexOf("detectionScript") !== -1,
            "service must detect the installed browsers");
        assert(service.indexOf("selectBrowser") !== -1,
            "service must select a browser in preference order");
        assert(service.indexOf("appModeArgs") !== -1,
            "service must build app-mode arguments");
        assert(service.indexOf("launchBrowser") !== -1,
            "service must launch the chosen browser");
        assert(service.indexOf("Quickshell.execDetached") !== -1,
            "the browser must be launched detached");
        assert(service.indexOf("xdg-open") !== -1,
            "a missing app-mode browser must fall back to the system handler");
        assert(service.indexOf("dsh-web") !== -1,
            "service must install the DeepSeek desktop identity");
        assert(service.indexOf("readonly property bool running") !== -1
                && service.indexOf("readonly property bool windowOpen") !== -1
                && service.indexOf("readonly property bool live") !== -1,
            "the service must expose live DSH state for the launcher icon");
        assert(service.indexOf("host") !== -1,
            "service must pass the DSH host to the desktop installer");
        assert(service.indexOf("applyDesktopIcon") !== -1,
            "service must apply the desktop-icon preference automatically");
        assert(service.indexOf("installDesktopIcon") !== -1,
            "service must honour the desktop-icon preference");
        assert(service.indexOf("browserChecked") !== -1,
            "service must expose that browser detection finished");
        assert(service.indexOf("defaultBrowserId") !== -1,
            "service must know the system default browser for adopted servers");
        assert(service.indexOf("defaultBrowserChecked") !== -1,
            "service must wait for the default-browser probe");
        assert(service.indexOf("browserIdFromDesktopFile") !== -1,
            "service must map the default desktop id to a browser");

        // --- embedded remains opt-in ---------------------------------------
        assert(service.indexOf("webEngineSupported") !== -1,
            "service must expose the embedded WebEngine capability");
        assert(service.indexOf("authCookie") !== -1,
            "service must keep the embedded cookie mint");

        // --- shell: gated lazy load + IPC ----------------------------------
        const shell = readLocalFile("../shell.qml");
        assert(shell.indexOf("LazyLoader") !== -1,
            "shell.qml must lazy-load the embedded window");
        assert(shell.indexOf("dsh/DshWebWindow.qml") !== -1,
            "shell.qml must point the lazy loader at the embedded window");
        assert(shell.indexOf('DshWebService.mode === "embedded"') !== -1,
            "the embedded load must be gated on embedded mode");
        assert(shell.indexOf("DshWebService.webEngineSupported") !== -1,
            "the embedded load must be gated on host WebEngine support");
        assert(shell.indexOf('target: "dshweb"') !== -1,
            "shell.qml must expose the dshweb IPC target");

        // --- config + settings ---------------------------------------------
        const config = readLocalFile("../config/Config.qml");
        assert(config.indexOf("dshWebEnabled") !== -1, "Config must expose dshWebEnabled");
        assert(config.indexOf("dshWebUrl") !== -1, "Config must expose dshWebUrl");
        assert(config.indexOf("dshWebCommand") !== -1, "Config must expose dshWebCommand");
        assert(config.indexOf("dshWebMode") !== -1, "Config must expose dshWebMode");
        assert(config.indexOf("dshWebBrowser") !== -1, "Config must expose dshWebBrowser");
        assert(config.indexOf("dshWebFirefoxKiosk") !== -1, "Config must expose dshWebFirefoxKiosk");

        const settings = readLocalFile("../config/settings.json");
        assert(settings.indexOf('"dshWeb"') !== -1, "settings.json must ship DSH web defaults");
        assert(settings.indexOf('"mode": "browser"') !== -1, "browser mode must be the shipped default");

        // --- discoverable entry points --------------------------------------
        const popout = readLocalFile("../dock/popouts/AiTokensSection.qml");
        assert(popout.indexOf("DshWebService.open()") !== -1,
            "the AI popout must offer an Open DSH Web entry point");

        // --- icon archetypes stay consistent across every surface -----------
        const materialIcon = readLocalFile("../components/MaterialIcon.qml");
        assert(materialIcon.indexOf("ThemedImage {") !== -1,
            "MaterialIcon must render app icons through the shared ThemedImage archetype");
        assert(readLocalFile("../components/ThemedIcon.qml").indexOf("ThemedImage {") !== -1,
            "ThemedIcon must share the same archetype renderer as MaterialIcon");
        const dock = readLocalFile("../shell/UnifiedDock.qml");
        assert(dock.indexOf("Config.iconUrl(modelData.iconName)") === -1,
            "the dock must not draw app icons through a raw Image");
        assert(dock.indexOf("Config.iconUrl(WindowService.activeIconName)") === -1,
            "the active-window icon must not be drawn through a raw Image");
        assert(readLocalFile("../daemon/src/infrastructure/dsh_web_desktop.rs")
                .indexOf("astral-dsh-web-symbolic") !== -1,
            "the installed DSH icon must be a symbolic template so it follows the theme");

        // --- a user-started dsh announces itself with a clickable prompt ------
        assert(service.indexOf("notify-send") !== -1,
            "the service must announce a user-started dsh server");
        assert(service.indexOf("-A", "default=Open DSH Web") !== -1,
            "the prompt must carry a default action so any click opens the view");
        assert(service.indexOf("portListeningFromProcNetTcp") !== -1,
            "the server check must be fork-free procfs parsing");
        assert(service.indexOf("procNetTcpProc") !== -1,
            "the service must have a procfs fallback for environments without XHR file reads");
        assert(service.indexOf("WindowService.activate") !== -1,
            "the service must activate existing open window when requested");
        assert(service.indexOf("interval: 20000") !== -1,
            "the watcher must be slow and idle-only (no busy polling)");

        assert(popout.indexOf("deepseek.svg") !== -1,
            "the AI popout must show DeepSeek's mark for the DSH entry");
        assert(popout.indexOf("DshWebService.windowOpen") !== -1,
            "the DSH icon must report that its web UI is on screen");
        assert(popout.indexOf("DshWebService.live") !== -1,
            "the DSH icon must show the live mark when the web UI is up");
        assert(popout.indexOf("forceColorize") !== -1,
            "the AI popout DSH mark must be themed, not brand-blue");
        assert(readLocalFile("../dock/components/DockStatusIcons.qml").indexOf("dshItem") === -1,
            "the dock must not carry the DSH icon; it lives in the AI drawer");

        const launcher = readLocalFile("../shell/CommandLauncher.qml");
        assert(launcher.indexOf('id: "dsh"') !== -1,
            "the command launcher must offer a >dsh command");
        assert(launcher.indexOf("DshWebService.open()") !== -1,
            "the >dsh command must open the DSH web app");

        const page = readLocalFile("../settings_gui/pages/AiPage.qml");
        assert(page.indexOf("Open DSH Web") !== -1,
            "Settings > AI must offer an Open DSH Web action");

        const shortcut = readLocalFile("../shortcuts/astral-dsh-web.desktop");
        assert(shortcut.indexOf("toggle_dsh_web.sh") !== -1,
            "an app-menu shortcut must launch DSH");
        assert(shortcut.indexOf("astral-dsh-web") !== -1,
            "the shortcut must use the DeepSeek icon");

        console.log("PASS: tst_dsh_web_service");
        Qt.exit(0);
    }
}
