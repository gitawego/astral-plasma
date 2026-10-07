.pragma library

// Pure helpers for the DSH web launcher. Kept out of DshWebService.qml so the
// offscreen QML suite can exercise them without a running Quickshell or server.

/** Host[:port] of a URL, or "" when unparsable. */
function authorityFromUrl(url) {
    var s = String(url || "");
    var m = /^[a-zA-Z][a-zA-Z0-9+.-]*:\/\/([^\/?#]+)/.exec(s);
    return m ? m[1] : "";
}

function hostFromUrl(url) {
    var a = authorityFromUrl(url);
    var i = a.lastIndexOf(":");
    return i >= 0 ? a.slice(0, i) : a;
}

/** Port as an int, defaulting to 80 (or 0 when the URL is unparsable). */
function portFromUrl(url) {
    var a = authorityFromUrl(url);
    if (!a) return 0;
    var i = a.lastIndexOf(":");
    if (i < 0) return 80;
    var p = parseInt(a.slice(i + 1), 10);
    return (isFinite(p) && p > 0) ? p : 0;
}

function isLoopback(authority) {
    var a = String(authority || "").toLowerCase();
    return a.indexOf("127.0.0.1") === 0 || a.indexOf("localhost") === 0 || a.indexOf("[::1]") === 0;
}

/**
 * The authenticated URL that `dsh web` prints once its server is listening:
 *   dsh web: http://127.0.0.1:3080/?token=<launch-token> (LAN: ...)
 */
function parseDshUrlLine(text) {
    if (!text) return "";
    var lines = String(text).split("\n");
    for (var i = 0; i < lines.length; i++) {
        var m = /dsh web:\s*(\S+)/.exec(lines[i]);
        if (m) return m[1];
    }
    return "";
}

/**
 * Classify an HTTP status fetched from the configured origin. Any HTTP status
 * means a server answered (401/403 is the expected unaubthenticated DSH reply);
 * a failed connection (curl reports "000") means it is down.
 */
function classifyProbe(statusText) {
    var code = parseInt(String(statusText || "").trim(), 10);
    if (!isFinite(code) || code < 100 || code > 599) return "down";
    return "up";
}

/**
 * Command that starts a headless DSH web server. A user-configured command wins;
 * otherwise prefer the installed `dsh` and fall back to `npx`.
 */
function resolveCommand(configured, dshAvailable, port) {
    var p = (port && port > 0) ? port : 3080;
    if (configured && String(configured).trim().length > 0) return String(configured).trim();
    if (dshAvailable) return "dsh web --no-open --host 127.0.0.1 --port " + p;
    return "npx -y @deepseek-ai/dsh web --no-open --host 127.0.0.1 --port " + p;
}

/**
 * Reuse an already-running server only when the shell does not hold its own
 * authenticated (token) URL: then the window mints and injects the cookie.
 */
function needsCookieInjection(serverUp, haveOwnAuthUrl) {
    return !!serverUp && !haveOwnAuthUrl;
}

// ---------------------------------------------------------------------------
// Browser app-mode launch
//
// The DSH UI is shown in the user's own browser as a chromeless "app" window.
// Preference order is fixed: chrome, chromium, edge, firefox.
// ---------------------------------------------------------------------------

var BROWSER_CANDIDATES = [
    { id: "chrome",   commands: ["google-chrome-stable", "google-chrome", "chrome"] },
    { id: "chromium", commands: ["chromium", "chromium-browser"] },
    { id: "edge",     commands: ["microsoft-edge-stable", "microsoft-edge", "microsoft-edge-beta", "msedge"] },
    { id: "firefox",  commands: ["firefox", "firefox-esr"] }
];

/** The fixed preference order. */
function browserOrder() {
    return BROWSER_CANDIDATES.map(function (b) { return b.id; });
}

/** Shell script that prints "id:path" for each installed candidate, in order. */
function detectionScript() {
    var parts = [];
    for (var i = 0; i < BROWSER_CANDIDATES.length; i++) {
        var b = BROWSER_CANDIDATES[i];
        var names = b.commands.map(function (c) { return "'" + c + "'"; }).join(" ");
        parts.push("for c in " + names + "; do p=$(command -v \"$c\" 2>/dev/null) && { echo \""
            + b.id + ":$p\"; break; }; done");
    }
    return parts.join("; ");
}

/** Parse the detection output into an ordered list of {id, path}. */
function parseBrowsers(text) {
    var out = [];
    if (!text) return out;
    var lines = String(text).split("\n");
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i].trim();
        if (!line) continue;
        var at = line.indexOf(":");
        if (at <= 0) continue;
        var id = line.slice(0, at).trim();
        var path = line.slice(at + 1).trim();
        if (path.length > 0) out.push({ id: id, path: path });
    }
    return out;
}

/** Pick the override browser when present, else the first in preference order. */
function selectBrowser(browsers, override) {
    if (!browsers || browsers.length === 0) return null;
    if (override && String(override).length > 0) {
        for (var i = 0; i < browsers.length; i++) {
            if (browsers[i].id === override) return browsers[i];
        }
    }
    return browsers[0];
}

function isChromium(browserId) {
    var id = String(browserId || "");
    return id === "chrome" || id === "chromium" || id === "edge";
}

/**
 * Arguments that open a URL as an app window. Chromium browsers have a true
 * chromeless --app; Firefox has no app mode, so it gets a normal window unless
 * the caller asks for kiosk.
 */
function appModeArgs(browserId, url, firefoxKiosk, geometry) {
    if (String(browserId) === "firefox") {
        return firefoxKiosk ? ["--kiosk", url] : ["--new-window", url];
    }
    // --class makes KWin match the window to astral-dsh-web.desktop, so the
    // window (taskbar + titlebar) shows DeepSeek's icon, not the browser's.
    var args = ["--app=" + url, "--class=astral-dsh-web"];
    if (geometry && geometry.width > 0 && geometry.height > 0) {
        args.push("--window-size=" + geometry.width + "," + geometry.height);
        args.push("--window-position=" + geometry.x + "," + geometry.y);
    }
    return args;
}

/**
 * A landscape app-window geometry, centred on the screen and never filling it.
 * The window is at most ~60% wide and ~63% of that tall (a wide 16:10-ish
 * canvas); the caller passes the primary screen size.
 */
function windowGeometry(screenWidth, screenHeight) {
    var sw = (screenWidth && screenWidth > 0) ? screenWidth : 1920;
    var sh = (screenHeight && screenHeight > 0) ? screenHeight : 1080;
    var width = Math.min(1600, Math.round(sw * 0.6));
    var height = Math.min(Math.round(sh * 0.82), Math.round(width * 0.63));
    // Leave a margin so the window never touches the screen edges.
    width = Math.max(880, Math.min(width, sw - 96));
    height = Math.max(520, Math.min(height, sh - 96));
    var x = Math.max(0, Math.round((sw - width) / 2));
    var y = Math.max(0, Math.round((sh - height) / 2));
    return { width: width, height: height, x: x, y: y };
}

/**
 * Map an xdg-settings desktop id (e.g. com.microsoft.Edge.desktop) to one of
 * our browser ids, or "" when it is a browser we do not launch.
 */
function browserIdFromDesktopFile(desktopId) {
    var s = String(desktopId || "").toLowerCase();
    if (s.indexOf("edge") !== -1) return "edge";
    if (s.indexOf("firefox") !== -1) return "firefox";
    if (s.indexOf("chromium") !== -1) return "chromium";
    if (s.indexOf("chrome") !== -1) return "chrome";
    return "";
}


/**
 * Is `port` in TCP LISTEN state in a /proc/net/tcp ([tcp6]) snapshot?
 *
 * Pure so the fork-free DSH-server watcher can be unit tested. Each data line is:
 *   sl local_address rem_address st ...
 * with the local address as little-endian HEX:PORT and st == 0A for LISTEN.
 */
function portListeningFromProcNetTcp(text, port) {
    if (!text || !(port > 0)) return false;
    var portHex = ("0000" + Number(port).toString(16).toUpperCase()).slice(-4);
    var lines = String(text).split("\n");
    for (var i = 1; i < lines.length; i++) {
        var fields = lines[i].trim().split(/\s+/);
        if (fields.length < 4) continue;
        if ((fields[3] || "").toUpperCase() !== "0A") continue;
        var local = (fields[1] || "").toUpperCase();
        if (local.length >= 5 && local.slice(-5) === ":" + portHex) return true;
    }
    return false;
}

/**
 * Is a window's appId a DSH browser app window for `host`? Chromium derives the
 * Wayland app id as `<browser>-<host>__-<profile>` and ignores --class, so this
 * is the reliable signal that our app window (not some other browser window) is
 * on screen. Pure, so the icon's state can be unit tested.
 */
function isDshAppId(appId, host) {
    var id = String(appId || "").toLowerCase();
    if (!id) return false;
    var h = String(host || "127.0.0.1").toLowerCase();
    var candidates = ["chrome", "chromium", "msedge"];
    for (var i = 0; i < candidates.length; i++) {
        if (id.indexOf(candidates[i] + "-" + h) === 0) return true;
    }
    return false;
}
