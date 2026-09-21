pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // Shipped defaults: the app-folder file. Read-only at runtime - it lives in
    // the checkout, so writing to it would mix user preferences into version
    // control and dirty the tree on every change.
    readonly property string defaultConfigPath: Qt.resolvedUrl("./settings.json").toString().replace("file://", "")

    // Live user settings: the XDG config dir, e.g.
    // $XDG_CONFIG_HOME/astral-plasma/settings.json (~/.config/... by default).
    // This is the only file ever written.
    readonly property string userConfigPath: {
        const xdg = (typeof Quickshell !== "undefined" && Quickshell.env)
            ? Quickshell.env("XDG_CONFIG_HOME") : "";
        const home = (typeof Quickshell !== "undefined" && Quickshell.env)
            ? (Quickshell.env("HOME") || "") : "";
        const base = (xdg && xdg.length > 0) ? xdg : (home + "/.config");
        return base + "/astral-plasma/settings.json";
    }

    // Code-level defaults. The live settings are the deep merge of these, the
    // shipped `defaultConfigPath` file, and the user's `userConfigPath` file.
    readonly property var defaultSettings: ({
        "dock": {
            "enabled": true,
            "position": "left",
            "width": 64,
            "iconSize": 32,
            "margin": 12,
            "exclusiveZone": true,
            "entries": [
                "launcher",
                "taskbar",
                "clock",
                "tray",
                "statusIcons",
                "settings",
                "power"
            ],
            "tray": {
                "enabled": true,
                "compact": false,
                "hiddenIcons": []
            },
            "statusIcons": [
                { "id": "kblayout", "enabled": true },
                { "id": "network", "enabled": true },
                { "id": "bluetooth", "enabled": true },
                { "id": "brightness", "enabled": true },
                { "id": "audio", "enabled": true },
                { "id": "battery", "enabled": true }
            ]
        },
        "dashboard": {
            "enabled": true,
            "defaultTab": "dashboard",
            "mediaAvatar": "",
            "tabs": [
                { "id": "dashboard", "label": "Dashboard", "enabled": true },
                { "id": "media", "label": "Media", "enabled": true },
                { "id": "performance", "label": "Performance", "enabled": true },
                { "id": "workspaces", "label": "Workspaces", "enabled": true }
            ],
            "weather": {
                "location": "auto",
                "units": "metric"
            }
        },
        "topBar": {
            "enabled": true,
            "height": 38,
            "exclusiveZone": true,
            "showTitle": true,
            "showTabs": true
        },
        "theme": {
            "mode": "dynamic",
            "preset": "iris",
            "blurStrength": 0.85,
            "cornerRadius": 20
        },
        "debugMode": false
    })

    property var settings: root.defaultSettings

    // Single Debug Mode toggle (gates all debug features & freeze)
    readonly property bool debugMode: root.settings.debugMode ?? false

    // Convenient getters
    readonly property bool dockEnabled: root.settings.dock ? (root.settings.dock.enabled ?? true) : true
    readonly property int dockIconSize: (root.settings.dock && root.settings.dock.iconSize !== undefined) ? root.settings.dock.iconSize : 32
    readonly property int dockStatusIconSize: (root.settings.dock && root.settings.dock.statusIconSize !== undefined)
        ? root.settings.dock.statusIconSize
        : root.dockIconSize
    readonly property int dockWidth: {
        const rawW = root.settings.dock ? (root.settings.dock.width ?? 64) : 64;
        const maxIcon = Math.max(root.dockIconSize, root.dockStatusIconSize);
        return Math.max(rawW, maxIcon + 24);
    }
    readonly property int borderThickness: root.settings.border ? (root.settings.border.thickness ?? 14) : 14
    readonly property int borderRounding: root.settings.border ? (root.settings.border.rounding ?? 20) : 20
    readonly property bool topBarEnabled: root.settings.topBar ? (root.settings.topBar.enabled ?? false) : false
    readonly property int topBarHeight: root.settings.topBar ? (root.settings.topBar.height ?? 38) : 38
    readonly property bool topBarExclusiveZone: root.settings.topBar ? (root.settings.topBar.exclusiveZone ?? false) : false
    readonly property bool topBarShowTitle: root.settings.topBar ? (root.settings.topBar.showTitle ?? true) : true
    readonly property bool topBarShowTabs: root.settings.topBar ? (root.settings.topBar.showTabs ?? true) : true
    readonly property bool topBarShowWeather: true
    readonly property bool dashboardShowOnHover: root.settings.dashboard ? (root.settings.dashboard.showOnHover ?? true) : true
    readonly property int dashboardWidth: root.settings.dashboard ? (root.settings.dashboard.width ?? 980) : 980
    readonly property string mediaAvatar: {
        if (root.settings.dashboard && root.settings.dashboard.mediaAvatar !== undefined && root.settings.dashboard.mediaAvatar !== "") {
            return root.settings.dashboard.mediaAvatar;
        }
        if (root.settings.media && root.settings.media.avatar !== undefined && root.settings.media.avatar !== "") {
            return root.settings.media.avatar;
        }
        return "";
    }
    readonly property var disablePlasmaPanels: {
        if (!root.settings.plasma) return "all";
        if (root.settings.plasma.disablePanels !== undefined) return root.settings.plasma.disablePanels;
        if (root.settings.plasma.disableTopPanel) return "all";
        return "all";
    }
    readonly property bool disablePlasmaNotifications: {
        if (!root.settings.plasma) return true;
        if (root.settings.plasma.disableNotifications !== undefined) return root.settings.plasma.disableNotifications;
        return true;
    }
    readonly property string plasmaBackupDir: root.settings.plasma?.backupDir ?? ""
    readonly property bool autoRestorePlasmaOnExit: root.settings.plasma?.autoRestoreOnExit ?? true

    // Theme getters
    readonly property bool isDarkMode: root.settings.theme ? (root.settings.theme.darkMode ?? (root.settings.theme.mode !== "light")) : true
    readonly property string themeMode: root.isDarkMode ? "dark" : "light"
    readonly property bool dynamicColors: root.settings.theme ? (root.settings.theme.dynamicColors ?? (root.settings.theme.mode === "dynamic")) : false
    readonly property string themePreset: root.settings.theme ? (root.settings.theme.preset ?? "iris") : "iris"
    readonly property int themeCornerRadius: root.settings.theme ? (root.settings.theme.cornerRadius ?? 20) : 20

    // Dynamic script path resolution (config-driven, agnostic, zero hardcoded paths)
    readonly property string scriptsDir: {
        let url = Qt.resolvedUrl("../scripts").toString();
        if (url.startsWith("file://")) {
            return url.substring(7);
        }
        return url;
    }

    function scriptPath(scriptName) {
        return root.scriptsDir + "/" + scriptName;
    }

    readonly property string daemonBin: {
        let url = Qt.resolvedUrl("../bin/astral-plasma").toString();
        if (url.startsWith("file://")) return url.substring(7);
        return url;
    }

    // Centralized, robust icon URL resolution
    // 1. Direct file paths are formatted as file://
    // 2. Existing theme icons are resolved via Quickshell.iconPath
    // 3. Fallback to extensionless name if .png/.svg was passed
    // 4. Returns "" if icon does not exist, preventing Quickshell from rendering magenta/black checkerboards
    function iconUrl(iconName) {
        if (!iconName) return "";
        let s = ("" + iconName).trim();
        if (s === "" || s.startsWith("Error")) return "";
        if (s.indexOf("/") !== -1) {
            return s.startsWith("file://") ? s : ("file://" + s);
        }
        if (Quickshell.hasThemeIcon(s)) {
            return Quickshell.iconPath(s);
        }
        const dotIdx = s.lastIndexOf(".");
        if (dotIdx > 0) {
            const noExt = s.substring(0, dotIdx);
            if (Quickshell.hasThemeIcon(noExt)) {
                return Quickshell.iconPath(noExt);
            }
        }
        return "";
    }

    // Systemd Service Management (Strictly Opt-in by User in Settings)
    property bool systemdServiceInstalled: false
    property bool systemdServiceActive: false
    property bool systemdServiceEnabled: false
    property string systemdServiceStatusText: "Not Installed"

    function checkSystemdServiceStatus() {
        if (typeof sysServiceProc !== "undefined" && !sysServiceProc.running) {
            sysServiceProc.command = [root.daemonBin, "systemd", "status"];
            sysServiceProc.running = true;
        }
    }

    function installSystemdService() {
        if (typeof sysServiceProc !== "undefined" && !sysServiceProc.running) {
            sysServiceProc.command = [root.daemonBin, "systemd", "install"];
            sysServiceProc.running = true;
        }
    }

    function removeSystemdService() {
        if (typeof sysServiceProc !== "undefined" && !sysServiceProc.running) {
            sysServiceProc.command = [root.daemonBin, "systemd", "remove"];
            sysServiceProc.running = true;
        }
    }

    // Pinned apps management
    readonly property var pinnedApps: (root.settings.dock && root.settings.dock.pinnedApps) ? root.settings.dock.pinnedApps : []

    function isPinned(appId, desktopFile, appName) {
        if (!appId && !desktopFile && !appName) return false;
        const list = root.pinnedApps;
        const idLow = (appId || "").toLowerCase();
        const deskLow = (desktopFile || "").toLowerCase();
        const nameLow = (appName || "").toLowerCase();

        return list.some(item => {
            const pId = (item.appId || "").toLowerCase();
            const pDesk = (item.desktopFile || "").toLowerCase();
            const pName = (item.appName || "").toLowerCase();
            if (idLow && (pId === idLow || pDesk === idLow)) return true;
            if (deskLow && (pDesk === deskLow || pId === deskLow)) return true;
            if (nameLow && pName === nameLow) return true;
            return false;
        });
    }

    function pinApp(appObj) {
        if (!appObj) return;
        const appId = appObj.appId || appObj.desktopFile || appObj.appName;
        if (!appId) return;
        if (isPinned(appObj.appId, appObj.desktopFile, appObj.appName)) return;

        let newSettings = JSON.parse(JSON.stringify(root.settings));
        if (!newSettings.dock) newSettings.dock = {};
        if (!Array.isArray(newSettings.dock.pinnedApps)) newSettings.dock.pinnedApps = [];

        newSettings.dock.pinnedApps.push({
            appId: appObj.appId || appId,
            appName: appObj.appName || "App",
            iconName: appObj.iconName || "",
            materialIcon: appObj.materialIcon || "apps",
            desktopFile: appObj.desktopFile || appObj.appId || appId
        });

        root.settings = newSettings;
        root.saveSettings();
    }

    function unpinApp(appId, desktopFile, appName) {
        if (!appId && !desktopFile && !appName) return;
        let newSettings = JSON.parse(JSON.stringify(root.settings));
        if (!newSettings.dock || !Array.isArray(newSettings.dock.pinnedApps)) return;

        const idLow = (appId || "").toLowerCase();
        const deskLow = (desktopFile || "").toLowerCase();
        const nameLow = (appName || "").toLowerCase();

        newSettings.dock.pinnedApps = newSettings.dock.pinnedApps.filter(item => {
            const pId = (item.appId || "").toLowerCase();
            const pDesk = (item.desktopFile || "").toLowerCase();
            const pName = (item.appName || "").toLowerCase();

            if (idLow && (pId === idLow || pDesk === idLow)) return false;
            if (deskLow && (pDesk === deskLow || pId === deskLow)) return false;
            if (nameLow && pName === nameLow) return false;
            return true;
        });

        root.settings = newSettings;
        root.saveSettings();
    }

    function updateSettings(callback) {
        let copy = JSON.parse(JSON.stringify(root.settings));
        callback(copy);
        root.settings = copy;
        root.saveSettings();
    }

    function setDarkMode(dark) {
        updateSettings(cfg => {
            if (!cfg.theme) cfg.theme = {};
            cfg.theme.darkMode = dark;
            cfg.theme.mode = dark ? "dark" : "light";
        });
    }

    function setDynamicColors(enabled) {
        updateSettings(cfg => {
            if (!cfg.theme) cfg.theme = {};
            cfg.theme.dynamicColors = enabled;
            if (enabled && cfg.theme.mode !== "dark" && cfg.theme.mode !== "light") {
                cfg.theme.mode = "dynamic";
            }
        });
    }

    function setThemePreset(name) {
        if (!name) return;
        updateSettings(cfg => {
            if (!cfg.theme) cfg.theme = {};
            cfg.theme.preset = name.toLowerCase();
            cfg.theme.dynamicColors = false;
        });
    }

    function setThemeCornerRadius(radius) {
        if (!radius || radius < 0) return;
        updateSettings(cfg => {
            if (!cfg.theme) cfg.theme = {};
            cfg.theme.cornerRadius = radius;
        });
    }

    function setDockEnabled(enabled) {
        updateSettings(cfg => {
            if (!cfg.dock) cfg.dock = {};
            cfg.dock.enabled = enabled;
        });
    }

    function setDockExclusiveZone(enabled) {
        updateSettings(cfg => {
            if (!cfg.dock) cfg.dock = {};
            cfg.dock.exclusiveZone = enabled;
        });
    }

    function setDockMargin(margin) {
        updateSettings(cfg => {
            if (!cfg.dock) cfg.dock = {};
            cfg.dock.margin = margin;
        });
    }

    function setDockTrayEnabled(enabled) {
        updateSettings(cfg => {
            if (!cfg.dock) cfg.dock = {};
            if (!cfg.dock.tray) cfg.dock.tray = {};
            cfg.dock.tray.enabled = enabled;
        });
    }

    function setDockIconSize(size) {
        if (!size || size < 16) return;
        updateSettings(cfg => {
            if (!cfg.dock) cfg.dock = {};
            cfg.dock.iconSize = size;
        });
    }

    function setDockWidth(width) {
        if (!width || width < 30) return;
        updateSettings(cfg => {
            if (!cfg.dock) cfg.dock = {};
            cfg.dock.width = width;
        });
    }

    function setDockStatusIconSize(size) {
        if (!size || size < 16) return;
        updateSettings(cfg => {
            if (!cfg.dock) cfg.dock = {};
            cfg.dock.statusIconSize = size;
        });
    }

    function setTopBarEnabled(enabled) {
        updateSettings(cfg => {
            if (!cfg.topBar) cfg.topBar = {};
            cfg.topBar.enabled = enabled;
        });
    }

    function setTopBarHeight(height) {
        if (!height || height < 20) return;
        updateSettings(cfg => {
            if (!cfg.topBar) cfg.topBar = {};
            cfg.topBar.height = height;
        });
    }

    function setDashboardEnabled(enabled) {
        updateSettings(cfg => {
            if (!cfg.dashboard) cfg.dashboard = {};
            cfg.dashboard.enabled = enabled;
        });
    }

    function setDashboardTabEnabled(tabId, enabled) {
        updateSettings(cfg => {
            if (!cfg.dashboard) cfg.dashboard = {};
            if (!Array.isArray(cfg.dashboard.tabs)) return;
            for (let i = 0; i < cfg.dashboard.tabs.length; i++) {
                if (cfg.dashboard.tabs[i].id === tabId) {
                    cfg.dashboard.tabs[i].enabled = enabled;
                    break;
                }
            }
        });
    }

    function setMediaAvatar(path) {
        updateSettings(cfg => {
            if (!cfg.dashboard) cfg.dashboard = {};
            cfg.dashboard.mediaAvatar = path;
        });
    }

    function setStatusIconEnabled(iconId, enabled) {
        updateSettings(cfg => {
            if (!cfg.dock) cfg.dock = {};
            if (!Array.isArray(cfg.dock.statusIcons)) return;
            for (let i = 0; i < cfg.dock.statusIcons.length; i++) {
                if (cfg.dock.statusIcons[i].id === iconId) {
                    cfg.dock.statusIcons[i].enabled = enabled;
                    break;
                }
            }
        });
    }

    function setDebugMode(enabled) {
        updateSettings(cfg => {
            cfg.debugMode = enabled;
        });
    }

    // Active selected dashboard tab ("dashboard", "media", "performance", "workspaces")
    property string activeDashboardTab: (root.settings.dashboard && root.settings.dashboard.defaultTab) ? root.settings.dashboard.defaultTab : "dashboard"

    onSettingsChanged: {
        if (root.settings.dashboard && root.settings.dashboard.defaultTab) {
            root.activeDashboardTab = root.settings.dashboard.defaultTab;
        }
    }

    // Active state toggles
    property bool dashboardVisible: (typeof Quickshell !== "undefined" && Quickshell.env && Quickshell.env("ASTRAL_PLASMA_DASHBOARD_OPEN") === "1") ? true : (root.settings.dashboardVisible ?? false)
    property bool settingsVisible: (typeof Quickshell !== "undefined" && Quickshell.env && Quickshell.env("ASTRAL_PLASMA_SETTINGS_OPEN") === "1") ? true : false
    property string activeSettingsPage: (typeof Quickshell !== "undefined" && Quickshell.env && Quickshell.env("ASTRAL_PLASMA_SETTINGS_PAGE")) ? Quickshell.env("ASTRAL_PLASMA_SETTINGS_PAGE") : "wallpaper"
    property string activePopout: "" // legacy popout tracker

    // Command Launcher State
    property bool commandLauncherVisible: (typeof Quickshell !== "undefined" && Quickshell.env && Quickshell.env("ASTRAL_PLASMA_LAUNCHER_OPEN") === "1") ? true : false
    property string commandLauncherMode: (typeof Quickshell !== "undefined" && Quickshell.env && Quickshell.env("ASTRAL_PLASMA_LAUNCHER_MODE")) ? Quickshell.env("ASTRAL_PLASMA_LAUNCHER_MODE") : "apps"

    function toggleCommandLauncher(mode) {
        if (root.commandLauncherVisible) {
            root.commandLauncherVisible = false;
        } else {
            root.openCommandLauncher(mode);
        }
    }

    function openCommandLauncher(mode) {
        root.commandLauncherMode = mode || "apps";
        root.commandLauncherVisible = true;
        root.dashboardVisible = false;
        root.closeBottomPopout();
    }

    function closeCommandLauncher() {
        root.commandLauncherVisible = false;
    }

    // Fused bottom popout state
    property bool bottomPopoutVisible: false
    property string bottomPopoutMode: "power" // "default", "bluetooth", "network", "audio", "power", "clock"
    property real popoutTargetY: 0

    Timer {
        id: popoutCloseTimer
        interval: 500
        repeat: false
        onTriggered: root.bottomPopoutVisible = false
    }

    function openBottomPopout(mode, targetY) {
        popoutCloseTimer.stop();
        if (targetY !== undefined && targetY > 0) {
            popoutTargetY = targetY;
        }
        if (mode) bottomPopoutMode = mode;
        bottomPopoutVisible = true;
    }

    function keepBottomPopout() {
        popoutCloseTimer.stop();
    }

    function scheduleCloseBottomPopout() {
        popoutCloseTimer.restart();
    }

    function closeBottomPopout() {
        popoutCloseTimer.stop();
        bottomPopoutVisible = false;
    }

    signal requestOpenTraySubmenu(string indexOrTitle)
    signal requestPopTraySubmenu()

    function openTraySubmenu(indexOrTitle) {
        requestOpenTraySubmenu(indexOrTitle);
    }

    function popTraySubmenu() {
        requestPopTraySubmenu();
    }

    // Media Visualizer Style selection ("radial" vs "speaker")
    property string mediaVisualizerStyle: (root.settings && root.settings.media && root.settings.media.visualizerStyle)
        ? root.settings.media.visualizerStyle
        : "radial"

    function setMediaVisualizerStyle(style) {
        if (!root.settings) root.settings = {};
        if (!root.settings.media) root.settings.media = {};
        root.settings.media.visualizerStyle = style;
        root.mediaVisualizerStyle = style;
        root.saveSettings();
    }

    // Right border edge control (volume & brightness) state
    property bool rightEdgeControlVisible: false

    Timer {
        id: rightEdgeCloseTimer
        interval: 850
        repeat: false
        onTriggered: root.rightEdgeControlVisible = false
    }

    function openRightEdgeControl() {
        rightEdgeCloseTimer.stop();
        root.rightEdgeControlVisible = true;
    }

    function keepRightEdgeControl() {
        rightEdgeCloseTimer.stop();
    }

    function scheduleCloseRightEdgeControl() {
        rightEdgeCloseTimer.restart();
    }

    function closeRightEdgeControl() {
        rightEdgeCloseTimer.stop();
        root.rightEdgeControlVisible = false;
    }

    // Flag indicating user is currently dragging the volume slider (suppresses central OSD)
    property bool isUserDraggingVolume: false

    // Central Volume OSD state
    property bool volumeOsdVisible: false

    Timer {
        id: volumeOsdTimer
        interval: 1600
        repeat: false
        onTriggered: root.volumeOsdVisible = false
    }

    function triggerVolumeOsd() {
        if (root.isUserDraggingVolume) return;
        root.volumeOsdVisible = true;
        volumeOsdTimer.restart();
    }

    function toggleDashboard() {
        dashboardVisible = !dashboardVisible;
        if (dashboardVisible) activePopout = "";
    }

    function toggleSettings() {
        settingsVisible = !settingsVisible;
        if (settingsVisible) {
            dashboardVisible = false;
            activePopout = "";
        }
    }

    function openSettings(page) {
        if (page) activeSettingsPage = page;
        settingsVisible = true;
        dashboardVisible = false;
        activePopout = "";
    }

    function closeSettings() {
        settingsVisible = false;
    }

    function togglePopout(id) {
        if (activePopout === id) {
            activePopout = "";
        } else {
            activePopout = id;
            dashboardVisible = false;
        }
    }

    // Deep merge: user values win, keys the user file does not mention fall back
    // to the shipped defaults, so a new default key keeps working after a user
    // file exists.
    function mergeSettings(base, override) {
        if (override === null || override === undefined) return base;
        const baseIsObject = base !== null && typeof base === "object" && !Array.isArray(base);
        const overrideIsObject = typeof override === "object" && !Array.isArray(override);
        if (!baseIsObject || !overrideIsObject) return override;
        const merged = Object.assign({}, base);
        for (const key in override) {
            merged[key] = root.mergeSettings(base[key], override[key]);
        }
        return merged;
    }

    function parseSettingsFile(view) {
        try {
            const text = view.text();
            if (text && text.trim().length > 0) return JSON.parse(text);
        } catch (e) {
            console.warn("[Config] Error parsing", view.path, e);
        }
        return null;
    }

    // Shipped defaults in the checkout...
    FileView {
        id: defaultsView
        path: root.defaultConfigPath
        preload: true
        onLoaded: root.applySettings()
    }

    // ...and the user's live settings.
    FileView {
        id: userView
        path: root.userConfigPath
        preload: true
        watchChanges: true
        onLoaded: { root.userFileResolved = true; root.userFileExists = true; root.applySettings(); }
        onLoadFailed: { root.userFileResolved = true; root.userFileExists = false; root.applySettings(); }
        // `fileChanged` only announces the change; reload() re-reads it.
        onFileChanged: userView.reload()
    }

    property bool userFileResolved: false
    property bool userFileExists: false

    function applySettings() {
        // Wait for both files: merging half of them would write a partial file.
        if (!defaultsView.loaded || !root.userFileResolved) return;

        const shipped = root.parseSettingsFile(defaultsView) || {};
        const user = root.userFileExists ? (root.parseSettingsFile(userView) || {}) : {};
        root.settings = root.mergeSettings(root.mergeSettings(root.defaultSettings, shipped), user);

        if (!root.userFileExists) {
            // First run (or migration from the checkout file): seed the user
            // file, so later saves have a home and the checkout stays pristine.
            root.userFileExists = true;
            root.saveSettings();
        }
    }

    // Save settings back to disk
    Process {
        id: saveProcess
    }

    function saveSettings() {
        try {
            const jsonStr = JSON.stringify(root.settings, null, 2);
            saveProcess.command = [root.daemonBin, "config", "write", root.userConfigPath, jsonStr];
            saveProcess.running = true;
        } catch (e) {
            console.error("[Config] Failed to save settings:", e);
        }
    }

    // Systemd User Service Process
    Process {
        id: sysServiceProc
        command: [root.daemonBin, "systemd", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const res = JSON.parse(this.text.trim());
                    if (res.action === "installed") {
                        root.systemdServiceInstalled = true;
                        root.systemdServiceStatusText = "Installed";
                        root.checkSystemdServiceStatus();
                    } else if (res.action === "removed") {
                        root.systemdServiceInstalled = false;
                        root.systemdServiceActive = false;
                        root.systemdServiceEnabled = false;
                        root.systemdServiceStatusText = "Not Installed";
                    } else if (res.installed !== undefined) {
                        root.systemdServiceInstalled = res.installed;
                        root.systemdServiceActive = !!res.active;
                        root.systemdServiceEnabled = !!res.enabled;
                        root.systemdServiceStatusText = res.installed ? (res.active ? "Active & Installed" : "Installed (Inactive)") : "Not Installed";
                    }
                } catch (e) {}
            }
        }
    }

    Component.onCompleted: {
        root.checkSystemdServiceStatus();
    }
}
