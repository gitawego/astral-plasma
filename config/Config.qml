pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string configPath: Quickshell.env("HOME") + "/.config/quickshell/config/settings.json"
    readonly property string localConfigPath: Qt.resolvedUrl("./settings.json").toString().replace("file://", "")

    // Default configuration model
    property var settings: ({
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
            "preset": "caelestia-pastel",
            "blurStrength": 0.85,
            "cornerRadius": 20
        }
    })

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

    function setDockIconSize(size) {
        if (!size || size < 16) return;
        let newSettings = JSON.parse(JSON.stringify(root.settings));
        if (!newSettings.dock) newSettings.dock = {};
        newSettings.dock.iconSize = size;
        root.settings = newSettings;
        root.saveSettings();
    }

    function setDockWidth(width) {
        if (!width || width < 30) return;
        let newSettings = JSON.parse(JSON.stringify(root.settings));
        if (!newSettings.dock) newSettings.dock = {};
        newSettings.dock.width = width;
        root.settings = newSettings;
        root.saveSettings();
    }

    function setDockStatusIconSize(size) {
        if (!size || size < 16) return;
        let newSettings = JSON.parse(JSON.stringify(root.settings));
        if (!newSettings.dock) newSettings.dock = {};
        newSettings.dock.statusIconSize = size;
        root.settings = newSettings;
        root.saveSettings();
    }

    // Active selected dashboard tab ("dashboard", "media", "performance", "workspaces")
    property string activeDashboardTab: (root.settings.dashboard && root.settings.dashboard.defaultTab) ? root.settings.dashboard.defaultTab : "dashboard"

    onSettingsChanged: {
        if (root.settings.dashboard && root.settings.dashboard.defaultTab) {
            root.activeDashboardTab = root.settings.dashboard.defaultTab;
        }
    }

    // Active state toggles
    property bool dashboardVisible: false
    property bool settingsVisible: false
    property string activePopout: "" // legacy popout tracker

    // Fused bottom popout state
    property bool bottomPopoutVisible: false
    property string bottomPopoutMode: "default" // "default", "bluetooth", "network", "audio", "power", "clock"
    property real popoutTargetY: 0

    Timer {
        id: popoutCloseTimer
        interval: 450
        repeat: false
        onTriggered: root.bottomPopoutVisible = false
    }

    function openBottomPopout(mode, targetY) {
        popoutCloseTimer.stop();
        if (mode) bottomPopoutMode = mode;
        if (targetY !== undefined && targetY > 0) {
            popoutTargetY = targetY;
        }
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

    function togglePopout(id) {
        if (activePopout === id) {
            activePopout = "";
        } else {
            activePopout = id;
            dashboardVisible = false;
        }
    }

    // Load file if exists
    FileView {
        id: fileView
        path: root.localConfigPath
        preload: true

        onLoaded: {
            try {
                const textData = fileView.text();
                if (textData && textData.trim().length > 0) {
                    const parsed = JSON.parse(textData);
                    // Merge with defaults
                    root.settings = Object.assign({}, root.settings, parsed);
                }
            } catch (e) {
                console.warn("[Config] Error parsing settings.json:", e);
            }
        }
    }

    // Save settings back to disk
    Process {
        id: saveProcess
    }

    function saveSettings() {
        try {
            const jsonStr = JSON.stringify(root.settings, null, 2);
            saveProcess.command = ["python3", "-c", 
                "import sys, os\n" +
                "path = sys.argv[1]\n" +
                "os.makedirs(os.path.dirname(path), exist_ok=True)\n" +
                "with open(path, 'w') as f:\n" +
                "    f.write(sys.argv[2])\n",
                root.localConfigPath,
                jsonStr
            ];
            saveProcess.running = true;
        } catch (e) {
            console.error("[Config] Failed to save settings:", e);
        }
    }
}
