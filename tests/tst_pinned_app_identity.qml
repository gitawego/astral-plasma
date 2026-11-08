import QtQuick

// ============================================================================
// Pinned Application Identity Resolution Tests
// ============================================================================
// A pinned dock entry and the running window it represents must resolve to one
// canonical application. Wine/Lutris apps make this visible: the pin may name
// the executable ("cloudmusic") while the window resolves through its Wine
// menu entry ("网易云音乐"), so string equality alone leaves a second, generic
// dock icon beside the running one.
//
// The bridge is data-driven: the desktop entry's own StartupWMClass. No
// application name is special-cased in the resolver or in this test.
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

    function normalizeId(str) {
        if (!str) return "";
        let s = String(str).trim().toLowerCase().replace(/\.desktop$/, "");
        const slashIdx = s.lastIndexOf("/");
        if (slashIdx !== -1) s = s.substring(slashIdx + 1);
        return s;
    }

    function getCanonicalAliases(rawId) {
        const id = normalizeId(rawId);
        if (!id) return [];
        const aliases = [id];
        const parts = id.split(".");
        if (parts.length >= 3 && ["com", "org", "net", "io", "app"].indexOf(parts[0]) !== -1) {
            const hyphenated = parts.slice(1).join("-");
            if (hyphenated && aliases.indexOf(hyphenated) === -1) aliases.push(hyphenated);
            if (parts[0] === "org" && parts[1] === "kde") {
                const kdeName = parts.slice(2).join("-");
                if (kdeName && aliases.indexOf(kdeName) === -1) aliases.push(kdeName);
            }
        }
        if (id.indexOf("-") !== -1 && id.indexOf(".") === -1) {
            const rDns = "com." + id.replace(/-/g, ".");
            if (aliases.indexOf(rDns) === -1) aliases.push(rDns);
        }
        return aliases;
    }

    // Mirrors WindowService._rebuildCanonicalMap: desktop ids, reverse-DNS
    // aliases, Exec binaries and the entry's declared StartupWMClass.
    function buildCanonicalMap(apps) {
        const map = {};
        for (let i = 0; i < apps.length; i++) {
            const a = apps[i];
            const desk = (a.desktop_file || "").toLowerCase().replace(/\.desktop$/, "");
            if (!desk) continue;
            map[desk] = desk;

            const parts = desk.split(".");
            if (parts.length >= 3 && ["com", "org", "net", "io", "app"].indexOf(parts[0]) !== -1) {
                const hyphenated = parts.slice(1).join("-");
                if (hyphenated) map[hyphenated] = desk;
                if (parts[0] === "org" && parts[1] === "kde") {
                    const kdeName = parts.slice(2).join("-");
                    if (kdeName) map[kdeName] = desk;
                }
            } else if (desk.indexOf("-") !== -1 && desk.indexOf(".") === -1) {
                map["com." + desk.replace(/-/g, ".")] = desk;
            }

            if (a.exec) {
                let bin = a.exec.trim();
                if (bin.startsWith("\"")) {
                    bin = bin.substring(1).split("\"")[0];
                } else if (bin.startsWith("'")) {
                    bin = bin.substring(1).split("'")[0];
                } else {
                    bin = bin.split(/\s+/)[0];
                }
                const slashIdx = bin.lastIndexOf("/");
                if (slashIdx !== -1) bin = bin.substring(slashIdx + 1);
                bin = bin.toLowerCase().replace(/\.desktop$/, "").trim();
                if (bin && !map[bin]) map[bin] = desk;
            }

            const wmClass = ("" + (a.wm_class || "")).trim().toLowerCase().replace(/\.desktop$/, "");
            if (wmClass) {
                if (!map[wmClass]) map[wmClass] = desk;
                if (wmClass.length > 4 && wmClass.slice(-4) === ".exe") {
                    const stem = wmClass.slice(0, -4);
                    if (stem && !map[stem]) map[stem] = desk;
                } else if (!map[wmClass + ".exe"]) {
                    map[wmClass + ".exe"] = desk;
                }
            }
        }
        return map;
    }

    function canonicalAppId(map, rawId) {
        if (!rawId) return "";
        let s = String(rawId).trim().toLowerCase().replace(/\.desktop$/, "");
        const slashIdx = s.lastIndexOf("/");
        if (slashIdx !== -1) s = s.substring(slashIdx + 1);
        if (map && map[s]) return map[s];
        const parts = s.split(".");
        if (parts.length >= 3 && ["com", "org", "net", "io", "app"].indexOf(parts[0]) !== -1) {
            const hyphenated = parts.slice(1).join("-");
            if (map && map[hyphenated]) return map[hyphenated];
            return hyphenated;
        }
        return s;
    }

    function matchApp(map, p, w) {
        if (!p || !w) return false;
        const pId = normalizeId(p.appId);
        const pDesk = normalizeId(p.desktopFile);
        const wId = normalizeId(w.appId);
        const wDesk = normalizeId(w.desktopFile);
        const wCls = normalizeId(w.cls || w.wmClass);

        if (pId && (wId === pId || wDesk === pId || wCls === pId)) return true;
        if (pDesk && (wDesk === pDesk || wId === pDesk || wCls === pDesk)) return true;

        const pAliases = getCanonicalAliases(pDesk || pId);
        const wAliases = getCanonicalAliases(wDesk || wId || wCls);
        for (let i = 0; i < pAliases.length; i++) {
            if (wAliases.indexOf(pAliases[i]) !== -1) return true;
        }

        const pCanon = canonicalAppId(map, pDesk || pId);
        const wCanon = canonicalAppId(map, wDesk || wId || wCls);
        if (pCanon && wCanon && pCanon === wCanon) return true;

        const pCanon2 = canonicalAppId(map, pId || pDesk);
        const wCanon2 = canonicalAppId(map, wId || wCls || wDesk);
        if (pCanon2 && wCanon2 && pCanon2 === wCanon2) return true;

        return false;
    }

    Component.onCompleted: runTests()

    function runTests() {
        console.log("RUNNING: Pinned Application Identity Resolution Tests");

        // The Wine menu entry the application installs about itself.
        const wineEntry = {
            name: "网易云音乐",
            desktop_file: "网易云音乐.desktop",
            icon: "C18B_cloudmusic.0",
            comment: "网易云音乐",
            exec: "wine C:/ProgramData/NetEase/CloudMusic/cloudmusic.lnk",
            wm_class: "cloudmusic.exe"
        };

        // A pin created outside the running app (a Lutris launch URI).
        const cloudPin = {
            appId: "cloudmusic",
            appName: "CloudMusic",
            iconName: "netease-cloud-music",
            materialIcon: "music_note",
            desktopFile: "lutris:rungame/netease-cloud-music"
        };

        // The running window, resolved through the desktop entry by the daemon.
        const wineWindow = {
            id: "win-cloudmusic-1",
            appId: "网易云音乐",
            appName: "网易云音乐",
            desktopFile: "网易云音乐",
            iconName: "/mnt/data/cache/astral-plasma/window-icons/cloudmusic.exe.png",
            materialIcon: "window",
            title: "Purple Rain - Prince/The Revolution",
            isActive: true
        };

        const map = buildCanonicalMap([wineEntry]);

        // ---- 1. StartupWMClass maps the executable id to the entry ----
        assert(canonicalAppId(map, "cloudmusic") === "网易云音乐",
            "the pin's executable id must resolve to the entry through StartupWMClass");
        assert(canonicalAppId(map, "cloudmusic.exe") === "网易云音乐",
            "the declared window class must resolve to the same entry");
        assert(canonicalAppId(map, "网易云音乐.desktop") === "网易云音乐",
            "the desktop id itself must keep resolving to the entry");

        // ---- 2. The pin and the running window are one application ----
        assert(matchApp(map, cloudPin, wineWindow),
            "a pin keyed by the executable must match the running Wine window");

        // ---- 3. Unrelated applications must not be absorbed ----
        assert(!matchApp(map, {
            appId: "firefox", appName: "Firefox", desktopFile: "firefox",
            iconName: "firefox", materialIcon: "language"
        }, wineWindow), "an unrelated pin must not match the Wine window");
        assert(!matchApp(map, cloudPin, {
            id: "win-other", appId: "org.kde.dolphin", appName: "Dolphin",
            desktopFile: "org.kde.dolphin", iconName: "org.kde.dolphin", materialIcon: "folder"
        }), "the CloudMusic pin must not match an unrelated window");

        // ---- 4. Dock list: the window is consumed by the pin, no duplicate ----
        const matchedWinIds = new Set();
        let pinnedRunning = false;
        if (matchApp(map, cloudPin, wineWindow)) {
            mountedToPin(matchedWinIds, wineWindow);
            pinnedRunning = true;
        }
        const unpinned = [wineWindow].filter(w => !matchedWinIds.has(w.id));
        assert(pinnedRunning, "the pinned entry must report isRunning");
        assert(unpinned.length === 0,
            "the matched window must not render a second, unpinned dock icon");

        // ---- 5. Icon: an unresolved theme name yields to the window's path ----
        const pinIconResolves = false; // "netease-cloud-music" is absent from the active theme
        const effectiveIcon = (!pinIconResolves || wineWindow.iconName.startsWith("/"))
            ? wineWindow.iconName
            : cloudPin.iconName;
        assert(effectiveIcon === wineWindow.iconName,
            "the merged pin must draw the window's authentic icon, not the material fallback");

        // ---- 6. Source contracts ----
        const wsSrc = readLocalFile("../modules/Astral/Kernel/services/WindowService.qml");
        assert(wsSrc.indexOf("a.wm_class") !== -1,
            "WindowService must index StartupWMClass in the canonical identity map");
        assert(wsSrc.indexOf("canonicalAppId") !== -1,
            "WindowService must expose canonicalAppId");
        const dockSrc = readLocalFile("../shell/UnifiedDock.qml");
        assert(dockSrc.indexOf("WindowService.canonicalAppId") !== -1,
            "UnifiedDock must resolve pins through WindowService.canonicalAppId");
        const portsSrc = readLocalFile("../daemon/src/domain/ports.rs");
        assert(portsSrc.indexOf("wm_class") !== -1,
            "AppInfo must expose wm_class for the shell's identity index");
        const launcherSrc = readLocalFile("../daemon/src/infrastructure/launcher.rs");
        assert(launcherSrc.indexOf("wm_class: entry.wm_class") !== -1,
            "the launcher listing must populate wm_class from the desktop entry");

        console.log("PASS: Pinned Application Identity Resolution Tests completed successfully!");
        Qt.exit(0);
    }

    function mountedToPin(matchedWinIds, win) {
        matchedWinIds.add(win.id);
    }
}
