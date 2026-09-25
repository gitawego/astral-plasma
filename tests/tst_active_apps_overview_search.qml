import QtQuick

// Test suite for ActiveAppsOverview integrated search:
// Verifies filtering across open windows and installed apps,
// ranking priority, keyboard navigation, and execution routing.
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
            throw new Error(msg);
        }
    }

    // Search model test harness matching ActiveAppsOverview logic
    QtObject {
        id: searchHarness

        property string queryText: ""
        property int selectedSearchIndex: 0
        property int selectedGridIndex: 0

        property var windows: [
            { id: 101, title: "Ghostty - astral-plasma", appName: "Ghostty", appId: "com.mitchellh.ghostty", isActive: true },
            { id: 102, title: "Pull Requests · astral-plasma - Firefox", appName: "Firefox", appId: "firefox", isActive: false },
            { id: 103, title: "Dolphin - /home/hlu/Downloads", appName: "Dolphin", appId: "org.kde.dolphin", isActive: false }
        ]

        property var installedApps: [
            { name: "Firefox", desktop_file: "firefox.desktop", comment: "Web Browser", exec: "firefox", icon: "firefox" },
            { name: "Ghostty", desktop_file: "com.mitchellh.ghostty.desktop", comment: "Terminal Emulator", exec: "ghostty", icon: "ghostty" },
            { name: "GIMP Image Editor", desktop_file: "gimp.desktop", comment: "Create images and edit photographs", exec: "gimp-2.10", icon: "gimp" },
            { name: "Dolphin", desktop_file: "org.kde.dolphin.desktop", comment: "File Manager", exec: "dolphin", icon: "system-file-manager" },
            { name: "System Settings", desktop_file: "systemsettings.desktop", comment: "Configure the system", exec: "systemsettings", icon: "preferences-system" },
            { name: "Visual Studio Code", desktop_file: "code.desktop", comment: "Code Editing", exec: "code", icon: "vscode" }
        ]

        property string lastActivatedWindowId: ""
        property string lastLaunchedTarget: ""
        property bool overviewClosed: false

        readonly property string searchQuery: queryText.trim().toLowerCase()

        function scoreItem(text, q) {
            if (!text) return 0;
            const t = text.toLowerCase();
            if (t === q) return 100;
            if (t.startsWith(q)) return 80;
            const wordIdx = t.indexOf(" " + q);
            if (wordIdx !== -1) return 60;
            if (t.indexOf(q) !== -1) return 40;
            return 0;
        }

        readonly property var matchingWindows: {
            if (!searchQuery) return [];
            const q = searchQuery;
            const wins = searchHarness.windows || [];
            const scored = [];
            for (let i = 0; i < wins.length; i++) {
                const w = wins[i];
                const sApp = scoreItem(w.appName, q);
                const sTitle = scoreItem(w.title, q);
                const sId = scoreItem(w.appId, q);
                const best = Math.max(sApp, sTitle, sId);
                if (best > 0) {
                    scored.push({ win: w, score: best });
                }
            }
            scored.sort((a, b) => b.score - a.score);
            return scored.map(item => item.win);
        }

        readonly property var matchingInstalledApps: {
            if (!searchQuery) return [];
            const q = searchQuery;
            const apps = searchHarness.installedApps || [];
            const scored = [];
            for (let i = 0; i < apps.length; i++) {
                const a = apps[i];
                const sName = scoreItem(a.name, q);
                const sComment = scoreItem(a.comment, q);
                const sExec = scoreItem(a.exec, q);
                const best = Math.max(sName, sComment > 0 ? sComment - 20 : 0, sExec > 0 ? sExec - 30 : 0);
                if (best > 0) {
                    scored.push({ app: a, score: best });
                }
            }
            scored.sort((a, b) => b.score - a.score);
            return scored.map(item => item.app);
        }

        readonly property var searchResults: {
            if (!searchQuery) return [];
            const res = [];
            for (let i = 0; i < matchingWindows.length; i++) {
                res.push({ type: "window", data: matchingWindows[i] });
            }
            for (let j = 0; j < matchingInstalledApps.length; j++) {
                res.push({ type: "app", data: matchingInstalledApps[j] });
            }
            return res;
        }

        onQueryTextChanged: {
            selectedSearchIndex = 0;
        }

        function selectNext() {
            if (searchResults.length > 0) {
                selectedSearchIndex = Math.min(searchResults.length - 1, selectedSearchIndex + 1);
            }
        }

        function selectPrevious() {
            if (searchResults.length > 0) {
                selectedSearchIndex = Math.max(0, selectedSearchIndex - 1);
            }
        }

        function executeCurrent() {
            if (searchResults.length === 0) return;
            const item = searchResults[selectedSearchIndex];
            if (!item) return;
            if (item.type === "window") {
                lastActivatedWindowId = String(item.data.id);
                overviewClosed = true;
            } else if (item.type === "app") {
                lastLaunchedTarget = item.data.desktop_file || item.data.exec || item.data.name;
                overviewClosed = true;
            }
        }

        function handleEscape() {
            if (queryText.length > 0) {
                queryText = "";
            } else {
                overviewClosed = true;
            }
        }
    }

    function runTests() {
        console.log("RUNNING: Active apps overview search tests");

        // ---- 1. WindowService exposes installedApps and reloadInstalledApps ---
        const wsCode = readLocalFile("../services/WindowService.qml");
        assert(wsCode.length > 1000, "WindowService.qml must be readable");
        assert(/property var installedApps:\s*\[\]/.test(wsCode),
            "WindowService must declare property var installedApps: []");
        assert(/installedAppsProc/.test(wsCode),
            "WindowService must define installedAppsProc process");
        assert(/function reloadInstalledApps\(/.test(wsCode),
            "WindowService must define reloadInstalledApps()");

        // ---- 2. Empty query returns no search results (shows Exposé grid) -----
        searchHarness.queryText = "";
        assert(searchHarness.searchResults.length === 0,
            "Empty query must produce 0 search results");
        assert(searchHarness.matchingWindows.length === 0,
            "Empty query must produce 0 matching windows");
        assert(searchHarness.matchingInstalledApps.length === 0,
            "Empty query must produce 0 matching installed apps");

        // ---- 3. Searching 'fire' matches both open window and installed app ---
        searchHarness.queryText = "fire";
        assert(searchHarness.matchingWindows.length === 1,
            "Searching 'fire' should match 1 open Firefox window");
        assert(searchHarness.matchingWindows[0].appName === "Firefox",
            "Matching open window should be Firefox");
        assert(searchHarness.matchingInstalledApps.length >= 1,
            "Searching 'fire' should match at least 1 installed app");
        assert(searchHarness.matchingInstalledApps[0].name === "Firefox",
            "First matching installed app should be Firefox");
        assert(searchHarness.searchResults.length === 2,
            "Total search results for 'fire' should be 2 (1 window + 1 app)");
        assert(searchHarness.searchResults[0].type === "window",
            "First result item should be the running window");
        assert(searchHarness.searchResults[1].type === "app",
            "Second result item should be the installed app");

        // ---- 4. Prefix ranking puts exact/prefix match at the top ------------
        searchHarness.queryText = "g";
        // 'Ghostty' starts with 'g', 'GIMP' starts with 'g'
        assert(searchHarness.matchingInstalledApps.length >= 2,
            "Searching 'g' should match Ghostty and GIMP");
        const topApp = searchHarness.matchingInstalledApps[0].name;
        assert(topApp === "Ghostty" || topApp === "GIMP Image Editor",
            "Top app match for 'g' should be a prefix match");

        // ---- 5. Arrow key navigation across sections -------------------------
        searchHarness.queryText = "fire";
        assert(searchHarness.selectedSearchIndex === 0,
            "Initial selectedSearchIndex should be 0");
        searchHarness.selectNext();
        assert(searchHarness.selectedSearchIndex === 1,
            "Pressing down should select index 1 (the installed app)");
        searchHarness.selectNext();
        assert(searchHarness.selectedSearchIndex === 1,
            "Pressing down at the end should clamp at max index");
        searchHarness.selectPrevious();
        assert(searchHarness.selectedSearchIndex === 0,
            "Pressing up should return to index 0");
        searchHarness.selectPrevious();
        assert(searchHarness.selectedSearchIndex === 0,
            "Pressing up at 0 should clamp at 0");

        // ---- 6. Execution routing --------------------------------------------
        // Execute window item (index 0)
        searchHarness.overviewClosed = false;
        searchHarness.lastActivatedWindowId = "";
        searchHarness.executeCurrent();
        assert(searchHarness.lastActivatedWindowId === "102",
            "Executing window item should activate window ID 102");
        assert(searchHarness.overviewClosed === true,
            "Executing item should close overview");

        // Execute app item (index 1)
        searchHarness.selectNext();
        searchHarness.overviewClosed = false;
        searchHarness.lastLaunchedTarget = "";
        searchHarness.executeCurrent();
        assert(searchHarness.lastLaunchedTarget === "firefox.desktop",
            "Executing app item should launch firefox.desktop");
        assert(searchHarness.overviewClosed === true,
            "Executing app item should close overview");

        // ---- 7. Escape behavior ----------------------------------------------
        searchHarness.queryText = "terminal";
        searchHarness.overviewClosed = false;
        searchHarness.handleEscape();
        assert(searchHarness.queryText === "",
            "Escape with non-empty query should clear query text");
        assert(searchHarness.overviewClosed === false,
            "Escape with non-empty query should NOT close overview");
        searchHarness.handleEscape();
        assert(searchHarness.overviewClosed === true,
            "Escape with empty query should close overview");

        // ---- 8. Searching app that is NOT currently running ------------------
        searchHarness.queryText = "gimp";
        assert(searchHarness.matchingWindows.length === 0,
            "Searching 'gimp' should have 0 open windows");
        assert(searchHarness.matchingInstalledApps.length === 1,
            "Searching 'gimp' should match 1 installed app");
        assert(searchHarness.searchResults.length === 1,
            "Total search results should be 1");
        assert(searchHarness.searchResults[0].type === "app",
            "Result should be of type 'app'");

        // ---- 9. Structural verification of ActiveAppsOverview.qml ------------
        const surface = readLocalFile("../shell/ActiveAppsOverview.qml");
        assert(surface.length > 1000, "ActiveAppsOverview.qml must be readable");
        assert(/TextInput/.test(surface),
            "ActiveAppsOverview must contain a TextInput for search input");
        assert(/matchingWindows/.test(surface),
            "ActiveAppsOverview must define matchingWindows");
        assert(/matchingInstalledApps/.test(surface),
            "ActiveAppsOverview must define matchingInstalledApps");
        assert(/searchResults/.test(surface),
            "ActiveAppsOverview must define searchResults");

        console.log("PASS: Active apps overview search tests passed");
        Qt.exit(0);
    }
}
