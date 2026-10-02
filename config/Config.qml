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
        "session": {
            "compositor": "auto",
            "environment": "auto",
            "integration": "auto",
            "restoreOnExit": true
        },
        "profiles": {
            "kde": {},
            "hyprland": {},
            "omarchyHosted": {},
            "hyprlandStandaloneExperimental": {}
        },
        "dock": {
            "enabled": true,
            "position": "left",
            "width": 64,
            "iconSize": 32,
            // 0 = fit as many app icons as the dock height allows; > 0 caps them.
            "maxVisibleApps": 0,
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
            // "" = follow the system's XDG MIME default for text/calendar.
            "calendarApp": "",
            "mediaAvatar": "",
            "hostAvatar": "",
            "hostAvatarBg": "#ffffff",
            "hostAvatarBgOpacity": 0.2,
            "bongoCatAvatar": "",
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
        "ai": {
            "enabled": true,
            "pollIntervalMinutes": 5,
            "warningThresholdPercent": 80,
            "criticalThresholdPercent": 95,
            "dockPillMode": "dynamic"
        },
        // Download manager: "" dir = ~/Downloads; split clamped 1..16.
        "downloads": {
            "dir": "",
            "split": 4,
            "borderEffect": true
        },
        "debugMode": false
    })

    property var settings: root.defaultSettings

    // Single Debug Mode toggle (gates all debug features & freeze)
    readonly property bool debugMode: root.settings.debugMode ?? false

    // Convenient getters
    readonly property bool dockEnabled: root.settings.dock ? (root.settings.dock.enabled ?? true) : true
    // 0 = auto-fit the taskbar to the available height; > 0 shows at most this
    // many app icons and scrolls the rest (see DockScrollCapsule).
    readonly property int maxVisibleApps: (root.settings.dock && root.settings.dock.maxVisibleApps !== undefined)
        ? root.settings.dock.maxVisibleApps : 0

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
    // Dashboard calendar app override ("" = system default via XDG MIME)
    readonly property string calendarApp: (root.settings.dashboard && typeof root.settings.dashboard.calendarApp === "string")
        ? root.settings.dashboard.calendarApp : ""
    readonly property string mediaAvatar: {
        if (root.settings.dashboard && root.settings.dashboard.mediaAvatar !== undefined && root.settings.dashboard.mediaAvatar !== "") {
            return root.settings.dashboard.mediaAvatar;
        }
        if (root.settings.media && root.settings.media.avatar !== undefined && root.settings.media.avatar !== "") {
            return root.settings.media.avatar;
        }
        return "";
    }
    // Dashboard system-host card avatar ("" = bundled default art). Written
    // by setHostAvatar / the load-time migration; both durably import the
    // file into the config dir before storing it.
    readonly property string hostAvatar: (root.settings.dashboard && typeof root.settings.dashboard.hostAvatar === "string")
        ? root.settings.dashboard.hostAvatar : ""
    // Circle background for the system-host avatar (default white @ 0.2).
    readonly property string hostAvatarBg: (root.settings.dashboard && typeof root.settings.dashboard.hostAvatarBg === "string" && root.settings.dashboard.hostAvatarBg !== "")
        ? root.settings.dashboard.hostAvatarBg : "#ffffff"
    readonly property real hostAvatarBgOpacity: {
        const v = root.settings.dashboard ? Number(root.settings.dashboard.hostAvatarBgOpacity) : NaN;
        return isNaN(v) ? 0.2 : Math.max(0, Math.min(1, v));
    }
    // Dashboard mascot / Bongo Cat avatar ("" = bundled default art).
    readonly property string bongoCatAvatar: (root.settings.dashboard && typeof root.settings.dashboard.bongoCatAvatar === "string")
        ? root.settings.dashboard.bongoCatAvatar : ""
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

    // Session and profile settings
    readonly property string sessionCompositor: root.settings.session?.compositor ?? "auto"
    readonly property string sessionEnvironment: root.settings.session?.environment ?? "auto"
    readonly property string sessionIntegration: root.settings.session?.integration ?? "auto"
    readonly property bool sessionRestoreOnExit: root.settings.session?.restoreOnExit ?? true
    readonly property var sessionProfiles: root.settings.profiles ?? ({})

    // AI Token Plan Configuration
    readonly property bool aiEnabled: (root.settings && root.settings.ai && root.settings.ai.enabled !== undefined) ? root.settings.ai.enabled : true
    readonly property bool modelActivityEffect: (root.settings && root.settings.ai && root.settings.ai.modelActivityEffect !== undefined) ? root.settings.ai.modelActivityEffect : true
    readonly property int aiPollIntervalMinutes: (root.settings && root.settings.ai && root.settings.ai.pollIntervalMinutes) ? root.settings.ai.pollIntervalMinutes : 5
    readonly property real aiWarningThreshold: (root.settings && root.settings.ai && root.settings.ai.warningThresholdPercent !== undefined) ? root.settings.ai.warningThresholdPercent : 80.0
    readonly property real aiCriticalThreshold: (root.settings && root.settings.ai && root.settings.ai.criticalThresholdPercent !== undefined) ? root.settings.ai.criticalThresholdPercent : 95.0
    readonly property string aiDockPillMode: (root.settings && root.settings.ai && root.settings.ai.dockPillMode) ? root.settings.ai.dockPillMode : "dynamic"
    readonly property bool aiPrivacyMode: (root.settings && root.settings.ai && root.settings.ai.privacyMode !== undefined) ? root.settings.ai.privacyMode : false
    // Download manager defaults (D6/D7): global split parts + destination.
    readonly property string downloadsDir: (root.settings && root.settings.downloads && typeof root.settings.downloads.dir === "string" && root.settings.downloads.dir.length > 0)
        ? root.settings.downloads.dir : ""
    readonly property int downloadsSplit: {
        const v = (root.settings && root.settings.downloads && root.settings.downloads.split !== undefined)
            ? Number(root.settings.downloads.split) : NaN;
        if (isNaN(v)) return 4;
        return Math.max(1, Math.min(16, Math.round(v)));
    }
    readonly property bool downloadsBorderEffect: (root.settings && root.settings.downloads && root.settings.downloads.borderEffect !== undefined)
        ? Boolean(root.settings.downloads.borderEffect) : true
    property string activeDownloadsSegment: "active"

    // Theme getters
    readonly property bool isDarkMode: root.settings.theme ? (root.settings.theme.darkMode ?? (root.settings.theme.mode !== "light")) : true
    readonly property string themeMode: root.isDarkMode ? "dark" : "light"
    readonly property bool dynamicColors: root.settings.theme ? (root.settings.theme.dynamicColors ?? (root.settings.theme.mode === "dynamic")) : false
    readonly property string themePreset: root.settings.theme ? (root.settings.theme.preset ?? "iris") : "iris"
    readonly property string themeArchetype: root.settings.theme ? (root.settings.theme.archetype ?? "liquid_glass") : "liquid_glass"
    readonly property int themeCornerRadius: root.settings.theme ? (root.settings.theme.cornerRadius ?? 20) : 20

    function setThemeArchetype(archetypeId) {
        root.updateSetting("theme", "archetype", archetypeId);
    }

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

    // Resolves provider brand icon SVG URLs from theme/assets/icons/
    function providerIconUrl(providerId) {
        if (!providerId) return "";
        const pid = String(providerId).toLowerCase().trim();
        let name = "opencode";
        if (pid === "gemini") name = "gemini";
        else if (pid.indexOf("opencode") !== -1) name = root.isDarkMode ? "opencode" : "opencode-dark";
        else if (pid.indexOf("minimax") !== -1) name = "minimax";
        else if (pid.indexOf("xiaomi") !== -1 || pid.indexOf("mimo") !== -1) name = "xiaomi";
        else if (pid.indexOf("deepseek") !== -1) name = "deepseek";
        else if (pid.indexOf("anthropic") !== -1 || pid.indexOf("claude") !== -1) name = "anthropic";
        else if (pid.indexOf("openai") !== -1) name = "openai";
        else if (pid.indexOf("ollama") !== -1) name = root.isDarkMode ? "ollama" : "ollama-dark";
        else if (pid.indexOf("antigravity") !== -1 || pid.indexOf("agy") !== -1) name = "antigravity";
        else name = pid;

        return Qt.resolvedUrl("../theme/assets/icons/" + name + ".svg").toString();
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

    /// Leave Astral Plasma and hand the desktop back to Plasma.
    ///
    /// The daemon quits the shell (and falls back to killing the instance if it
    /// is wedged); the supervisor that started the shell restores the panels.
    function exitShell() {
        if (typeof exitShellProc !== "undefined" && !exitShellProc.running) {
            exitShellProc.command = [root.daemonBin, "shell", "exit"];
            exitShellProc.running = true;
        }
    }

    function removeSystemdService() {
        if (typeof sysServiceProc !== "undefined" && !sysServiceProc.running) {
            sysServiceProc.command = [root.daemonBin, "systemd", "remove"];
            sysServiceProc.running = true;
        }
    }

    // Desktop & Session Integration Management (Strictly Opt-in by User in Settings)
    property bool desktopIntegrationInstalled: false
    property bool desktopSessionInstalled: false
    property bool desktopShortcutsInstalled: false
    property string desktopIntegrationStatusText: "Not Installed"
    property string desktopSessionFile: ""
    property string desktopShortcutsDir: ""

    function checkDesktopIntegrationStatus() {
        if (typeof desktopEntriesProc !== "undefined" && !desktopEntriesProc.running) {
            desktopEntriesProc.command = [root.daemonBin, "desktop", "status"];
            desktopEntriesProc.running = true;
        }
    }

    function installDesktopIntegration() {
        if (typeof desktopEntriesProc !== "undefined" && !desktopEntriesProc.running) {
            desktopEntriesProc.command = [root.daemonBin, "desktop", "install"];
            desktopEntriesProc.running = true;
        }
    }

    function removeDesktopIntegration() {
        if (typeof desktopEntriesProc !== "undefined" && !desktopEntriesProc.running) {
            desktopEntriesProc.command = [root.daemonBin, "desktop", "remove"];
            desktopEntriesProc.running = true;
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

    function setAiEnabled(enabled) {
        updateSettings(cfg => {
            if (!cfg.ai) cfg.ai = {};
            cfg.ai.enabled = enabled;
        });
    }

    function setAiDockPillMode(mode) {
        updateSettings(cfg => {
            if (!cfg.ai) cfg.ai = {};
            cfg.ai.dockPillMode = mode;
        });
    }

    function setAiThresholds(warnThr, critThr) {
        updateSettings(cfg => {
            if (!cfg.ai) cfg.ai = {};
            cfg.ai.warningThresholdPercent = warnThr;
            cfg.ai.criticalThresholdPercent = critThr;
        });
    }

    function setAiPollInterval(minutes) {
        updateSettings(cfg => {
            if (!cfg.ai) cfg.ai = {};
            cfg.ai.pollIntervalMinutes = minutes;
        });
    }

    function setAiGeminiMonthlyEnabled(enabled) {
        updateSettings(cfg => {
            if (!cfg.ai) cfg.ai = {};
            cfg.ai.geminiMonthlyEnabled = enabled;
        });
    }

    function setAiGeminiMonthlyRemainingPercent(percent) {
        updateSettings(cfg => {
            if (!cfg.ai) cfg.ai = {};
            cfg.ai.geminiMonthlyRemainingPercent = percent;
        });
    }

    function setAiGeminiMonthlyResetDay(day) {
        updateSettings(cfg => {
            if (!cfg.ai) cfg.ai = {};
            cfg.ai.geminiMonthlyResetDay = day;
        });
    }

    function setAiPrivacyMode(enabled) {
        updateSettings(cfg => {
            if (!cfg.ai) cfg.ai = {};
            cfg.ai.privacyMode = enabled;
        });
    }

    // Download manager defaults (persisted to the user settings file).
    function setDownloadsDir(dir) {
        updateSettings(cfg => {
            if (!cfg.downloads) cfg.downloads = {};
            cfg.downloads.dir = dir || "";
        });
    }

    function setDownloadsSplit(split) {
        const v = Math.max(1, Math.min(16, Math.round(Number(split) || 4)));
        updateSettings(cfg => {
            if (!cfg.downloads) cfg.downloads = {};
            cfg.downloads.split = v;
        });
    }

    function setDownloadsBorderEffect(enabled) {
        updateSettings(cfg => {
            if (!cfg.downloads) cfg.downloads = {};
            cfg.downloads.borderEffect = Boolean(enabled);
        });
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

    function setMaxVisibleApps(count) {
        updateSettings(cfg => {
            if (!cfg.dock) cfg.dock = {};
            cfg.dock.maxVisibleApps = Math.max(0, Math.round(count));
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

    // ------------------------------------------------------------------
    // Durable avatar image import (system-host card + media tab avatars)
    // ------------------------------------------------------------------
    // The file operations live in the daemon (`config import-image` /
    // `config forget-image`) so they carry full unit-test coverage; Config.qml
    // only wires them into the settings store.

    /// [{ key, kind }] of dashboard settings holding a durable-imported image.
    readonly property var dashboardAvatarFields: [
        { "key": "mediaAvatar", "kind": "media" },
        { "key": "hostAvatar", "kind": "host" },
        { "key": "bongoCatAvatar", "kind": "mascot" }
    ]

    /// Guards the one-time load-time migration (applySettings can re-run).
    property bool avatarMigrationRan: false

    /// One-shot daemon call for avatar import/forget. Each call spawns its own
    /// process, so the load-time migration and UI setters can never queue
    /// behind each other. `doneCb` receives the daemon's `stored` path, or
    /// `fallbackValue` when the process produced no parseable output (e.g.
    /// binary missing) - settings then keep the original path, exactly the
    /// pre-import behaviour.
    Component {
        id: avatarProcComponent
        Process {
            id: avatarProc
            property var doneCb: null
            property string fallbackValue: ""
            stdout: StdioCollector { id: avatarProcStdout }
            onExited: (exitCode, exitStatus) => {
                let stored = "";
                try {
                    const parsed = JSON.parse(avatarProcStdout.text.trim());
                    if (parsed && typeof parsed.stored === "string") stored = parsed.stored;
                } catch (e) {}
                const cb = avatarProc.doneCb;
                if (cb) cb(stored !== "" ? stored : avatarProc.fallbackValue);
                avatarProc.destroy();
            }
        }
    }

    function runAvatarProcess(command, fallbackValue, doneCb) {
        const proc = avatarProcComponent.createObject(root, {
            "doneCb": doneCb || null,
            "fallbackValue": fallbackValue || ""
        });
        if (!proc) {
            if (doneCb) doneCb(fallbackValue || "");
            return;
        }
        proc.command = command;
        proc.running = true;
    }

    /// Ask the daemon to durably import `srcPath` and report the path to
    /// store. `done` always receives a readable path: the config-dir copy on
    /// success, the original source when it could not be copied.
    function importAvatarToConfig(srcPath, kind, done) {
        root.runAvatarProcess([root.daemonBin, "config", "import-image", srcPath, kind], srcPath, done);
    }

    /// Persist a dashboard avatar durably. Empty `pathValue` resets to the
    /// bundled default and asks the daemon to drop our owned copy (the daemon
    /// re-verifies ownership - user originals are never touched).
    function setDashboardAvatar(key, kind, pathValue) {
        const p = (pathValue || "").trim();
        const current = (root.settings.dashboard && root.settings.dashboard[key])
            ? root.settings.dashboard[key]
            : "";
        if (p === "") {
            root.updateSettings(cfg => {
                if (!cfg.dashboard) cfg.dashboard = {};
                cfg.dashboard[key] = "";
            });
            const previous = String(current).trim();
            if (previous !== "") {
                root.runAvatarProcess([root.daemonBin, "config", "forget-image", previous], "", null);
            }
            return;
        }
        root.importAvatarToConfig(p, kind, stored => {
            let previous = "";
            root.updateSettings(cfg => {
                if (!cfg.dashboard) cfg.dashboard = {};
                previous = String(cfg.dashboard[key] || "").trim();
                cfg.dashboard[key] = stored;
            });
            // After a *successful* import, drop a stale owned copy (e.g. the
            // old extension). Guarded three ways: a previous value exists,
            // it differs from the new durable copy, and the import really
            // produced a new copy (`stored !== pNorm` - a failed copy falls
            // back to the normalized source and must never trigger deletion).
            const pNorm = p.replace(/^file:\/\//, "");
            if (previous !== "" && previous !== stored && stored !== pNorm) {
                root.runAvatarProcess([root.daemonBin, "config", "forget-image", previous], "", null);
            }
        });
    }

    /// Media tab avatar (Settings > Dashboard & Widgets).
    function setMediaAvatar(pathValue) {
        root.setDashboardAvatar("mediaAvatar", "media", pathValue);
    }

    /// Dashboard system-host card avatar (Settings > Dashboard & Widgets).
    function setHostAvatar(pathValue) {
        root.setDashboardAvatar("hostAvatar", "host", pathValue);
    }

    /// Dashboard mascot / Bongo Cat avatar (Settings > Dashboard & Widgets).
    function setBongoCatAvatar(pathValue) {
        root.setDashboardAvatar("bongoCatAvatar", "mascot", pathValue);
    }

    /// Circle background color (#rrggbb) for the system-host avatar.
    /// Garbage input is ignored (keeps the current color).
    function setHostAvatarBgColor(colorHex) {
        const digits = String(colorHex || "").trim().toLowerCase().replace(/^#/, "");
        if (!/^[0-9a-f]{6}$/.test(digits)) return;
        root.updateSettings(cfg => {
            if (!cfg.dashboard) cfg.dashboard = {};
            cfg.dashboard.hostAvatarBg = "#" + digits;
        });
    }

    /// Circle background transparency (0..1, clamped).
    function setHostAvatarBgOpacity(opacityValue) {
        const v = Number(opacityValue);
        if (isNaN(v)) return;
        root.updateSettings(cfg => {
            if (!cfg.dashboard) cfg.dashboard = {};
            cfg.dashboard.hostAvatarBgOpacity = Math.max(0, Math.min(1, v));
        });
    }

    /// One-time load-time migration: any avatar still pointing *outside* the
    /// config dir (e.g. ~/Downloads) is imported into it and the stored value
    /// rewritten to the durable copy, so the image survives deletion of the
    /// original. The daemon import is idempotent (in-dir paths come back
    /// unchanged); a failed copy keeps the original path and retries on the
    /// next start.
    function migrateAvatarPaths() {
        if (root.avatarMigrationRan) return;
        root.avatarMigrationRan = true;
        if (!root.settings.dashboard) return;
        for (const entry of root.dashboardAvatarFields) {
            const current = String(root.settings.dashboard[entry.key] || "").trim();
            if (current === "") continue;
            root.importAvatarToConfig(current, entry.kind, stored => {
                if (stored === current) return;
                root.updateSettings(cfg => {
                    if (!cfg.dashboard) cfg.dashboard = {};
                    if (String(cfg.dashboard[entry.key] || "").trim() === current) {
                        cfg.dashboard[entry.key] = stored;
                    }
                });
            });
        }
    }

    /// Pick the calendar app for dashboard date clicks.
    /// Blank means "system default" (the XDG text/calendar handler).
    function setCalendarApp(desktopId) {
        updateSettings(cfg => {
            if (!cfg.dashboard) cfg.dashboard = {};
            cfg.dashboard.calendarApp = (desktopId || "").trim();
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

    // Active selected dashboard tab ("dashboard", "media", "performance", "workspaces", "downloads", "ai")
    property string activeDashboardTab: (root.settings && root.settings.dashboard && root.settings.dashboard.defaultTab) ? root.settings.dashboard.defaultTab : "dashboard"
    property string perfSelectedDevice: "cpu"

    // Active state toggles
    // Transient, like every other overlay: it opens because the user opened it
    // (or because a test asked), never because a previous session left a `true`
    // in settings.json - which is exactly how the top drawer appeared on every
    // reload.
    property bool dashboardVisible: (typeof Quickshell !== "undefined" && Quickshell.env && Quickshell.env("ASTRAL_PLASMA_DASHBOARD_OPEN") === "1") ? true : false
    property bool settingsVisible: (typeof Quickshell !== "undefined" && Quickshell.env && Quickshell.env("ASTRAL_PLASMA_SETTINGS_OPEN") === "1") ? true : false
    property string activeSettingsPage: (typeof Quickshell !== "undefined" && Quickshell.env && Quickshell.env("ASTRAL_PLASMA_SETTINGS_PAGE")) ? Quickshell.env("ASTRAL_PLASMA_SETTINGS_PAGE") : "wallpaper"
    property string activePopout: "" // legacy popout tracker

    // Assistant State
    property bool assistantVisible: (typeof Quickshell !== "undefined" && Quickshell.env && Quickshell.env("ASTRAL_PLASMA_ASSISTANT_OPEN") === "1") ? true : false
    property bool assistantMinimized: false
    readonly property string assistantHarness: (root.settings && root.settings.assistant && root.settings.assistant.harness) ? root.settings.assistant.harness : "pi"
    readonly property string assistantDefaultProvider: (root.settings && root.settings.assistant && root.settings.assistant.defaultProvider) ? root.settings.assistant.defaultProvider : ""
    readonly property string assistantDefaultModel: (root.settings && root.settings.assistant && root.settings.assistant.defaultModel) ? root.settings.assistant.defaultModel : ""
    readonly property bool assistantAutoProactiveCrash: (root.settings && root.settings.assistant && root.settings.assistant.autoProactiveCrash !== undefined) ? root.settings.assistant.autoProactiveCrash : true

    function toggleAssistant() {
        if (root.assistantMinimized) {
            root.restoreAssistant();
        } else if (root.assistantVisible) {
            root.minimizeAssistant();
        } else {
            root.openAssistant();
        }
    }

    function openAssistant() {
        root.assistantVisible = true;
        root.assistantMinimized = false;
        root.dashboardVisible = false;
        root.settingsVisible = false;
        root.commandLauncherVisible = false;
        root.closeBottomPopout();
    }

    function minimizeAssistant() {
        root.assistantMinimized = true;
        root.assistantVisible = false;
    }

    function restoreAssistant() {
        root.assistantMinimized = false;
        root.assistantVisible = true;
        root.dashboardVisible = false;
        root.settingsVisible = false;
        root.commandLauncherVisible = false;
        root.closeBottomPopout();
    }

    function closeAssistant() {
        root.assistantVisible = false;
        root.assistantMinimized = false;
    }

    // Command Launcher State
    property bool commandLauncherVisible: (typeof Quickshell !== "undefined" && Quickshell.env && Quickshell.env("ASTRAL_PLASMA_LAUNCHER_OPEN") === "1") ? true : false
    property string commandLauncherMode: (typeof Quickshell !== "undefined" && Quickshell.env && Quickshell.env("ASTRAL_PLASMA_LAUNCHER_MODE")) ? Quickshell.env("ASTRAL_PLASMA_LAUNCHER_MODE") : "apps"
    property string commandLauncherInitialQuery: ""

    function toggleCommandLauncher(mode) {
        if (root.commandLauncherVisible) {
            root.commandLauncherVisible = false;
        } else {
            root.openCommandLauncher(mode);
        }
    }

    function openCommandLauncher(mode, query) {
        root.commandLauncherMode = mode || "apps";
        root.commandLauncherInitialQuery = query || "";
        root.commandLauncherVisible = true;
        root.overviewVisible = false;
        root.dashboardVisible = false;
        root.assistantVisible = false;
        root.closeBottomPopout();
    }

    function closeCommandLauncher() {
        root.commandLauncherVisible = false;
    }

    // Active-apps overview (bare Meta key -> IPC -> here). Transient by
    // design: never persisted, so the shell can never start with the overview
    // stuck open. Opening closes the other capture-driving overlays, exactly
    // like the launcher does, so a single surface ever drives captures.
    property bool overviewVisible: false

    function toggleOverview() {
        if (root.overviewVisible) {
            root.closeOverview();
        } else {
            root.openOverview();
        }
    }

    function openOverview() {
        root.overviewVisible = true;
        root.dashboardVisible = false;
        // One modal at a time - openCommandLauncher does the same.
        root.commandLauncherVisible = false;
        root.closeBottomPopout();
    }

    function closeOverview() {
        root.overviewVisible = false;
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

    // -----------------------------------------------------------------------
    // Display refresh rate
    //
    // The shell budgets its own motion at 30 fps (`Theme.decorativeMaxFps`), so a
    // 240 Hz panel buys its surfaces nothing while multiplying the per-frame work
    // of every other client - and of the compositor, which blends and blurs the
    // shell's glass on every one of those frames (docs/LESSONS.md 33). So the
    // shipped default is 60 Hz, and `max` leaves the outputs exactly as the
    // session configured them.
    //
    // The daemon owns the switch: it picks the highest refresh at the *current
    // resolution* that does not exceed the choice, records what the session was
    // running, and puts it back when the shell exits.
    readonly property var displayRefreshOptions: ["60", "120", "144", "165", "max"]
    readonly property string defaultDisplayRefreshRate: "60"

    property string displayRefreshRate: (root.settings && root.settings.display
            && root.settings.display.refreshRate !== undefined)
        ? ("" + root.settings.display.refreshRate)
        : root.defaultDisplayRefreshRate

    function displayRefreshLabel(rate) {
        return ("" + rate === "max") ? "Max" : ("" + rate + " Hz");
    }

    function setDisplayRefreshRate(rate) {
        const value = "" + rate;
        if (!root.settings) root.settings = {};
        if (!root.settings.display) root.settings.display = {};
        root.settings.display.refreshRate = value;
        root.displayRefreshRate = value;
        root.saveSettings();
    }

    // -----------------------------------------------------------------------
    // Voice input
    //
    // Every getter tolerates an absent `voice` block, so a settings.json written
    // before this feature existed keeps working. See docs/VOICE-INPUT-SPEC.md
    // section 4.6 for the authoritative key list and clamps; the daemon applies
    // the same clamps, so a hand-edited out-of-range value is corrected there
    // too rather than being trusted.
    // -----------------------------------------------------------------------

    readonly property var voiceSettings: (root.settings && root.settings.voice) ? root.settings.voice : ({})
    readonly property bool voiceEnabled: root.voiceSettings.enabled !== undefined
        ? !!root.voiceSettings.enabled : true
    readonly property string voiceEngine: (root.voiceSettings.engine) ? root.voiceSettings.engine : "whisper-cpp"
    readonly property string voiceModel: (root.voiceSettings.model) ? root.voiceSettings.model : "ggml-small"
    /**
     * The transcription language. Empty means "follow the system locale", which
     * is the shipped default: an absent key is a user who has not chosen, and
     * resolving that to auto-detect is what handed the output alphabet to
     * whisper's ungated language argmax. "auto" remains available in the
     * picker for people who switch languages while dictating.
     */
    readonly property string voiceLanguage: (root.voiceSettings.language) ? root.voiceSettings.language : ""
    readonly property int voiceMaxUtteranceSeconds: (root.voiceSettings.maxUtteranceSeconds !== undefined)
        ? root.voiceSettings.maxUtteranceSeconds : 30
    readonly property int voiceSilenceHangoverMs: (root.voiceSettings.silenceHangoverMs !== undefined)
        ? root.voiceSettings.silenceHangoverMs : 1200
    readonly property bool voiceAutoFinalize: (root.voiceSettings.autoFinalize !== undefined)
        ? !!root.voiceSettings.autoFinalize : true
    readonly property bool voiceInstallModelOnDemand: (root.voiceSettings.installModelOnDemand !== undefined)
        ? !!root.voiceSettings.installModelOnDemand : true
    readonly property bool voiceEchoCancel: (root.voiceSettings.echoCancel !== undefined)
        ? !!root.voiceSettings.echoCancel : false
    readonly property bool voiceNoiseSuppress: (root.voiceSettings.noiseSuppress !== undefined)
        ? !!root.voiceSettings.noiseSuppress : false

    function _ensureVoiceBlock() {
        if (!root.settings) root.settings = {};
        if (!root.settings.voice) root.settings.voice = {};
        return root.settings.voice;
    }

    function setVoiceEnabled(enabled) {
        const block = root._ensureVoiceBlock();
        block.enabled = !!enabled;
        root.voiceSettings = block;
        root.saveSettings();
    }

    function setVoiceModel(modelId) {
        const block = root._ensureVoiceBlock();
        block.model = modelId;
        root.voiceSettings = block;
        root.saveSettings();
    }

    function setVoiceLanguage(language) {
        const block = root._ensureVoiceBlock();
        block.language = language;
        root.voiceSettings = block;
        root.saveSettings();
    }

    function setVoiceMaxUtteranceSeconds(seconds) {
        const block = root._ensureVoiceBlock();
        block.maxUtteranceSeconds = seconds;
        root.voiceSettings = block;
        root.saveSettings();
    }

    function setVoiceSilenceHangoverMs(ms) {
        const block = root._ensureVoiceBlock();
        block.silenceHangoverMs = ms;
        root.voiceSettings = block;
        root.saveSettings();
    }

    function setVoiceAutoFinalize(enabled) {
        const block = root._ensureVoiceBlock();
        block.autoFinalize = !!enabled;
        root.voiceSettings = block;
        root.saveSettings();
    }

    function setVoiceInstallModelOnDemand(enabled) {
        const block = root._ensureVoiceBlock();
        block.installModelOnDemand = !!enabled;
        root.voiceSettings = block;
        root.saveSettings();
    }

    function setVoiceEchoCancel(enabled) {
        const block = root._ensureVoiceBlock();
        block.echoCancel = !!enabled;
        root.voiceSettings = block;
        root.saveSettings();
    }

    function setVoiceNoiseSuppress(enabled) {
        const block = root._ensureVoiceBlock();
        block.noiseSuppress = !!enabled;
        root.voiceSettings = block;
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

    // Deep links ("Settings > AI > Voice input") name a *section*, not just a
    // page: the hub scrolls to it once the page exposes `sectionY(name)`.
    property string settingsSection: ""

    function openSettings(page, section) {
        if (page) activeSettingsPage = page;
        settingsSection = section || "";
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

        // One-time: durably import any avatar path that still lives outside
        // the config dir (idempotent; see migrateAvatarPaths).
        root.migrateAvatarPaths();
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
        id: exitShellProc
    }

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

    Process {
        id: desktopEntriesProc
        command: [root.daemonBin, "desktop", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const res = JSON.parse(this.text.trim());
                    if (res.action === "installed") {
                        root.desktopIntegrationInstalled = true;
                        root.desktopSessionInstalled = true;
                        root.desktopShortcutsInstalled = true;
                        root.desktopIntegrationStatusText = "Installed";
                        root.checkDesktopIntegrationStatus();
                    } else if (res.action === "removed") {
                        root.desktopIntegrationInstalled = false;
                        root.desktopSessionInstalled = false;
                        root.desktopShortcutsInstalled = false;
                        root.desktopIntegrationStatusText = "Not Installed";
                    } else if (res.installed !== undefined) {
                        root.desktopIntegrationInstalled = !!res.installed;
                        root.desktopSessionInstalled = !!res.session_installed;
                        root.desktopShortcutsInstalled = !!res.shortcuts_installed;
                        if (res.session_file) root.desktopSessionFile = res.session_file;
                        if (res.shortcuts_dir) root.desktopShortcutsDir = res.shortcuts_dir;
                        root.desktopIntegrationStatusText = res.installed
                            ? "Installed"
                            : (res.session_installed || res.shortcuts_installed ? "Partially Installed" : "Not Installed");
                    }
                } catch (e) {}
            }
        }
    }

    Component.onCompleted: {
        root.checkSystemdServiceStatus();
        root.checkDesktopIntegrationStatus();
    }
}
