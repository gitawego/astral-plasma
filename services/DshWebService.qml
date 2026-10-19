pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../config"
import "DshAuth.js" as DshAuth
import "DshWebLogic.js" as DshLogic

// DSH Web launcher.
//
// Two ways to show the UI, chosen by config ai.dshWeb.mode:
//   * "browser" (default): open the DSH URL in the user's own browser as a
//     chromeless app window. The browser is resolved from the desktop's own
//     WebBrowser registrations first (default browser / installed browsers), and
//     only then from PATH, in family preference order Chrome, Chromium, Edge,
//     Firefox. Registration first matters: an automation-only build such as
//     Chrome for Testing sits on PATH without being installed as a browser, and
//     it stamps a "for automated testing" banner over every page it shows.
//   * "embedded": the in-shell QtWebEngine view (dsh/DshWebWindow.qml), which
//     needs a WebEngine-enabled Quickshell (scripts/build-quickshell-webengine.sh
//     or scripts/install-quickshell-webengine-shim.sh).
//
// Server handling is shared by both: reuse a running dsh web (its own browser
// cookie authenticates the app window), or start one and use the authenticated
// URL it prints.
//
// One rule keeps every path honest: a remembered server is never assumed to be
// alive. A `dsh web` the user started in a terminal can be stopped at any moment
// and a child we spawned can die, so every observation of death (child exit,
// failed probe, the idle watcher seeing the port close) invalidates the cached
// readiness. Reopening therefore probes before it reuses a URL, and a browser
// window whose server died is reloaded instead of being raised onto a dead page.
Singleton {
    id: root

    // ------------------------------------------------------------------
    // Configuration (proxied from Config; safe fallbacks for tests)
    // ------------------------------------------------------------------
    readonly property bool enabled: (typeof Config !== "undefined" && Config.dshWebEnabled !== undefined)
        ? Config.dshWebEnabled : true
    readonly property string baseUrl: (typeof Config !== "undefined" && Config.dshWebUrl && Config.dshWebUrl.length > 0)
        ? Config.dshWebUrl : "http://127.0.0.1:3080"
    readonly property string configuredCommand: (typeof Config !== "undefined" && Config.dshWebCommand)
        ? Config.dshWebCommand : ""
    readonly property string mode: (typeof Config !== "undefined" && Config.dshWebMode && Config.dshWebMode.length > 0)
        ? Config.dshWebMode : "browser"
    readonly property string browserOverride: (typeof Config !== "undefined" && Config.dshWebBrowser)
        ? Config.dshWebBrowser : ""
    readonly property bool firefoxKiosk: (typeof Config !== "undefined" && Config.dshWebFirefoxKiosk !== undefined)
        ? Config.dshWebFirefoxKiosk : false
    readonly property bool installDesktopIcon: (typeof Config !== "undefined" && Config.dshWebInstallDesktopIcon !== undefined)
        ? Config.dshWebInstallDesktopIcon : true

    readonly property string authority: DshLogic.authorityFromUrl(root.baseUrl)
    readonly property string host: DshLogic.hostFromUrl(root.baseUrl)
    readonly property int port: {
        var p = DshLogic.portFromUrl(root.baseUrl);
        return (p > 0) ? p : 3080;
    }

    // DSH's own cookie max age is 30 days; the shell mints fresh on every open,
    // so one hour is ample and always inside the server's window.
    readonly property int cookieTtlMs: 60 * 60 * 1000

    // ------------------------------------------------------------------
    // Observable state
    // ------------------------------------------------------------------
    property bool visible: false        // embedded window only
    property string state: "idle"       // idle | probing | starting | ready | error
    property bool serverUp: false
    property bool managed: false        // this shell started the server
    property string authUrl: ""         // tokenised URL from our own server
    property string targetUrl: ""       // what the view/app window loads
    property bool injectCookie: false   // embedded: adopting an external server
    property string errorMessage: ""
    property string statusText: "Idle"
    property bool dshAvailable: false

    // ------------------------------------------------------------------
    // Live state, so the launcher icon can say what is actually true:
    //   running    - the web UI answered and we are ready to show it
    //   windowOpen - our browser app window is on screen right now
    // ------------------------------------------------------------------
    readonly property bool running: root.serverUp && root.state === "ready"
    readonly property bool failed: root.state === "error"
    /// The web UI is live in any form: its server answers, or a window that still
    /// belongs to a live server is up. A window left showing a dead server's
    /// connection error is not live.
    readonly property bool live: root.running || (root.windowOpen && !root.windowPageStale)
    /// The shell owns the server on screen, so it is also the one that can stop
    /// it again (a server the user started in a terminal is theirs to stop).
    readonly property bool canStop: root.managed

    readonly property bool windowOpen: {
        if (typeof WindowService === "undefined" || !WindowService) return false;
        const wins = WindowService.windows || [];
        for (let i = 0; i < wins.length; i++) {
            if (DshLogic.isDshAppId(wins[i].appId, root.host)) return true;
        }
        return false;
    }

    // The window on screen belongs to a server that is gone, so its page shows a
    // connection error. Reopening must reload it, not raise it.
    property bool windowPageStale: false

    onWindowOpenChanged: {
        if (!root.windowOpen) root.windowPageStale = false;      // closed: nothing to reload
        else if (!root.serverUp) root.windowPageStale = true;    // appeared without a live server
    }

    // User-started server announcement: see the watcher at the bottom.
    property bool externalNotified: false   // already told the user for this episode
    property bool externalSeenDown: false   // observed the port closed at least once

    // Embedded capability
    property bool webEngineSupported: false
    property bool capabilityChecked: false

    // Browser app mode
    property var browsers: []
    property string browserId: ""
    property string browserPath: ""
    property bool browserChecked: false
    property string defaultBrowserId: ""
    property bool defaultBrowserChecked: false

    // ------------------------------------------------------------------
    // Credentials: the durable browser-session signing secret (embedded only)
    // ------------------------------------------------------------------
    readonly property string dshHome: {
        var h = (typeof Quickshell !== "undefined" && Quickshell.env)
            ? (Quickshell.env("DSH_HOME") || "") : "";
        if (h.length > 0) return h;
        var home = (typeof Quickshell !== "undefined" && Quickshell.env)
            ? (Quickshell.env("HOME") || "") : "";
        return home + "/.dsh";
    }
    readonly property string credentialsPath: root.dshHome + "/.credentials.yaml"

    FileView {
        id: credentialsView
        path: root.credentialsPath
        preload: true
    }

    /** The DSH browser-session cookie for the configured authority, or null. */
    function authCookie() {
        try {
            var secret = DshAuth.parseSecret(credentialsView.text());
            if (!secret) return null;
            return DshAuth.mintCookie(secret, root.authority, Date.now(), root.cookieTtlMs);
        } catch (e) {
            console.warn("DshWebService: cookie mint failed:", e);
            return null;
        }
    }

    // ------------------------------------------------------------------
    // Probes: embedded capability, dsh availability, and browser detection
    // ------------------------------------------------------------------
    Process {
        id: capabilityProc
        command: ["sh", "-c", "grep -qa Qt6WebEngineQuick /proc/"
            + ((typeof Quickshell !== "undefined") ? Quickshell.processId : "self")
            + "/maps 2>/dev/null && echo yes || echo no"]
        stdout: SplitParser {
            onRead: line => {
                root.webEngineSupported = (line.trim() === "yes");
                root.capabilityChecked = true;
            }
        }
    }

    Process {
        id: dshAvailableProc
        command: ["sh", "-c", "command -v dsh >/dev/null 2>&1 && echo yes || echo no"]
        stdout: SplitParser {
            onRead: line => { root.dshAvailable = (line.trim() === "yes"); }
        }
    }

    Process {
        id: browserProc
        command: ["sh", "-c", DshLogic.detectionScript()]
        stdout: StdioCollector {
            onStreamFinished: {
                const records = DshLogic.parseBrowserRecords(this.text);
                root.browsers = DshLogic.resolveBrowsers(records.registrations, records.pathHits);
                var chosen = DshLogic.selectBrowser(root.browsers, root.browserOverride);
                root.browserId = chosen ? chosen.id : "";
                root.browserPath = chosen ? chosen.path : "";
                root.browserChecked = true;
            }
        }
    }

    // dsh web opens the token URL in the system default browser, so that is the
    // profile most likely to already hold the DSH cookie when we adopt a server.
    Process {
        id: defaultBrowserProc
        command: ["sh", "-c", "xdg-settings get default-web-browser 2>/dev/null; echo"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.defaultBrowserId = DshLogic.browserIdFromDesktopFile(this.text.trim());
                root.defaultBrowserChecked = true;
            }
        }
    }

    readonly property string daemonBin: {
        var bin = (typeof Config !== "undefined" && Config.daemonBin) ? Config.daemonBin : "";
        if (bin.length > 0) return bin;
        var url = Qt.resolvedUrl("../bin/astral-plasma").toString();
        if (url.startsWith("file://")) return url.substring(7);
        return url;
    }

    // Install DeepSeek's icon + a matching .desktop so the browser app window is
    // identified as its own application (daemon infrastructure/dsh_web_desktop.rs).
    // That is what makes the window and taskbar show DeepSeek's icon.
    Process {
        id: desktopEntryProc
    }

    /** Install or remove the DeepSeek icon + desktop entry. The daemon tells the
     *  user with a notification when something actually changes. */
    function applyDesktopIcon(enabled) {
        if (!root.daemonBin || root.daemonBin.length === 0) return;
        desktopEntryProc.running = false;
        if (enabled) {
            // The daemon writes desktop entries for the real Wayland app ids and a
            // KWin rule forcing this landscape size (KWin then centres it).
            var screen = (typeof Quickshell !== "undefined" && Quickshell.screens && Quickshell.screens.length > 0)
                ? Quickshell.screens[0] : null;
            var geometry = DshLogic.windowGeometry(screen ? screen.width : 0, screen ? screen.height : 0);
            desktopEntryProc.command = [root.daemonBin, "dsh-web", "desktop", "install",
                root.host, String(geometry.width), String(geometry.height)];
        } else {
            desktopEntryProc.command = [root.daemonBin, "dsh-web", "desktop", "remove"];
        }
        desktopEntryProc.running = true;
    }

    Connections {
        target: (typeof Config !== "undefined") ? Config : null
        function onDshWebInstallDesktopIconChanged() {
            root.applyDesktopIcon(Config.dshWebInstallDesktopIcon);
        }
    }

    Component.onCompleted: {
        capabilityProc.running = true;
        dshAvailableProc.running = true;
        browserProc.running = true;
        defaultBrowserProc.running = true;
        // Automatic: no manual step, and the daemon announces it once.
        if (root.installDesktopIcon && root.mode === "browser") root.applyDesktopIcon(true);
    }

    // ------------------------------------------------------------------
    // Health probe
    // ------------------------------------------------------------------
    Process {
        id: probeProc
        command: ["sh", "-c", "curl -s -o /dev/null -w '%{http_code}' --max-time 2 '"
            + root.baseUrl + "' 2>/dev/null || echo 000"]
        stdout: SplitParser {
            onRead: line => root.handleProbe(line)
        }
    }

    function probe() {
        root.state = "probing";
        root.statusText = "Checking DSH at " + root.authority + "...";
        root.errorMessage = "";
        probeProc.running = false;
        probeProc.running = true;
    }

    function handleProbe(line) {
        root.serverUp = (DshLogic.classifyProbe(line) === "up");
        if (root.serverUp) {
            root.adoptExisting();
        } else {
            // Nothing answered, so whatever we remembered is dead: forget it and
            // start a server instead of reusing a URL that no longer loads.
            root.invalidateServer("probe " + line);
            root.startServer();
        }
    }

    /**
     * Forget a server that is gone. Every observation of death funnels here - the
     * managed child exiting, the health probe failing, the idle watcher seeing the
     * port closed - so `serverUp` is never a stale memory that makes the launcher
     * open a dead page instead of restarting the server.
     */
    function invalidateServer(reason) {
        if (!root.managed && !root.serverUp) return;   // nothing remembered: nothing to forget
        const hadWindow = root.windowOpen;
        root.serverUp = false;
        root.managed = false;
        root.authUrl = "";            // a launch token dies with its server
        if (root.state === "ready" || root.state === "probing") root.state = "idle";
        if (hadWindow) root.windowPageStale = true;
        if (typeof Log !== "undefined" && Log.debugEnabled && Log.debugEnabled("dshweb"))
            Log.debug("dshweb", "server gone: " + reason);
    }

    /** A server answered: reuse our token URL, or adopt the running one. */
    function adoptExisting() {
        if (root.managed && root.authUrl.length > 0) {
            root.targetUrl = root.authUrl;
            root.injectCookie = false;
        } else {
            root.targetUrl = root.baseUrl;
            root.injectCookie = DshLogic.needsCookieInjection(true, false);
        }
        root.state = "ready";
        root.finishOpen();
    }

    // ------------------------------------------------------------------
    // Managed server: dsh web --no-open prints the authenticated URL
    // ------------------------------------------------------------------
    // Stopping a Process emits its exit *after* the replacement would have
    // started, so a restart is sequenced through that exit (see onExited) instead
    // of racing a late exit against the new server's state.
    property bool restartPending: false

    Process {
        id: serverProc
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                var url = DshLogic.parseDshUrlLine(line);
                if (url.length > 0) root.onServerReady(url);
            }
        }
        // A failure to start used to be invisible; keep the child's own words.
        stderr: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                const text = String(line).trim();
                if (text.length > 0 && typeof Log !== "undefined") Log.debug("dshweb", "dsh: " + text);
            }
        }
        onExited: (code, status) => {
            const wasStarting = root.managed && root.state === "starting";
            if (root.restartPending) {
                // The old child is observed gone: now the replacement is safe.
                root.restartPending = false;
                root.invalidateServer("restart (child exited with code " + code + ")");
                root.startServer();
                return;
            }
            root.invalidateServer("child exited with code " + code);
            if (wasStarting) {
                root.state = "error";
                root.errorMessage = "dsh web exited before printing its URL (code " + code + ")";
                root.statusText = root.errorMessage;
            }
        }
    }

    function startServer() {
        root.state = "starting";
        root.errorMessage = "";
        root.statusText = "Starting DSH web server...";
        root.managed = true;
        if (serverProc.running) {
            // A previous child is still alive (a server that stopped answering, or
            // an explicit restart): stop it and let onExited spawn the successor.
            root.restartPending = true;
            serverProc.running = false;
            return;
        }
        root.restartPending = false;
        var cmd = DshLogic.resolveCommand(root.configuredCommand, root.dshAvailable, root.port);
        serverProc.command = ["sh", "-c", "exec " + cmd];
        serverProc.running = true;
    }

    function onServerReady(url) {
        root.authUrl = url;
        root.serverUp = true;
        root.managed = true;
        root.injectCookie = false;
        root.targetUrl = url;
        root.state = "ready";
        root.finishOpen();
    }

    /** Stop the server the shell started, and forget it. A server the user
     *  started in a terminal is left alone: it is not ours to kill. */
    function stopServer() {
        root.restartPending = false;
        if (serverProc.running) serverProc.running = false;
        root.invalidateServer("stopped");
    }

    // ------------------------------------------------------------------
    // Presentation
    // ------------------------------------------------------------------
    /** The DSH browser app window on screen, or null (embedded mode has none). */
    function dshWindow() {
        if (root.mode === "embedded") return null;
        if (typeof WindowService === "undefined" || !WindowService) return null;
        const wins = WindowService.windows || [];
        for (let i = 0; i < wins.length; i++) {
            if (DshLogic.isDshAppId(wins[i].appId, root.host)) return wins[i];
        }
        return null;
    }

    /** Raise the DSH window: its server is alive, so its page is still valid. */
    function activateWindow() {
        const win = root.dshWindow();
        if (win && win.id !== undefined && win.id !== null) WindowService.activateWindow(win.id);
    }

    /** Close a window whose page belonged to a dead server, before relaunching. */
    function closeStaleWindow() {
        const win = root.dshWindow();
        if (win && win.id !== undefined && win.id !== null) WindowService.closeWindow(win.id);
    }

    /** Open the resolved URL: the embedded view, or a browser app window. */
    function finishOpen() {
        if (root.mode === "embedded" && root.webEngineSupported) {
            root.visible = true;
            root.statusText = root.managed ? "Connected (managed server)" : "Connected to running DSH";
            return;
        }
        // A browser window outlives its server, so it is only reused when this
        // opening did not have to revive the server behind it.
        const step = DshLogic.windowOpenStep(root.windowOpen, root.windowPageStale);
        if (step === "activate") {
            root.activateWindow();
            root.state = "ready";
            root.statusText = "DSH is already on screen";
            return;
        }
        if (step === "reload") {
            // The window shows the connection error of the server that died;
            // relaunching it on the fresh URL is what makes it work again.
            root.closeStaleWindow();
        }
        root.windowPageStale = false;
        // An adopted server's cookie lives in the default browser; a token URL
        // from our own server authenticates anywhere, so only then does the
        // configured preference order apply.
        root.launchBrowser(root.targetUrl, !root.managed);
    }

    /**
     * Launch the browser in app mode. The token URL (when we started the server)
     * authenticates; otherwise the browser's own DSH cookie does.
     */
    function launchBrowser(url, preferDefaultBrowser) {
        if (root.installDesktopIcon) root.applyDesktopIcon(true);
        var override = root.browserOverride;
        if ((!override || override.length === 0) && preferDefaultBrowser && root.defaultBrowserId.length > 0) {
            override = root.defaultBrowserId;
        }
        var chosen = DshLogic.selectBrowser(root.browsers, override);
        if (!chosen) {
            // No known app-mode browser: hand the URL to the system handler so
            // the UI still opens, even without a chromeless window.
            Quickshell.execDetached(["xdg-open", url]);
            root.state = "ready";
            root.statusText = "No app-mode browser found; opened with the default handler";
            return;
        }
        root.browserId = chosen.id;
        root.browserPath = chosen.path;
        // Landscape window, centred on the primary screen, never full-screen.
        var screen = (typeof Quickshell !== "undefined" && Quickshell.screens && Quickshell.screens.length > 0)
            ? Quickshell.screens[0] : null;
        var geometry = DshLogic.windowGeometry(screen ? screen.width : 0, screen ? screen.height : 0);
        var args = DshLogic.appModeArgs(chosen.id, url, root.firefoxKiosk, geometry);
        Quickshell.execDetached([chosen.path].concat(args));
        root.state = "ready";
        root.statusText = "Opened DSH in " + chosen.id + " (app mode)";
    }

    // ------------------------------------------------------------------
    // Public API
    // ------------------------------------------------------------------
    function open() {
        if (!root.enabled) return;
        // Server first, window second. A window on screen proves nothing about the
        // server behind it - the user can stop a dsh they started in a terminal at
        // any moment - so opening always goes through the probe/start flow, and
        // finishOpen decides from live state whether to raise or reload the window.
        root.startOpenFlow();
    }

    function startOpenFlow() {
        // Wait for the startup probes; the browser list is needed for the
        // fallback even when embedded mode was requested.
        if (!root.capabilityChecked || !root.browserChecked || !root.defaultBrowserChecked) {
            Qt.callLater(root.startOpenFlow);
            return;
        }
        // A child we started is alive but has not printed its URL yet (or is being
        // replaced): let it, instead of probing the port it has not opened yet.
        if (root.managed && root.state === "starting" && (serverProc.running || root.restartPending)) return;
        // Only a managed child we can still see running proves the remembered URL
        // answers; anything else (including a state that says "ready") is memory.
        if (DshLogic.serverOpenStep(root.managed, serverProc.running) === "reuse"
            && root.targetUrl.length > 0) {
            root.serverUp = true;
            root.state = "ready";
            root.finishOpen();
            return;
        }
        root.probe();
    }

    function close() { root.visible = false; }

    function toggle() {
        if (root.mode === "embedded" && root.visible) root.close();
        else root.open();
    }

    function openExternal(url) {
        Quickshell.execDetached(["xdg-open", (url && url.length > 0) ? url : root.baseUrl]);
    }

    // ------------------------------------------------------------------
    // A dsh server the *user* started in a terminal
    //
    // Cost is deliberately near-zero: one in-process /proc/net/tcp read every
    // 20 s (no fork, no curl, no polling of the network), and the loop stops
    // while the view is open or a notification is already on screen. The click
    // is handled by notify-send itself (an action implies --wait; the chosen
    // action name is printed), so nothing hooks the global notification stream.
    // ------------------------------------------------------------------
    readonly property bool watchExternal: root.enabled
    readonly property bool xhrFileReadAllowed: (typeof Quickshell !== "undefined" && Quickshell.env)
        ? (Quickshell.env("QML_XHR_ALLOW_FILE_READ") === "1") : false

    /** Fork-free "is something listening on our port?" check (when QML_XHR_ALLOW_FILE_READ=1). */
    function dshPortListening() {
        if (!root.xhrFileReadAllowed) return false;
        var sources = ["file:///proc/net/tcp", "file:///proc/net/tcp6"];
        for (var i = 0; i < sources.length; i++) {
            var xhr = new XMLHttpRequest();
            try {
                xhr.open("GET", sources[i], false);
                xhr.send();
                if (xhr.responseText && xhr.responseText.length > 0) {
                    if (DshLogic.portListeningFromProcNetTcp(xhr.responseText, root.port)) return true;
                }
            } catch (e) {
                continue;
            }
        }
        return false;
    }

    Process {
        id: procNetTcpProc
        command: ["sh", "-c", "cat /proc/net/tcp /proc/net/tcp6 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                var isListening = DshLogic.portListeningFromProcNetTcp(this.text, root.port);
                root.handleExternalWatchStatus(isListening);
            }
        }
    }

    Timer {
        id: externalWatch
        interval: 20000
        repeat: true
        triggeredOnStart: true
        // Idle-only: no work while the DSH view is open or a prompt is waiting.
        running: root.watchExternal && !root.visible && !externalNotifyProc.running
        onTriggered: root.handleExternalWatch()
    }

    function handleExternalWatch() {
        if (root.managed) return;              // we started it: nothing to announce
        // Try in-process synchronous read only when QML_XHR_ALLOW_FILE_READ=1
        // is enabled; otherwise Qt logs a warning on every local-file GET.
        if (root.xhrFileReadAllowed && root.dshPortListening()) {
            root.handleExternalWatchStatus(true);
            return;
        }
        // In live desktop, local file XHR is disabled by default in Qt; use procfs read
        if (!procNetTcpProc.running) {
            procNetTcpProc.running = true;
        }
    }

    function handleExternalWatchStatus(isListening) {
        if (root.managed) return;
        if (!isListening) {
            root.externalNotified = false;     // a later start is a new episode
            root.externalSeenDown = true;
            // The port is closed: whatever we remembered answered is gone, so the
            // icon stops claiming the UI is live and the next open restarts it.
            root.invalidateServer("port closed");
            return;
        }
        // A server that was already running when the shell started is not news.
        if (!root.externalSeenDown || root.externalNotified) return;
        root.externalNotified = true;
        root.notifyExternalServer();
    }

    Process {
        id: externalNotifyProc
        stdout: StdioCollector {
            onStreamFinished: {
                // notify-send prints the chosen action; any click opens the view.
                if (this.text && this.text.indexOf("default") !== -1) root.open();
            }
        }
    }

    function notifyExternalServer() {
        var icon = (root.mode === "embedded") ? "astral-dsh-web-symbolic" : "astral-dsh-web-symbolic";
        externalNotifyProc.running = false;
        externalNotifyProc.command = [
            "notify-send",
            "-a", "Astral Plasma",
            "-i", icon,
            "-t", "20000",
            "-A", "default=Open DSH Web",
            "DeepSeek Harness is running",
            "Click to open the DSH web view"
        ];
        externalNotifyProc.running = true;
    }
}
