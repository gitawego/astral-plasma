import QtQuick

// ============================================================================
// Launcher App Discovery — an installed entry is re-read, never remembered
// ============================================================================
// The launcher's app list is a cache of the XDG desktop entries. A cache read
// once at shell start cannot answer for an application installed while the shell
// is running: Herdr was installed, `astral-plasma apps` listed it immediately,
// and the launcher kept showing the pre-install list until the shell restarted.
//
// The daemon half already re-stamps its index when the applications directory
// changes (docs/LESSONS.md §29); the shell half must re-ask on every open, and
// must do so without blanking the list, spawning twice, or moving the
// highlighted row.
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

    // Deterministic model of the launcher's cache policy: the refresh trigger,
    // the in-flight coalescing and the payload application are mirrored from
    // shell/CommandLauncher.qml so the behaviour is testable offscreen.
    QtObject {
        id: cache

        property var installedApps: [
            { name: "Alacritty", desktop_file: "Alacritty.desktop", exec: "alacritty" },
            { name: "Dolphin", desktop_file: "org.kde.dolphin.desktop", exec: "dolphin" },
            { name: "Kate", desktop_file: "org.kde.kate.desktop", exec: "kate" }
        ]
        property int selectedAppIndex: 0
        property string queryText: ""
        property bool running: false
        property int spawns: 0

        readonly property var filteredApps: {
            const q = queryText.trim().toLowerCase();
            if (!q) return installedApps;
            const res = [];
            for (let i = 0; i < installedApps.length; i++) {
                const app = installedApps[i];
                const key = app._searchKey || ((app.name || "") + " " + (app.comment || "") + " " + (app.exec || "")).toLowerCase();
                if (key.indexOf(q) !== -1) res.push(app);
            }
            return res;
        }

        // CommandLauncher.refreshInstalledApps()
        function refreshInstalledApps() {
            if (running) return;
            running = true;
            spawns++;
        }

        // CommandLauncher.onActiveVisibleChanged -> open
        function openLauncher() {
            queryText = "";
            refreshInstalledApps();
        }

        // CommandLauncher.appsProc.onStreamFinished
        function deliver(payloadText) {
            running = false;
            if (payloadText === null) return;
            let parsed;
            try {
                parsed = JSON.parse(payloadText);
            } catch (e) {
                return;
            }
            if (!Array.isArray(parsed)) return;
            for (let i = 0; i < parsed.length; i++) {
                const a = parsed[i];
                a._searchKey = ((a.name || "") + " " + (a.comment || "") + " " + (a.exec || "")).toLowerCase();
            }
            const previous = filteredApps[selectedAppIndex];
            installedApps = parsed;
            const visible = filteredApps;
            if (previous && previous.desktop_file) {
                for (let i = 0; i < visible.length; i++) {
                    if (visible[i].desktop_file === previous.desktop_file) {
                        selectedAppIndex = i;
                        return;
                    }
                }
            }
            selectedAppIndex = Math.max(0, Math.min(selectedAppIndex, visible.length - 1));
        }

        function search(q) {
            queryText = q;
        }
    }

    Timer {
        interval: 50
        running: true
        repeat: false
        onTriggered: runTests()
    }

    function runTests() {
        console.log("RUNNING: Launcher App Discovery Tests");

        const launcherCode = readLocalFile("../shell/CommandLauncher.qml");
        const overviewCode = readLocalFile("../modules/Astral/Apps/Overview/Main.qml");
        assert(launcherCode.length > 1000, "CommandLauncher.qml must be readable");
        assert(overviewCode.length > 1000, "the overview app must be readable");

        // ---- 1. The launcher re-reads its cache on every open ----------------
        assert(/function refreshInstalledApps\s*\(/.test(launcherCode),
            "CommandLauncher must expose refreshInstalledApps()");
        assert(/if\s*\(\s*appsProc\.running\s*\)\s*return;/.test(launcherCode),
            "refreshInstalledApps must coalesce an in-flight query instead of spawning twice");
        assert(!/installedApps\.length\s*===\s*0/.test(launcherCode),
            "CommandLauncher must not gate the refresh on an empty cache (an installed app leaves the cache non-empty)");

        const launcherOpen = launcherCode.slice(launcherCode.indexOf("onActiveVisibleChanged"));
        assert(launcherOpen.length > 0, "CommandLauncher must keep onActiveVisibleChanged");
        assert(/refreshInstalledApps\(\s*\)/.test(launcherOpen),
            "Opening the launcher must re-read installed applications");

        // ---- 2. A refresh must not blank the list or move the highlighted row -
        assert(/previous\.desktop_file/.test(launcherCode) && /desktop_file\s*===\s*previous\.desktop_file/.test(launcherCode),
            "Applying a fresh payload must restore the selection by desktop_file");

        // ---- 3. The overview shares the same policy (single app index) ------
        // The refresh belongs to the *visible* branch of the handler, before the
        // branch that tears the overview down.
        const overviewHook = overviewCode.indexOf("onOverviewVisibleChanged");
        assert(overviewHook !== -1, "ActiveAppsOverview must keep onOverviewVisibleChanged");
        const overviewElse = overviewCode.indexOf("} else {", overviewHook);
        assert(overviewElse > overviewHook, "onOverviewVisibleChanged must keep its visible/else branches");
        const overviewOpen = overviewCode.slice(overviewHook, overviewElse);
        assert(/session\.reloadInstalledApps\(\s*\)/.test(overviewOpen),
            "Opening the overview must re-read the shared app index through the session port");
        assert(!/typeof WindowService/.test(overviewCode),
            "the overview must not reach for the kernel's WindowService singleton");

        // ---- 4. Opening a launcher whose cache is warm still queries ---------
        assert(cache.spawns === 0, "No query has been started yet");
        cache.openLauncher();
        assert(cache.spawns === 1, "Opening the launcher must query the daemon even with a warm cache");

        // ---- 5. A second open during an in-flight query does not spawn twice -
        cache.openLauncher();
        assert(cache.spawns === 1, "Re-opening while a query is in flight must not spawn another");

        // ---- 6. A freshly installed app becomes searchable -------------------
        cache.search("herdr");
        assert(cache.filteredApps.length === 0, "Herdr is not in the stale list yet");
        cache.deliver(JSON.stringify([
            { name: "Alacritty", desktop_file: "Alacritty.desktop", exec: "alacritty" },
            { name: "Dolphin", desktop_file: "org.kde.dolphin.desktop", exec: "dolphin" },
            { name: "Herdr", desktop_file: "herdr-app.desktop", comment: "Terminals and coding agents that keep running", exec: "/home/hlu/.local/bin/herdr-app" },
            { name: "Kate", desktop_file: "org.kde.kate.desktop", exec: "kate" }
        ]));
        assert(cache.filteredApps.length === 1, "Herdr must be searchable as soon as the fresh list lands");
        assert(cache.filteredApps[0].desktop_file === "herdr-app.desktop", "Matched app must be Herdr");

        // ---- 7. The highlighted row stays on the same application ------------
        cache.search("");
        cache.selectedAppIndex = 3; // Kate, in the four-entry list
        assert(cache.filteredApps[3].desktop_file === "org.kde.kate.desktop", "Row 3 is Kate before the refresh");
        cache.openLauncher();
        cache.deliver(JSON.stringify([
            { name: "AAA New App", desktop_file: "aaa-new.desktop", exec: "aaa-new" },
            { name: "AAB New App", desktop_file: "aab-new.desktop", exec: "aab-new" },
            { name: "Alacritty", desktop_file: "Alacritty.desktop", exec: "alacritty" },
            { name: "Dolphin", desktop_file: "org.kde.dolphin.desktop", exec: "dolphin" },
            { name: "Kate", desktop_file: "org.kde.kate.desktop", exec: "kate" }
        ]));
        assert(cache.selectedAppIndex === 4, "Selection must move with Kate to index 4");
        assert(cache.filteredApps[cache.selectedAppIndex].desktop_file === "org.kde.kate.desktop",
            "Selection must follow Kate by identity, not by position");

        // ---- 8. A failed query keeps the last good list ----------------------
        const count = cache.installedApps.length;
        cache.deliver("not json");
        cache.deliver(null);
        assert(cache.installedApps.length === count, "A failed query must not blank the launcher");
        assert(cache.filteredApps.length === count, "The cached list must survive a failed query");

        // ---- 9. A disappearing selection clamps into range -------------------
        cache.search("");
        cache.selectedAppIndex = 3;
        cache.deliver(JSON.stringify([
            { name: "Alacritty", desktop_file: "Alacritty.desktop", exec: "alacritty" },
            { name: "Dolphin", desktop_file: "org.kde.dolphin.desktop", exec: "dolphin" }
        ]));
        assert(cache.selectedAppIndex === 1, "Selection must clamp when the highlighted app is uninstalled");

        console.log("PASS: Launcher App Discovery Tests");
        Qt.exit(0);
    }
}
