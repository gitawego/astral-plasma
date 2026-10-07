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

        // --- browser app-mode detection -----------------------------------
        assert(JSON.stringify(DshLogic.browserOrder()) === JSON.stringify(["chrome", "chromium", "edge", "firefox"]),
            "preference order must be chrome, chromium, edge, firefox");
        var script = DshLogic.detectionScript();
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
