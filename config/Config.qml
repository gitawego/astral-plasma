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

    // AI Token Plan Configuration
    readonly property bool aiEnabled: (root.settings && root.settings.ai && root.settings.ai.enabled !== undefined) ? root.settings.ai.enabled : true
    readonly property bool modelActivityEffect: (root.settings && root.settings.ai && root.settings.ai.modelActivityEffect !== undefined) ? root.settings.ai.modelActivityEffect : true
    readonly property int aiPollIntervalMinutes: (root.settings && root.settings.ai && root.settings.ai.pollIntervalMinutes) ? root.settings.ai.pollIntervalMinutes : 5
    readonly property real aiWarningThreshold: (root.settings && root.settings.ai && root.settings.ai.warningThresholdPercent !== undefined) ? root.settings.ai.warningThresholdPercent : 80.0
    readonly property real aiCriticalThreshold: (root.settings && root.settings.ai && root.settings.ai.criticalThresholdPercent !== undefined) ? root.settings.ai.criticalThresholdPercent : 95.0
    readonly property string aiDockPillMode: (root.settings && root.settings.ai && root.settings.ai.dockPillMode) ? root.settings.ai.dockPillMode : "dynamic"
    readonly property bool aiGeminiMonthlyEnabled: (root.settings && root.settings.ai && root.settings.ai.geminiMonthlyEnabled !== undefined) ? root.settings.ai.geminiMonthlyEnabled : true
    readonly property real aiGeminiMonthlyRemainingPercent: (root.settings && root.settings.ai && root.settings.ai.geminiMonthlyRemainingPercent !== undefined) ? root.settings.ai.geminiMonthlyRemainingPercent : 85.0
    readonly property int aiGeminiMonthlyResetDay: (root.settings && root.settings.ai && root.settings.ai.geminiMonthlyResetDay !== undefined) ? root.settings.ai.geminiMonthlyResetDay : 1

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
        { "key": "hostAvatar", "kind": "host" }
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

    Component.onCompleted: {
        root.checkSystemdServiceStatus();
    }
}
