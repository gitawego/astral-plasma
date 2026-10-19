import QtQuick
import "../services/DshWebLogic.js" as DshLogic

Item {
    id: testRoot
    width: 200
    height: 100

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
        // --- URL decomposition ---
        assert(DshLogic.authorityFromUrl("http://127.0.0.1:3080/") === "127.0.0.1:3080",
            "authorityFromUrl must strip scheme and path");
        assert(DshLogic.authorityFromUrl("http://127.0.0.1:3080/?token=x#y") === "127.0.0.1:3080",
            "authorityFromUrl must stop at query/hash");
        assert(DshLogic.authorityFromUrl("not a url") === "",
            "authorityFromUrl must return empty for garbage");
        assert(DshLogic.hostFromUrl("http://localhost:3080/") === "localhost",
            "hostFromUrl must drop the port");
        assert(DshLogic.portFromUrl("http://127.0.0.1:3080/") === 3080,
            "portFromUrl must read the port");
        assert(DshLogic.portFromUrl("http://127.0.0.1/") === 80,
            "portFromUrl must default to 80");
        assert(DshLogic.isLoopback("127.0.0.1:3080") === true, "loopback 127.0.0.1");
        assert(DshLogic.isLoopback("localhost:3080") === true, "loopback localhost");
        assert(DshLogic.isLoopback("10.0.0.5:3080") === false, "non-loopback LAN host");

        // --- dsh web URL line ---
        var out = "boot line\ndsh web: http://127.0.0.1:3080/?token=abcDEF123 (LAN: http://10.0.0.5:3080/?token=abcDEF123)\n";
        assert(DshLogic.parseDshUrlLine(out) === "http://127.0.0.1:3080/?token=abcDEF123",
            "parseDshUrlLine must read the local authenticated URL");
        assert(DshLogic.parseDshUrlLine("no url here") === "",
            "parseDshUrlLine must return empty when absent");

        // --- probe classification ---
        assert(DshLogic.classifyProbe("200") === "up", "HTTP 200 is up");
        assert(DshLogic.classifyProbe("401") === "up", "HTTP 401 is up (unaubthenticated DSH)");
        assert(DshLogic.classifyProbe("403") === "up", "HTTP 403 is up");
        assert(DshLogic.classifyProbe("000") === "down", "curl 000 is down");
        assert(DshLogic.classifyProbe("") === "down", "empty status is down");
        assert(DshLogic.classifyProbe("nonsense") === "down", "garbage status is down");

        // --- command resolution ---
        var withDsh = DshLogic.resolveCommand("", true, 3080);
        assert(withDsh.indexOf("dsh web") === 0, "prefer the installed dsh");
        assert(withDsh.indexOf("--port 3080") !== -1, "command must pin the port");
        var withNpx = DshLogic.resolveCommand("", false, 3080);
        assert(withNpx.indexOf("npx") === 0, "fall back to npx when dsh is absent");
        assert(withNpx.indexOf("@deepseek-ai/dsh") !== -1, "npx must name the DSH package");
        assert(DshLogic.resolveCommand("my-dsh web", true, 3080) === "my-dsh web",
            "a configured command wins");

        // --- cookie injection decision ---
        assert(DshLogic.needsCookieInjection(true, false) === true,
            "external server needs a minted cookie");
        assert(DshLogic.needsCookieInjection(true, true) === false,
            "our own token URL needs no cookie");
        assert(DshLogic.needsCookieInjection(false, false) === false,
            "a down server needs starting, not a cookie");

        // --- reopening after the server went away --------------------------
        // A remembered URL is not proof that a server still answers: a `dsh web`
        // started in a terminal can be stopped by the user at any moment, and a
        // child the shell spawned can die. Only a child we can still see running
        // may skip the probe, or the launcher opens a dead page instead of
        // restarting the server.
        assert(DshLogic.serverOpenStep(true, true) === "reuse",
            "a managed child that is still running is ground truth: reuse its token URL");
        assert(DshLogic.serverOpenStep(true, false) === "probe",
            "a managed child that exited must be probed, not reused");
        assert(DshLogic.serverOpenStep(false, true) === "probe",
            "a server the user started can vanish at any moment: probe it");
        assert(DshLogic.serverOpenStep(false, false) === "probe",
            "nothing running means probing before anything is reused");

        // A browser window outlives its server, so its presence is not readiness.
        assert(DshLogic.windowOpenStep(false, false) === "launch", "no window means launch");
        assert(DshLogic.windowOpenStep(false, true) === "launch", "a stale marker without a window means launch");
        assert(DshLogic.windowOpenStep(true, false) === "activate",
            "a window whose server is alive must only be raised");
        assert(DshLogic.windowOpenStep(true, true) === "reload",
            "a window whose server died must be reloaded, not raised");

        // --- browser app-mode detection -----------------------------------
        // Why this matters: a PATH lookup can find an automation-only build
        // (Chrome for Testing - it even injects a "for automated testing" banner
        // and is not installed as a browser). The desktop's own browser
        // registration is the authority on browsers a user can browse with, so
        // registered entries outrank bare PATH hits.
        assert(DshLogic.execProgram("Exec=/usr/bin/microsoft-edge-stable %U") === "/usr/bin/microsoft-edge-stable",
            "execProgram must read argv[0] and drop field codes");
        assert(DshLogic.execProgram("Exec=env FOO=bar /opt/browser/browser %u") === "/opt/browser/browser",
            "execProgram must skip env and VAR=VAL prefixes");
        assert(DshLogic.execProgram("Exec=xdg-open %u") === "xdg-open",
            "execProgram must return a bare program name too");
        assert(DshLogic.execProgram("") === "", "execProgram must tolerate an empty Exec line");

        assert(DshLogic.browserIdFromExecPath("/usr/bin/microsoft-edge-stable") === "edge",
            "the Edge binary identifies the edge family");
        assert(DshLogic.browserIdFromExecPath("/usr/lib/firefox/firefox") === "firefox",
            "the Firefox binary identifies the firefox family");
        assert(DshLogic.browserIdFromExecPath("/usr/bin/chromium") === "chromium",
            "the Chromium binary identifies the chromium family");
        assert(DshLogic.browserIdFromExecPath("/opt/chrome-linux64/chrome") === "chrome",
            "a Chrome binary identifies the chrome family");
        assert(DshLogic.browserIdFromExecPath("/usr/bin/xdg-open") === "",
            "a URL dispatcher is not a browser");
        assert(DshLogic.browserIdFromExecPath("/usr/bin/torbrowser-launcher") === "",
            "an unknown program is not a browser we can drive");

        var records = DshLogic.parseBrowserRecords(
            "R\t/usr/share/applications/microsoft-edge.desktop\tExec=/usr/bin/microsoft-edge-stable %U\n"
            + "R\t/usr/share/applications/firefox.desktop\tExec=/usr/lib/firefox/firefox %u\n"
            + "R\t/home/u/.local/share/applications/tor.desktop\tExec=torbrowser-launcher %u\n"
            + "P\tchrome:/home/u/.local/bin/google-chrome-stable\n"
            + "P\tedge:/usr/bin/microsoft-edge-stable\n");
        assert(records.registrations.length === 3, "parseBrowserRecords must read every registration record");
        assert(records.registrations[0].desktopId === "microsoft-edge.desktop",
            "a registration must keep its desktop id");
        assert(records.registrations[0].path === "/usr/bin/microsoft-edge-stable",
            "a registration must keep the program its Exec line launches");
        assert(records.pathHits.length === 2 && records.pathHits[0].id === "chrome",
            "parseBrowserRecords must read the PATH fallback records");

        // The exact reported failure: Chrome for Testing is on PATH, Edge is the
        // browser the desktop actually offers. The app window must be Edge.
        var chosenList = DshLogic.resolveBrowsers(records.registrations, records.pathHits);
        assert(chosenList.length === 3 && chosenList[0].id === "edge" && chosenList[0].path === "/usr/bin/microsoft-edge-stable",
            "a registered browser must outrank a PATH-only build");
        assert(chosenList[1].id === "firefox" && chosenList[2].id === "chrome",
            "registered families keep the family order; PATH-only families follow them");
        assert(DshLogic.selectBrowser(chosenList, "").id === "edge",
            "without an override the launcher picks the first registered browser");

        // The same environment with only Edge registered (what the user has).
        var edgeOnly = DshLogic.resolveBrowsers(
            [{ desktopId: "microsoft-edge.desktop", path: "/usr/bin/microsoft-edge-stable" }],
            records.pathHits);
        assert(edgeOnly.length === 2 && edgeOnly[0].id === "edge" && edgeOnly[1].id === "chrome",
            "an automation-only Chrome on PATH must never beat the registered Edge");
        assert(DshLogic.selectBrowser(edgeOnly, "").path === "/usr/bin/microsoft-edge-stable",
            "the launch must use the registered browser's own Exec path, not a PATH symlink");

        // Within one tier the documented family order still decides.
        var bothRegistered = DshLogic.resolveBrowsers([
            { desktopId: "firefox.desktop", path: "/usr/lib/firefox/firefox" },
            { desktopId: "google-chrome.desktop", path: "/usr/bin/google-chrome-stable" }
        ], []);
        assert(bothRegistered.length === 2 && bothRegistered[0].id === "chrome" && bothRegistered[1].id === "firefox",
            "two registered browsers keep the chrome-before-firefox order");

        // Nothing registered (a bare environment): behave as before.
        var pathOnly = DshLogic.resolveBrowsers([], [
            { id: "chromium", path: "/usr/bin/chromium" },
            { id: "firefox", path: "/usr/bin/firefox" }
        ]);
        assert(pathOnly.length === 2 && pathOnly[0].id === "chromium" && pathOnly[1].id === "firefox",
            "without any registration the PATH order is preserved");
        assert(DshLogic.resolveBrowsers([], []).length === 0,
            "no registrations and no PATH hits means no candidate");

        assert(DshLogic.browserOrder().length === 4, "the family preference order must stay defined");
        assert(JSON.stringify(DshLogic.browserOrder()) === JSON.stringify(["chrome", "chromium", "edge", "firefox"]),
            "preference order must be chrome, chromium, edge, firefox");
        var script = DshLogic.detectionScript();
        assert(script.indexOf("WebBrowser") !== -1,
            "detection script must read the desktop's own WebBrowser registrations");
        assert(script.indexOf("XDG_DATA_DIRS") !== -1 && script.indexOf("flatpak") !== -1,
            "registration scan must cover every XDG application directory");
        assert(script.indexOf("$r/applications") !== -1,
            "XDG_DATA_DIRS lists data roots: `applications` must be appended to each");
        assert(script.indexOf("google-chrome-stable") !== -1 && script.indexOf("chromium") !== -1
            && script.indexOf("microsoft-edge-stable") !== -1 && script.indexOf("firefox") !== -1,
            "detection script must look for every family");
        assert(script.indexOf("google-chrome-stable") < script.indexOf("chromium")
            && script.indexOf("chromium") < script.indexOf("microsoft-edge-stable")
            && script.indexOf("microsoft-edge-stable") < script.indexOf("firefox"),
            "detection script must probe in preference order");

        var parsed = DshLogic.parseBrowsers("chrome:/usr/bin/google-chrome\nedge:/usr/bin/microsoft-edge-stable\n");
        assert(parsed.length === 2 && parsed[0].id === "chrome" && parsed[1].path === "/usr/bin/microsoft-edge-stable",
            "parseBrowsers must read id:path lines");
        assert(DshLogic.parseBrowsers("").length === 0, "parseBrowsers must tolerate empty input");

        var list = [{ id: "chrome", path: "/c" }, { id: "firefox", path: "/f" }];
        assert(DshLogic.selectBrowser(list, "") === list[0], "no override picks the first browser");
        assert(DshLogic.selectBrowser(list, "firefox") === list[1], "an override picks that browser");
        assert(DshLogic.selectBrowser(list, "edge") === list[0], "an unknown override falls back to the first");
        assert(DshLogic.selectBrowser([], "chrome") === null, "no browsers means no selection");

        assert(JSON.stringify(DshLogic.appModeArgs("chrome", "http://u/", false))
                === JSON.stringify(["--app=http://u/", "--class=astral-dsh-web"]),
            "chrome uses app mode with the DeepSeek window class");
        assert(JSON.stringify(DshLogic.appModeArgs("chromium", "http://u/", false))
                === JSON.stringify(["--app=http://u/", "--class=astral-dsh-web"]),
            "chromium uses app mode with the DeepSeek window class");
        assert(JSON.stringify(DshLogic.appModeArgs("edge", "http://u/", false))
                === JSON.stringify(["--app=http://u/", "--class=astral-dsh-web"]),
            "edge uses app mode with the DeepSeek window class");
        assert(JSON.stringify(DshLogic.appModeArgs("firefox", "http://u/", false)) === JSON.stringify(["--new-window", "http://u/"]),
            "firefox falls back to a new window");
        assert(JSON.stringify(DshLogic.appModeArgs("firefox", "http://u/", true)) === JSON.stringify(["--kiosk", "http://u/"]),
            "firefox kiosk is opt-in");
        // --- our app window, by its Wayland app id --------------------------
        assert(DshLogic.isDshAppId("msedge-127.0.0.1__-Default", "127.0.0.1"),
            "an Edge DSH app window is recognised");
        assert(DshLogic.isDshAppId("chrome-127.0.0.1__-Default", "127.0.0.1"),
            "a Chrome DSH app window is recognised");
        assert(DshLogic.isDshAppId("chromium-localhost__-Default", "localhost"),
            "the host is matched, not assumed");
        assert(!DshLogic.isDshAppId("microsoft-edge", "127.0.0.1"),
            "a plain browser window is not our app window");
        assert(!DshLogic.isDshAppId("msedge-127.0.0.1__-Default", "localhost"),
            "another host's app window does not match");
        assert(!DshLogic.isDshAppId("", "127.0.0.1"), "an empty app id is not a match");

        // --- user-started server detection (fork-free procfs scan) ----------
        // Real /proc/net/tcp layout: sl local_address rem_address st ...
        var sample = "  sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode\n"
            + "   0: 0100007F:0C08 00000000:0000 0A 00000000:00000000 00:00000000 00000000  1000        0 12345 1 0000000000000000 100 0 0 10 0\n";
        assert(DshLogic.portListeningFromProcNetTcp(sample, 3080),
            "3080 listening in LISTEN state must be detected");
        assert(!DshLogic.portListeningFromProcNetTcp(sample, 3081),
            "a different port must not match");
        assert(!DshLogic.portListeningFromProcNetTcp("", 3080),
            "an empty snapshot is not a listening server");
        // Same port but ESTABLISHED (01) is a client, not a server.
        var established = "  sl  local_address rem_address   st\n"
            + "   1: 0100007F:0C08 0100007F:1F90 01 00000000:00000000\n";
        assert(!DshLogic.portListeningFromProcNetTcp(established, 3080),
            "only LISTEN sockets count as a running server");

        assert(DshLogic.isChromium("chrome") && DshLogic.isChromium("chromium") && DshLogic.isChromium("edge")
            && !DshLogic.isChromium("firefox"),
            "isChromium must cover chrome/chromium/edge only");

        // --- app-window geometry --------------------------------------------
        var g = DshLogic.windowGeometry(2560, 1600);
        assert(g.width > g.height, "the app window must be landscape");
        assert(g.width < 2560 && g.height < 1600, "the app window must not fill the screen");
        assert(g.x === Math.round((2560 - g.width) / 2) && g.y === Math.round((1600 - g.height) / 2),
            "the app window must be centred on the screen");

        var small = DshLogic.windowGeometry(1366, 768);
        assert(small.width > 0 && small.height > 0 && small.width > small.height,
            "small screens still get a landscape window");
        assert(small.width <= 1366 - 96 && small.height <= 768 - 96,
            "the window keeps a margin on small screens");

        var withGeom = DshLogic.appModeArgs("edge", "http://u/", false,
            { width: 1200, height: 760, x: 100, y: 80 });
        assert(JSON.stringify(withGeom) === JSON.stringify([
            "--app=http://u/", "--class=astral-dsh-web",
            "--window-size=1200,760", "--window-position=100,80"
        ]), "chromium must pass the window size and position");

        assert(DshLogic.browserIdFromDesktopFile("com.microsoft.Edge.desktop") === "edge",
            "an Edge desktop id maps to edge");
        assert(DshLogic.browserIdFromDesktopFile("firefox.desktop") === "firefox",
            "a Firefox desktop id maps to firefox");
        assert(DshLogic.browserIdFromDesktopFile("google-chrome.desktop") === "chrome",
            "a Chrome desktop id maps to chrome");
        assert(DshLogic.browserIdFromDesktopFile("brave-browser.desktop") === "",
            "an unknown desktop id maps to nothing");

        console.log("PASS: tst_dsh_web_logic");
        Qt.exit(0);
    }
}
