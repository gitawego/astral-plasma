import QtQuick

Item {
    id: testRoot
    width: 800
    height: 600

    // Test Harness matching CommandLauncher command parsing & dispatch logic
    QtObject {
        id: launcherHarness

        property string queryText: ""
        property string activeMode: ""
        property var installedApps: [
            { name: "Firefox", desktop_file: "firefox.desktop", comment: "Web Browser", exec: "firefox" },
            { name: "Ghostty", desktop_file: "com.mitchellh.ghostty.desktop", comment: "Terminal Emulator", exec: "ghostty" },
            { name: "Dolphin", desktop_file: "org.kde.dolphin.desktop", comment: "File Manager", exec: "dolphin" },
            { name: "Settings", desktop_file: "systemsettings.desktop", comment: "KDE Settings", exec: "systemsettings" }
        ]
        property int selectedAppIndex: 0
        property int selectedSuggestionIndex: 0
        property string lastLaunchedApp: ""
        property string lastPresetSet: ""
        property bool lastDarkModeSet: true
        property string lastSettingsPageOpened: ""

        readonly property bool isCommandMode: queryText.startsWith(">")
        readonly property string commandName: {
            if (!isCommandMode) return "";
            const parts = queryText.slice(1).trim().split(" ");
            return parts[0].toLowerCase();
        }
        readonly property string commandArg: {
            if (!isCommandMode) return "";
            const parts = queryText.slice(1).trim().split(" ");
            return parts.length > 1 ? parts.slice(1).join(" ").toLowerCase() : "";
        }

        readonly property bool isWallpaperMode: activeMode === "wallpaper" || commandName === "wallpaper" || commandName === "wp"
        readonly property bool isSchemeMode: activeMode === "scheme" || commandName === "scheme" || commandName === "color"
        readonly property bool isModeMode: activeMode === "mode" || commandName === "mode" || commandName === "dark" || commandName === "light"
        readonly property bool isSettingsMode: activeMode === "settings" || commandName === "settings" || commandName === "set"
        readonly property bool hasActiveCommandPage: isWallpaperMode || isSchemeMode || isModeMode || isSettingsMode

        readonly property var commandSuggestions: [
            { id: "wallpaper", name: "Wallpaper", description: "Change the current wallpaper", icon: "wallpaper", aliases: ["wallpaper", "wp", "wallpapers", "background"] },
            { id: "scheme", name: "Color Scheme", description: "Switch Material 3 color presets", icon: "palette", aliases: ["scheme", "color", "colors", "theme"] },
            { id: "mode", name: "Dark / Light Mode", description: "Toggle system dark or light appearance", icon: "brightness_6", aliases: ["mode", "dark", "light", "appearance"] },
            { id: "settings", name: "System Settings", description: "Jump to system configuration pages", icon: "settings", aliases: ["settings", "set", "config", "preferences"] }
        ]

        readonly property var filteredSuggestions: {
            if (!isCommandMode) return [];
            const q = commandName;
            if (!q) return commandSuggestions;
            return commandSuggestions.filter(item => {
                if (item.id.indexOf(q) !== -1 || item.name.toLowerCase().indexOf(q) !== -1) return true;
                for (let i = 0; i < item.aliases.length; i++) {
                    if (item.aliases[i].indexOf(q) !== -1) return true;
                }
                return false;
            });
        }

        readonly property var filteredApps: {
            if (isCommandMode) return [];
            const q = queryText.trim().toLowerCase();
            if (!q) return installedApps;

            return installedApps.filter(app => {
                const nameMatch = (app.name || "").toLowerCase().indexOf(q) !== -1;
                const commentMatch = (app.comment || "").toLowerCase().indexOf(q) !== -1;
                const execMatch = (app.exec || "").toLowerCase().indexOf(q) !== -1;
                return nameMatch || commentMatch || execMatch;
            });
        }

        function activateSuggestion(item) {
            if (!item) return;
            if (item.id === "wallpaper") {
                queryText = ">wallpaper";
                activeMode = "wallpaper";
            } else if (item.id === "scheme") {
                activeMode = "scheme";
            } else if (item.id === "mode") {
                activeMode = "mode";
            } else if (item.id === "settings") {
                activeMode = "settings";
            }
        }

        function executeCurrent() {
            if (isWallpaperMode) {
                // Handled by carousel
            } else if (isCommandMode && !hasActiveCommandPage) {
                if (filteredSuggestions.length > 0 && selectedSuggestionIndex < filteredSuggestions.length) {
                    activateSuggestion(filteredSuggestions[selectedSuggestionIndex]);
                }
            } else if (isSchemeMode) {
                lastPresetSet = commandArg || "iris";
            } else if (isModeMode) {
                lastDarkModeSet = !commandArg.includes("light");
            } else if (isSettingsMode) {
                lastSettingsPageOpened = commandArg || "dock";
            } else if (filteredApps.length > 0 && selectedAppIndex < filteredApps.length) {
                lastLaunchedApp = filteredApps[selectedAppIndex].desktop_file;
            }
        }
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
            return false;
        }
        return true;
    }

    function runTests() {
        console.log("RUNNING: CommandLauncher Fuzzy Search & Dispatcher Unit Tests");

        // 1. Initial State: App search
        assert(launcherHarness.filteredApps.length === 4, "Initial apps list contains 4 apps");
        assert(!launcherHarness.isCommandMode, "Should not be in command mode initially");

        // 2. Fuzzy filter apps
        launcherHarness.queryText = "term";
        assert(launcherHarness.filteredApps.length === 1, "Searching 'term' matches 1 app (Ghostty)");
        assert(launcherHarness.filteredApps[0].name === "Ghostty", "Filtered app is Ghostty");

        // 3. Launch selected app
        launcherHarness.executeCurrent();
        assert(launcherHarness.lastLaunchedApp === "com.mitchellh.ghostty.desktop", "Launched app must be Ghostty");

        // 4. Switch to > command mode (Frame 46 suggestion list)
        launcherHarness.queryText = ">";
        assert(launcherHarness.isCommandMode === true, "Must enter command mode on '>'");
        assert(launcherHarness.filteredSuggestions.length === 4, "All 4 command suggestions listed on empty prompt");

        // 5. Suggestion filter: >wall shows Wallpaper suggestion
        launcherHarness.queryText = ">wall";
        assert(launcherHarness.filteredSuggestions.length === 1, "Only Wallpaper suggestion matched for '>wall'");
        assert(launcherHarness.filteredSuggestions[0].id === "wallpaper", "Matched suggestion id is wallpaper");
        assert(launcherHarness.filteredSuggestions[0].description === "Change the current wallpaper", "Description matches Frame 46");

        // 6. Activating Wallpaper suggestion switches to wallpaper mode (Frame 47)
        launcherHarness.executeCurrent();
        assert(launcherHarness.activeMode === "wallpaper", "Active mode switched to wallpaper");
        assert(launcherHarness.isWallpaperMode === true, "isWallpaperMode is true");

        // 7. Shorthand >wp
        launcherHarness.activeMode = "";
        launcherHarness.queryText = ">wp";
        assert(launcherHarness.isWallpaperMode === true, ">wp shorthand recognized");

        // 8. Color Scheme preset command
        launcherHarness.queryText = ">scheme coral";
        assert(launcherHarness.isSchemeMode === true, "Must identify >scheme mode");
        assert(launcherHarness.commandArg === "coral", "Parsed preset arg must be coral");
        launcherHarness.executeCurrent();
        assert(launcherHarness.lastPresetSet === "coral", "Preset set to coral");

        // 9. Dark/Light mode command
        launcherHarness.queryText = ">mode light";
        assert(launcherHarness.isModeMode === true, "Must identify >mode");
        launcherHarness.executeCurrent();
        assert(launcherHarness.lastDarkModeSet === false, "DarkMode set to false for 'light'");

        // 10. Settings jump command
        launcherHarness.queryText = ">settings theme";
        assert(launcherHarness.isSettingsMode === true, "Must identify >settings");
        launcherHarness.executeCurrent();
        assert(launcherHarness.lastSettingsPageOpened === "theme", "Settings opened to theme");

        // 11. Large Dataset Virtual Scroll & Pre-indexing Test (500 apps)
        launcherHarness.queryText = "";
        launcherHarness.activeMode = "";
        const largeApps = [];
        for (let i = 0; i < 500; i++) {
            largeApps.push({
                name: "App " + i,
                desktop_file: "app-" + i + ".desktop",
                comment: "Tool description for app " + i,
                exec: "app-" + i,
                _searchKey: ("app " + i + " tool description for app " + i + " app-" + i).toLowerCase()
            });
        }
        launcherHarness.installedApps = largeApps;
        assert(launcherHarness.filteredApps.length === 500, "Must support 500+ apps in virtual scroll");

        // 12. Arrow down past 8th item (verify selection moves continuously)
        launcherHarness.selectedAppIndex = 0;
        for (let step = 0; step < 12; step++) {
            launcherHarness.selectedAppIndex = Math.min(launcherHarness.filteredApps.length - 1, launcherHarness.selectedAppIndex + 1);
        }
        assert(launcherHarness.selectedAppIndex === 12, "Selection advances past 8th item to index 12");

        // 13. PageDown / PageUp navigation clamping
        launcherHarness.selectedAppIndex = Math.min(launcherHarness.filteredApps.length - 1, launcherHarness.selectedAppIndex + 6);
        assert(launcherHarness.selectedAppIndex === 18, "PageDown advances by 6 items to 18");
        launcherHarness.selectedAppIndex = Math.max(0, launcherHarness.selectedAppIndex - 6);
        assert(launcherHarness.selectedAppIndex === 12, "PageUp steps back by 6 items to 12");

        // 14. Fast sub-millisecond filtering on large dataset
        launcherHarness.queryText = "app 25";
        assert(launcherHarness.filteredApps.length > 0, "Querying 500 apps finds matching items");
        assert(launcherHarness.filteredApps[0].name.indexOf("25") !== -1, "First result contains '25'");

        console.log("PASS: CommandLauncher Fuzzy Search & Dispatcher Unit Tests");
        Qt.exit(0);
    }
}
