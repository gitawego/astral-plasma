//@ pragma DefaultEnv QS_NO_RELOAD_POPUP=1
//@ pragma DefaultEnv QSG_RENDER_LOOP=threaded

import QtQuick
import Quickshell
import Quickshell.Io
import "config"
import "theme"
import "shell"
import "settings_gui"
import "services"

ShellRoot {
    id: root

    // IPC Handlers for external scripting & shortcuts
    IpcHandler {
        target: "dashboard"
        function toggle(): void { Config.dashboardVisible = !Config.dashboardVisible; }
        function open(): void { Config.dashboardVisible = true; }
        function close(): void { Config.dashboardVisible = false; }
        function setTab(tab: string): void {
            Config.activeDashboardTab = tab;
            Config.dashboardVisible = true;
        }
    }

    IpcHandler {
        target: "media"
        function cyclePlayer(): void { MprisMedia.cyclePlayer(); }
        function selectPlayer(busName: string): void {
            let p = MprisMedia.findMatchingPlayer(busName);
            if (p) MprisMedia.selectPlayer(p);
        }
        function playPause(): void { MprisMedia.playPause(); }
        function next(): void { MprisMedia.next(); }
        function previous(): void { MprisMedia.previous(); }
        function setVisualizer(style: string): void { Config.setMediaVisualizerStyle(style); }
        function toggleVisualizer(): void {
            let next = (Config.mediaVisualizerStyle === "speaker" || Config.mediaVisualizerStyle === "heatmap") ? "radial" : "speaker";
            Config.setMediaVisualizerStyle(next);
        }
    }

    IpcHandler {
        target: "shell"
        // Leaving the shell: `astral-plasma shell exit` (the settings page, the
        // launcher command and the power menu) calls this. The supervisor that
        // started the shell restores the Plasma panels when the process exits.
        function quit(): void { Qt.quit(); }
    }

    IpcHandler {
        target: "settings"
        function toggle(): void { Config.settingsVisible = !Config.settingsVisible; }
        function open(page: string): void {
            if (page) Config.activeSettingsPage = page;
            Config.settingsVisible = true;
        }
        function close(): void { Config.settingsVisible = false; }
        function setPage(page: string): void {
            Config.activeSettingsPage = page;
        }
        function scroll(y: real): void {
            settingsWindow.scrollTo(y);
        }
    }

    IpcHandler {
        target: "ai"
        function refresh(): void { AiTokenService.refresh(true); }
        function switchGemini(account: string): void { AiTokenService.switchGeminiAccount(account); }
        function login(email: string): void { AiTokenService.loginGemini(email); }
        function cancel(): void { AiTokenService.cancelLogin(); }
        function selectProvider(providerId: string): void {
            if (typeof AiTokenService !== "undefined") {
                AiTokenService.lastActiveProviderId = providerId;
            }
        }
        function openPopout(y: real): void { Config.openBottomPopout("ai", (y !== undefined && y > 0) ? y : 1450); }
        function closePopout(): void { Config.closeBottomPopout(); }
        function togglePopout(): void {
            if (Config.bottomPopoutVisible && Config.bottomPopoutMode === "ai") {
                Config.closeBottomPopout();
            } else {
                Config.openBottomPopout("ai", 1450);
            }
        }
        function triggerActivity(agent: string, model: string, displayName: string, brandColor: string, rate: real, tokens: real): void {
            if (typeof AiActivityService !== "undefined") {
                AiActivityService.applyActivity({
                    agent: agent,
                    model: model,
                    display_name: displayName,
                    brand_color: brandColor,
                    brand_icon: "token",
                    is_active: true,
                    intensity: 1.0,
                    request_rate: (rate !== undefined) ? rate : 1.0,
                    token_rate: (tokens !== undefined) ? tokens : 0.0,
                    recent_tokens: (tokens !== undefined) ? tokens : 0.0
                });
            }
        }
        function triggerMultiActivity(agent1: string, model1: string, name1: string, color1: string, tokens1: real, agent2: string, model2: string, name2: string, color2: string, tokens2: real, rate: real): void {
            if (typeof AiActivityService !== "undefined") {
                AiActivityService.applyActivity({
                    agent: agent1,
                    model: model1,
                    display_name: name1,
                    brand_color: color1,
                    brand_icon: "token",
                    is_active: true,
                    intensity: 1.0,
                    request_rate: (rate !== undefined) ? rate : 2.0,
                    token_rate: (tokens1 + tokens2),
                    recent_tokens: (tokens1 + tokens2),
                    active_agents: [
                        {
                            tool_source: agent1,
                            model_id: model1,
                            display_name: name1,
                            brand_color: color1,
                            brand_icon: "auto_awesome",
                            request_rate_rpm: (rate !== undefined) ? rate / 2 : 1.0,
                            token_rate_tpm: tokens1,
                            recent_tokens: tokens1
                        },
                        {
                            tool_source: agent2,
                            model_id: model2,
                            display_name: name2,
                            brand_color: color2,
                            brand_icon: "psychology",
                            request_rate_rpm: (rate !== undefined) ? rate / 2 : 1.0,
                            token_rate_tpm: tokens2,
                            recent_tokens: tokens2
                        }
                    ]
                });
            }
        }
        function clearActivity(): void {
            if (typeof AiActivityService !== "undefined") {
                AiActivityService.applyActivity({
                    is_active: false,
                    intensity: 0.0,
                    request_rate: 0.0,
                    token_rate: 0.0,
                    recent_tokens: 0.0
                });
            }
        }

        property string activeModel: (typeof AiActivityService !== "undefined") ? AiActivityService.model : ""
        property string activeDisplayName: (typeof AiActivityService !== "undefined") ? AiActivityService.displayName : ""
        property bool isActive: (typeof AiActivityService !== "undefined") ? AiActivityService.isActive : false
        property real intensity: (typeof AiActivityService !== "undefined") ? AiActivityService.intensity : 0.0
        property real requestRate: (typeof AiActivityService !== "undefined") ? AiActivityService.requestRate : 0.0
        property real tokenRate: (typeof AiActivityService !== "undefined") ? AiActivityService.tokenRate : 0.0
        property real recentTokens: (typeof AiActivityService !== "undefined") ? AiActivityService.recentTokens : 0.0
        property real throughputLoad: (typeof AiActivityService !== "undefined") ? AiActivityService.throughputLoad : 0.0
        property int currentTravelDuration: (typeof AiActivityService !== "undefined") ? AiActivityService.currentTravelDuration : 3200
        property int pulseDuration: (typeof AiActivityService !== "undefined") ? AiActivityService.pulseDuration : 2400
        property real packetLength: (typeof AiActivityService !== "undefined") ? AiActivityService.packetLength : 48.0
        property int activeAgentsCount: (typeof AiActivityService !== "undefined" && AiActivityService.activeAgents) ? AiActivityService.activeAgents.length : 0
        property string activeAgentsSummary: {
            if (typeof AiActivityService === "undefined" || !AiActivityService.activeAgents) return "";
            return AiActivityService.activeAgents.map(function(a) { return a.display_name; }).join(", ");
        }
    }

    IpcHandler {
        target: "overview"
        function toggle(): void { Config.toggleOverview(); }
        function open(): void { Config.openOverview(); }
        function close(): void { Config.closeOverview(); }
    }

    IpcHandler {
        target: "theme"
        function setMode(mode: string): void {
            if (mode === "light") {
                Config.setDarkMode(false);
            } else if (mode === "dark") {
                Config.setDarkMode(true);
            }
        }
        function toggle(): void {
            Config.setDarkMode(!Config.isDarkMode);
        }
        function setPreset(preset: string): void {
            Config.setThemePreset(preset);
        }
    }

    IpcHandler {
        target: "popout"
        function toggle(mode: string, targetY: real): void {
            if (Config.bottomPopoutVisible) {
                Config.closeBottomPopout();
            } else {
                Config.openBottomPopout(mode || "default", targetY);
            }
        }
        function open(mode: string, targetY: real): void { Config.openBottomPopout(mode || "default", targetY); }
        function close(): void { Config.closeBottomPopout(); }
        function showTray(idOrService: string, customY: real): void {
            const trayItems = WindowService.tray || [];
            let item = null;
            for (let i = 0; i < trayItems.length; i++) {
                let t = trayItems[i];
                if (t && ((t.id && t.id.toLowerCase().indexOf(idOrService.toLowerCase()) !== -1) || (t.service && t.service.toLowerCase().indexOf(idOrService.toLowerCase()) !== -1))) {
                    item = t;
                    break;
                }
            }
            if (item) {
                WindowService.loadTrayMenu(item);
                const y = (customY !== undefined && customY > 0) ? customY : 650;
                Config.openBottomPopout("tray", y);
            }
        }
        function openTraySubmenu(indexOrTitle: string): void {
            Config.openTraySubmenu(indexOrTitle);
        }
        function popTraySubmenu(): void {
            Config.popTraySubmenu();
        }
        function previewApp(index: int, customY: real): void {
            const wins = WindowService.windows || [];
            if (wins.length > index) {
                const w = wins[index];
                const appObj = {
                    id: w.id,
                    appId: w.appId,
                    appName: w.appName,
                    iconName: w.iconName,
                    materialIcon: w.materialIcon,
                    desktopFile: w.desktopFile,
                    title: w.title,
                    isActive: w.isActive,
                    isRunning: true,
                    isPinned: false
                };
                WindowService.loadAppPreview(appObj);
                const y = (customY !== undefined && customY > 0) ? customY : 650;
                Config.openBottomPopout("app", y);
            }
        }
    }

    IpcHandler {
        target: "notification"
        function show(summary: string, body: string, icon: string, appName: string, image: string): void {
            NotificationService.show(summary, body, icon, appName, image);
        }
        function post(summary: string, body: string): void {
            NotificationService.show(summary, body, "info", "Astral", "");
        }
        function dismiss(): void {
            NotificationService.dismiss();
        }
    }

    IpcHandler {
        target: "rightedge"
        function toggle(): void {
            if (Config.rightEdgeControlVisible) {
                Config.closeRightEdgeControl();
            } else {
                Config.openRightEdgeControl();
            }
        }
        function open(): void { Config.openRightEdgeControl(); }
        function close(): void { Config.closeRightEdgeControl(); }
    }

    IpcHandler {
        target: "volumeosd"
        function trigger(): void { Config.triggerVolumeOsd(); }
    }

    IpcHandler {
        target: "app"
        function launch(target: string): void {
            WindowService.launchApp(target);
        }
    }

    IpcHandler {
        target: "power"
        function logout(): void { PowerService.requestLogout(); }
        function reboot(): void { PowerService.requestReboot(); }
        function shutdown(): void { PowerService.requestPoweroff(); }
        function confirm(): void { PowerService.confirmAction(); }
        function cancel(): void { PowerService.cancelAction(); }
    }

    IpcHandler {
        target: "launcher"
        function toggle(): void {
            if (Config.commandLauncherVisible) {
                commandLauncher.closeLauncher();
            } else {
                commandLauncher.openLauncher("apps");
            }
        }
        function open(mode: string): void { commandLauncher.openLauncher(mode); }
        function close(): void { commandLauncher.closeLauncher(); }
        function next(): void { commandLauncher.selectNext(); }
        function prev(): void { commandLauncher.selectPrevious(); }
        function pageDown(): void { commandLauncher.selectPageDown(6); }
        function pageUp(): void { commandLauncher.selectPageUp(6); }
        function select(idx: int): void { commandLauncher.selectIndex(idx); }
    }

    IpcHandler {
        target: "wallpaper"
        function set(path: string): void { WallpaperEngine.setWallpaper(path); }
        function preview(path: string): void { WallpaperEngine.preview(path); }
        function stopPreview(): void { WallpaperEngine.stopPreview(); }
        function reload(): void { WallpaperEngine.reloadWallpapers(); }
    }

    // Unified Desktop Shell (Flush Fused Left Dock + Top Bar with Corner Fillet)
    Variants {
        model: Quickshell.screens

        Scope {
            id: screenScope
            required property ShellScreen modelData

            // Dynamic & Static Background Wallpaper Layer
            WallpaperLayer {
                targetScreen: screenScope.modelData
            }

            // Dedicated 1px invisible Exclusion Zones for KWin window tiling
            ExclusionZones {
                screen: screenScope.modelData
            }

            // The Unified Shell Visual Surface
            UnifiedShell {
                targetScreen: screenScope.modelData
            }
        }
    }

    // Bottom Command Launcher & Wallpaper Carousel Modal
    CommandLauncher {
        id: commandLauncher
        targetScreen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
    }

    // Active apps overview (bare Meta key -> KWin shortcut -> daemon ShellIpc
    // -> this IPC): fullscreen overlay with live thumbnails, primary screen.
    ActiveAppsOverview {}

    // Settings GUI Window
    SettingsWindow {
        id: settingsWindow
        targetScreen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
    }

    Component.onCompleted: {
        if (Config.debugMode) {
            console.log("[shell.qml] onCompleted, disablePlasmaPanels:", Config.disablePlasmaPanels, "daemonBin:", Config.daemonBin, "pid:", Quickshell.processId);
        }
        if (Config.disablePlasmaPanels && DesktopSessionFacade.profile === "kde") {
            const target = (typeof Config.disablePlasmaPanels === "string") ? Config.disablePlasmaPanels : "all";
            Quickshell.execDetached([Config.daemonBin, "plasma", "disable", target, "" + Quickshell.processId]);
        }
    }

    Component.onDestruction: {
        if (Config.debugMode) {
            console.log("[shell.qml] onDestruction, autoRestorePlasmaOnExit:", Config.autoRestorePlasmaOnExit);
        }
        if (Config.autoRestorePlasmaOnExit && DesktopSessionFacade.profile === "kde") {
            Quickshell.execDetached([Config.daemonBin, "plasma", "restore"]);
        }
    }
}
