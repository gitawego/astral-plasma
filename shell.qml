//@ pragma DefaultEnv QS_NO_RELOAD_POPUP=1
//@ pragma DefaultEnv QSG_RENDER_LOOP=threaded
//@ pragma UseWebEngine

import QtQuick
import Quickshell
import Quickshell.Io
import "./modules/Astral/Kernel/config"
import "./modules/Astral/Kernel/theme"
import "./shell"
import Astral.Kernel.Host 1.0
import "./modules/Astral/Apps/Workspaces"
import "./modules/Astral/Apps/Media"
import "./modules/Astral/Apps/Performance"
import "./modules/Astral/Apps/Ai"
import "./modules/Astral/Apps/Downloads"
import "./modules/Astral/Apps/Assistant"
import "./modules/Astral/Apps/Launcher"
import "./settings_gui"
import "./modules/Astral/Kernel/services"

ShellRoot {
    id: root

    // The app platform is declared before the surfaces that use it: a pane asks the
    // host for an app during its own creation, so the host and its plan must already
    // exist (that ordering bug is in spec C.10).
    // ---- app platform wiring -------------------------------------------------
    // The shell owns its state, its window model, and its actions; a surface gets
    // them injected. An imported singleton would be a copy (spec C.9/C.10).
    ShellState {
        id: shellState
        overviewVisible: Config.overviewVisible
        commandLauncherVisible: Config.commandLauncherVisible
        commandLauncherMode: Config.commandLauncherMode
        commandLauncherInitialQuery: Config.commandLauncherInitialQuery
        themePreset: Config.themePreset
        aiTerminal: Config.aiTerminal
        aiDefaultAgent: Config.aiDefaultAgent
        dashboardVisible: Config.dashboardVisible
        dashboardWidth: Config.dashboardWidth
        // Only the tabs an enabled app provides: disabling an app removes its tab from the
        // strip instead of leaving a pane that apologises (spec C.35).
        //
        // `AppStates.integrations` is read first on purpose: a call into a singleton creates
        // no QML dependency, so binding straight to the function would evaluate once (when the
        // map was still empty) and never again — the strip vanished instead of updating.
        dashboardTabs: {
            // Read the map first: see the note above about function calls and dependencies.
            const map = AppStates.integrations;
            return AppStates.providedOnly("dashboardTab", Config.dashboardTabs);
        }
        perfSelectedDevice: Config.perfSelectedDevice
        activeDashboardTab: Config.activeDashboardTab
        hostAvatar: Config.hostAvatar
        hostAvatarBg: Config.hostAvatarBg
        hostAvatarBgOpacity: Config.hostAvatarBgOpacity
        hostAvatarBorder: Config.hostAvatarBorder
        bongoCatAvatar: Config.bongoCatAvatar
        daemonBin: Config.daemonBin
        iconResolver: function (name) { return Config.iconUrl(name); }
        mediaAvatar: Config.mediaAvatar
        mediaVisualizerStyle: Config.mediaVisualizerStyle
        downloadsSegment: Config.activeDownloadsSegment
        downloadsDir: Config.downloadsDir
        downloadsSplit: Config.downloadsSplit
        downloadsMaxConcurrent: Config.downloadsMaxConcurrent
        downloadsSpeedLimit: Config.downloadsSpeedLimit
        downloadsBorderEffect: Config.downloadsBorderEffect
        aiPrivacyMode: Config.aiPrivacyMode
        assistantVisible: Config.assistantVisible
        assistantSessionsVisible: Config.assistantSessionsVisible
        providerIconResolver: function (name) { return Config.providerIconUrl(name); }
    }

    SessionPort {
        id: sessionPort
        windows: WindowService.windows
        installedApps: WindowService.installedApps
        overviewThumbnails: WindowService.overviewThumbnails
        activeWindowId: WindowService.activeId
        activateWindowImpl: function (id) { WindowService.activateWindow(id); return true; }
        closeWindowImpl: function (id) { WindowService.closeWindow(id); return true; }
        launchAppImpl: function (target, meta) { WindowService.launchApp(target, meta); return true; }
        reloadInstalledAppsImpl: function () { WindowService.reloadInstalledApps(); return true; }
        startThumbnailsImpl: function () { WindowService.startOverviewThumbnails(); return true; }
        stopThumbnailsImpl: function () { WindowService.stopOverviewThumbnails(); return true; }
        refreshThumbnailsImpl: function () { WindowService.refreshOverviewThumbnails(); return true; }
        openCalendarImpl: function (isoDate) { WindowService.openCalendar(isoDate); return true; }
    }

    // The now-playing model a media surface may read: filled from the shell's own
    // MprisMedia, because a Loader-loaded surface would get a stale duplicate.
    MediaPort {
        id: mediaPort
        hasMedia: MprisMedia.hasMedia
        title: MprisMedia.title
        artist: MprisMedia.artist
        album: MprisMedia.album
        artUrl: MprisMedia.artUrl
        status: MprisMedia.isAnyPlayerPlaying ? "playing" : (MprisMedia.hasMedia ? "paused" : "stopped")
        playerName: MprisMedia.identity
        position: MprisMedia.position
        length: MprisMedia.length
        // Sampled from the visualiser singleton here, at the shell boundary: the values
        // cross to apps as plain properties instead of as an import they cannot make.
        audioActive: AudioVisualizer.active
        audioEnergy: AudioVisualizer.displayEnergy
        audioBass: AudioVisualizer.displayBass
        audioMid: AudioVisualizer.displayMid
        audioTreble: AudioVisualizer.displayTreble
        audioBeat: AudioVisualizer.displayBeat
        audioBands: AudioVisualizer.displayBands
        loopState: MprisMedia.loopState || "enabled"
        shuffle: Boolean(MprisMedia.shuffle)
        canGoNext: Boolean(MprisMedia.canGoNext)
        canGoPrevious: Boolean(MprisMedia.canGoPrevious)
        players: (MprisMedia.players || []).map(function (player) {
            return {
                id: player.busName || "",
                name: MprisMedia.playerIdentity(player)
            };
        })
        activePlayerId: MprisMedia.activePlayer ? (MprisMedia.activePlayer.busName || "") : ""
        toggleImpl: function () {
            MprisMedia.togglePlay();
            return true;
        }
        nextImpl: function () {
            MprisMedia.next();
            return true;
        }
        previousImpl: function () {
            MprisMedia.previous();
            return true;
        }
        seekImpl: function (fraction) {
            MprisMedia.seekTo(fraction);
            return true;
        }
        cyclePlayerImpl: function () {
            MprisMedia.cyclePlayer();
            return true;
        }
        cycleLoopImpl: function () {
            MprisMedia.cycleLoop();
            return true;
        }
        toggleShuffleImpl: function () {
            MprisMedia.toggleShuffle();
            return true;
        }
        selectPlayerImpl: function (id) {
            const list = MprisMedia.players || [];
            for (let index = 0; index < list.length; index++) {
                if ((list[index].busName || "") === id) {
                    MprisMedia.selectPlayer(list[index]);
                    return true;
                }
            }
            return false;
        }
    }

    // Desktops, for surfaces that group windows by workspace. Filled from the shell's
    // own KWinWorkspaces: a Loader-loaded surface would get its own copy (C.10).
    WorkspacesPort {
        id: workspacesPort
        desktops: KWinWorkspaces.desktops
        currentId: KWinWorkspaces.currentId
        switchToImpl: function (id) {
            KWinWorkspaces.switchTo(id);
            return true;
        }
        createImpl: function (name) {
            KWinWorkspaces.createDesktop(name);
            return true;
        }
        removeImpl: function (id) {
            KWinWorkspaces.removeDesktop(id);
            return true;
        }
        refreshImpl: function () {
            KWinWorkspaces.refresh();
            return true;
        }
        moveWindowImpl: function (windowId, desktopId) {
            KWinWorkspaces.moveWindow(windowId, desktopId);
            return true;
        }
    }

    IntentBus {
        id: intents
    }

    // The overview is a shell surface, not a migrated app: the theme cannot cross the
    // app boundary yet (spec C.17), and an untitled surface is worse than an unmigrated one.
    ActiveAppsOverview {
        id: overviewSurface
    }

    AppRegistry {
        id: bundledApps
        bundledRoot: Qt.resolvedUrl("modules/Astral/Apps/").toString().replace(/^file:\/\//, "")
        // The daemon's records: a bundled app can be disabled or pinned.
        statePath: Paths.appsRegistryPath
    }

    Connections {
        target: bundledApps
        // The registry is the truth for every surface, including the ones that are the
        // shell's own (the dock's AI pill, an app-owned drawer).
        function onRecordsChanged() {
            AppStates.adopt(bundledApps.entries);

            // One boolean for a singleton: the app is on *and* it declares this dock location.
        AiTokenService.appEnabled = bundledApps.isEnabled("org.astralplasma.ai")
            && AppStates.integrationEnabled("dockItem", "ai");
        }
    }

    AppHost {
        id: featureHost
        entries: bundledApps.entries
        state: shellState
        intents: intents
        session: sessionPort
        media: mediaPort
        workspaces: workspacesPort
        metrics: SystemService
        ai: AiTokenService
        downloads: DownloadService
        // Shell-declared components share the shell's kernel registration, which is what
        // makes a migrated app themed (spec C.18).
        components: ({
            "org.astralplasma.workspaces": workspacesApp,
            "org.astralplasma.media": mediaApp,
            "org.astralplasma.performance": performanceApp,
            "org.astralplasma.ai": aiApp,
            "org.astralplasma.downloads": downloadsApp
        })
        eager: []
        host: ({ level: 1, floor: 1 })
        onAppFailed: function (id, reason) { console.error("app failed: " + id + " - " + reason) }
    }


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
        function setPerfDevice(dev: string): void {
            Config.perfSelectedDevice = dev;
            Config.activeDashboardTab = "performance";
            Config.dashboardVisible = true;
        }
        function setDownloadsSegment(seg: string): void {
            Config.activeDashboardTab = "downloads";
            Config.activeDownloadsSegment = seg;
            Config.dashboardVisible = true;
        }
    }

    IpcHandler {
        target: "media"
        // The same call the visualiser-style button makes, so a script (or a verification
        // run) can exercise the exact path without a pointer.
        function setVisualizerStyle(style: string): void {
            if (style !== "radial" && style !== "speaker") {
                console.log("media.setVisualizerStyle: style must be radial or speaker");
                return;
            }
            Config.setMediaVisualizerStyle(style);
        }
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
            Config.openSettings(page);
        }
        // A deep link may name a section too ("Settings > AI > Voice input").
        function openSection(page: string, section: string): void {
            Config.openSettings(page, section);
        }
        function close(): void { Config.settingsVisible = false; }
        function setPage(page: string): void {
            Config.activeSettingsPage = page;
        }
        function scroll(y: real): void {
            settingsWindow.scrollTo(y);
        }
        // A downloaded artifact can hand itself to the consent card (a browser's "open
        // with", or a file manager). Nothing is installed: this only inspects.
        function inspectApp(file: string): void {
            Config.openSettings("apps");
            AppsService.inspect(file);
        }
        // Installing is a separate call on purpose: an artifact may only be *inspected* by
        // arriving, and the install happens when a person confirms it.
        function installApp(file: string): void {
            Config.openSettings("apps");
            AppsService.install(file);
        }
        // The same two calls the Apps page's buttons make, for scripts and verification.
        function removeApp(id: string): void {
            Config.openSettings("apps");
            AppsService.remove(id, false);
        }

    }

    IpcHandler {
        target: "downloads"
        function open(): void { Config.openDownloadsWindow(); }
        function settings(): void {
            Config.openDownloadsWindow();
            downloadsWindow.openSettings();
        }
        function raise(): void { downloadsWindow.raiseWindow(); }
        function close(): void { Config.closeDownloadsWindow(); }
        function toggle(): void { Config.toggleDownloadsWindow(); }
    }

    IpcHandler {
        // The same calls the Skills page makes, for scripts and verification.
        target: "skills"
        function refresh(): void { SkillsService.refresh(); }
        function search(query: string): void { SkillsService.search(query); }
        function setSource(source: string): void { SkillsService.setSearchSource(source); }
        function install(source: string): void { SkillsService.install(source, []); }
        function addSource(input: string, ref: string): void { SkillsService.addSource(input, ref); }
        function enable(sourceId: string, skill: string): void {
            SkillsService.setSkillEnabled(sourceId, skill, true);
        }
        function disable(sourceId: string, skill: string): void {
            SkillsService.setSkillEnabled(sourceId, skill, false);
        }
        function doctor(): void { SkillsService.runDoctor(); }
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
        function openPopout(y: real): void {
            // A drawer belongs to whichever app declares it; a disabled app opens nothing.
            if (!AppStates.integrationEnabled("drawer", "ai")) return;
            Config.openBottomPopout("ai", (y !== undefined && y > 0) ? y : 1450);
        }
        function closePopout(): void { Config.closeBottomPopout(); }
        function togglePopout(): void {
            if (Config.bottomPopoutVisible && Config.bottomPopoutMode === "ai") {
                Config.closeBottomPopout();
            } else if (AppStates.integrationEnabled("drawer", "ai")) {
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
        // Quickshell's IPC exposes at most 10 arguments per function, and a
        // function above that limit is dropped silently. `rate` therefore keeps
        // the default the body already applies when it is absent (2.0), instead
        // of being an 11th parameter that made the whole endpoint unusable.
        function triggerMultiActivity(agent1: string, model1: string, name1: string, color1: string, tokens1: real, agent2: string, model2: string, name2: string, color2: string, tokens2: real): void {
            if (typeof AiActivityService !== "undefined") {
                AiActivityService.applyActivity({
                    agent: agent1,
                    model: model1,
                    display_name: name1,
                    brand_color: color1,
                    brand_icon: "token",
                    is_active: true,
                    intensity: 1.0,
                    request_rate: 2.0,
                    token_rate: (tokens1 + tokens2),
                    recent_tokens: (tokens1 + tokens2),
                    active_agents: [
                        {
                            tool_source: agent1,
                            model_id: model1,
                            display_name: name1,
                            brand_color: color1,
                            brand_icon: "auto_awesome",
                            request_rate_rpm: 1.0,
                            token_rate_tpm: tokens1,
                            recent_tokens: tokens1
                        },
                        {
                            tool_source: agent2,
                            model_id: model2,
                            display_name: name2,
                            brand_color: color2,
                            brand_icon: "psychology",
                            request_rate_rpm: 1.0,
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
    }

    // Embedded DSH web UI (dsh/DshWebWindow.qml). open() adopts a running server
    // or starts one, then shows the view.
    IpcHandler {
        target: "dshweb"
        function toggle(): void { DshWebService.toggle(); }
        function open(): void { DshWebService.open(); }
        function close(): void { DshWebService.close(); }
        function stopServer(): void { DshWebService.stopServer(); }
    }

    IpcHandler {
        target: "assistant"
        function toggle(): void { Config.toggleAssistant(); }
        function open(): void { Config.openAssistant(); }
        function close(): void { Config.closeAssistant(); }
        function send(prompt: string): void {
            Config.openAssistant();
            AssistantService.sendMessage(prompt);
        }
        function sendWithImage(prompt: string, imagePath: string): void {
            Config.openAssistant();
            AssistantService.sendMessage(prompt, [imagePath]);
        }
        function openPicker(): void {
            Config.openAssistant();
            if (assistantWindow && assistantWindow.drawerItem) {
                assistantWindow.drawerItem.imagePickerVisible = true;
            }
        }
        function togglePicker(): void {
            Config.openAssistant();
            if (assistantWindow && assistantWindow.drawerItem) {
                assistantWindow.drawerItem.imagePickerVisible = !assistantWindow.drawerItem.imagePickerVisible;
            }
        }
        function toggleSessions(): void {
            Config.openAssistant();
            if (assistantWindow && assistantWindow.drawerItem) {
                assistantWindow.drawerItem.sessionsVisible = !assistantWindow.drawerItem.sessionsVisible;
            }
        }
        function selectSession(id: string): void {
            Config.openAssistant();
            AssistantService.loadSession(id);
        }
        function newChat(): void {
            Config.openAssistant();
            AssistantService.createNewSession();
        }
        function openFileDialog(): void {
            Config.openAssistant();
            if (assistantWindow && assistantWindow.drawerItem && assistantWindow.drawerItem.chatInputItem) {
                assistantWindow.drawerItem.chatInputItem.openNativeFileDialog();
            }
        }
        // Voice input is reachable over IPC, but no key is bound to it in v1:
        // global push-to-talk would need a hotkey contract and the repo has
        // already had shortcut conflicts once. The action exists so binding one
        // later is a config change, not a refactor.
        function toggleVoice(): void {
            Config.openAssistant();
            // Mirrors the on-screen button: toggle when recording, open the
            // settings page that resolves the gap when not ready. Never a no-op.
            AssistantService.toggleVoiceInput();
        }
        function dismissVoiceNotice(): void {
            AssistantService.dismissVoiceSetupNotice();
        }
        function startVoice(): void {
            Config.openAssistant();
            AssistantService.startVoiceInput();
        }
        function stopVoice(): void {
            AssistantService.stopVoiceInput();
        }
        function cancelVoice(): void {
            AssistantService.cancelVoiceInput();
        }
        function dismissCrashes(): void {
            AssistantService.dismissAllCrashes();
        }
    }

    IpcHandler {
        target: "overview"
        function toggle(): void { Config.toggleOverview(); }
        function open(): void { Config.openOverview(); }
        function close(): void { Config.closeOverview(); }
        function search(query: string): void {
            Config.openOverview();
            if (overviewSurface) overviewSurface.queryText = query;
        }
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
        function setArchetype(archetype: string): void {
            Config.setThemeArchetype(archetype);
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
        function keep(): void { Config.keepBottomPopout(); }
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
                const matchingWins = [];
                for (let i = 0; i < wins.length; i++) {
                    if (wins[i].appId === w.appId || (w.appName && wins[i].appName === w.appName)) {
                        matchingWins.push(wins[i]);
                    }
                }
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
                    isPinned: false,
                    windows: matchingWins,
                    windowCount: matchingWins.length
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
                appHost: featureHost
            }
        }
    }

    // Bottom Command Launcher & Wallpaper Carousel Modal
    LauncherApp {
        id: commandLauncher
        appHost: featureHost
        targetScreen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
    }


    // Migrated app components, declared here so they resolve imports in the shell's
    // context (one kernel registration, one palette).
    Component {
        id: workspacesApp
        WorkspacesApp {}
    }
    Component {
        id: mediaApp
        MediaApp {}
    }
    Component {
        id: performanceApp
        PerformanceApp {}
    }
    Component {
        id: aiApp
        AiApp {}
    }
    Component {
        id: downloadsApp
        DownloadsApp {}
    }

    // Settings GUI Window
    SettingsWindow {
        id: settingsWindow
        targetScreen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
        // Which app owns which surface, from the registry — the settings rail hides a page whose
        // app is disabled (spec C.35).
        integrations: AppStates.integrations
    }

    // Update curtain: the short surface shown while an update restarts the
    // shell, so the desktop never looks like it merely vanished.
    UpdateCurtain {
        id: updateCurtain
        targetScreen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
    }

    // AI Assistant Copilot Window
    AssistantWindow {
        assistant: AssistantService
        shellState: shellState
        intents: intents
        id: assistantWindow
        targetScreen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
    }

    // Dedicated download manager Window (real toplevel, opened from the drawer)
    DownloadsWindow {
        appComponent: downloadsApp
        id: downloadsWindow
        targetScreen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
    }

    // Embedded DSH web UI. Lazy: the window (and its WebEngineView) is only
    // instantiated when the hosting Quickshell actually has WebEngine, so stock
    // Quickshell never constructs the type that would abort it.
    LazyLoader {
        id: dshWebLoader
        active: typeof DshWebService !== "undefined"
            && DshWebService.mode === "embedded"
            && DshWebService.webEngineSupported
        source: "dsh/DshWebWindow.qml"
    }

    Component.onCompleted: {
        AppStates.adopt(bundledApps.entries);
        // One boolean for a singleton: the app is on *and* it declares this dock location.
        AiTokenService.appEnabled = bundledApps.isEnabled("org.astralplasma.ai")
            && AppStates.integrationEnabled("dockItem", "ai");
        // Intent handlers live here, next to the rest of the shell's startup wiring:
        // one completion block, so nothing about startup is split across objects.
        intents.register("overview.close", function () {
            Config.closeOverview();
            return intents.applied();
        });
        intents.register("overview.toggle", function () {
            Config.toggleOverview();
            return intents.applied();
        });
        intents.register("media.visualizerStyle", function (args) {
            const style = (args && args.style) ? String(args.style) : "";
            if (style !== "radial" && style !== "speaker") {
                return intents.invalid("media.visualizerStyle needs style=radial|speaker");
            }
            Config.setMediaVisualizerStyle(style);
            return intents.applied();
        });
        intents.register("performance.device", function (args) {
            const device = (args && args.device) ? String(args.device) : "";
            if (device !== "cpu" && device !== "memory" && device !== "gpu" && device !== "battery") {
                return intents.invalid("performance.device needs cpu|memory|gpu|battery");
            }
            Config.perfSelectedDevice = device;
            return intents.applied();
        });
        intents.register("dashboard.close", function () {
            Config.dashboardVisible = false;
            return intents.applied();
        });
        intents.register("downloads.segment", function (args) {
            const segment = (args && args.segment) ? String(args.segment) : "";
            if (segment.length === 0) {
                return intents.invalid("downloads.segment needs a segment");
            }
            Config.activeDownloadsSegment = segment;
            return intents.applied();
        });
        intents.register("downloads.dir", function (args) {
            Config.setDownloadsDir(String((args && args.value) || ""));
            return intents.applied();
        });
        intents.register("downloads.maxConcurrent", function (args) {
            Config.setDownloadsMaxConcurrent(Number((args && args.value) || 0));
            return intents.applied();
        });
        intents.register("downloads.speedLimit", function (args) {
            Config.setDownloadsSpeedLimit(Number((args && args.value) || 0));
            return intents.applied();
        });
        intents.register("downloads.split", function (args) {
            Config.setDownloadsSplit(!!(args && args.value));
            return intents.applied();
        });
        intents.register("downloads.borderEffect", function (args) {
            Config.setDownloadsBorderEffect(!!(args && args.value));
            return intents.applied();
        });
        intents.register("downloads.window", function () {
            Config.openDownloadsWindow();
            return intents.applied();
        });
        intents.register("theme.mode", function (args) {
            if (!args || typeof args.dark !== "boolean") {
                return intents.invalid("theme.mode needs dark=true|false");
            }
            Config.setDarkMode(args.dark);
            return intents.applied();
        });
        intents.register("theme.preset", function (args) {
            const preset = (args && args.preset) ? String(args.preset) : "";
            if (preset.length === 0) {
                return intents.invalid("theme.preset needs a preset");
            }
            Config.setThemePreset(preset);
            return intents.applied();
        });
        intents.register("launcher.mode", function (args) {
            Config.commandLauncherMode = (args && args.mode) ? String(args.mode) : "apps";
            return intents.applied();
        });
        intents.register("settings.open", function (args) {
            const page = (args && args.page) ? String(args.page) : "";
            const section = (args && args.section) ? String(args.section) : "";
            Config.openSettings(page, section);
            return intents.applied();
        });
        intents.register("assistant.close", function () {
            Config.closeAssistant();
            return intents.applied();
        });
        intents.register("assistant.minimize", function () {
            Config.minimizeAssistant();
            return intents.applied();
        });
        intents.register("assistant.sessions", function (args) {
            Config.assistantSessionsVisible = !!(args && args.visible);
            return intents.applied();
        });
        intents.register("ai.privacyMode", function (args) {
            if (!args || typeof args.enabled !== "boolean") {
                return intents.invalid("ai.privacyMode needs enabled=true|false");
            }
            Config.setAiPrivacyMode(args.enabled);
            return intents.applied();
        });
        intents.register("dashboard.show", function (args) {
            const tab = (args && args.tab) ? String(args.tab) : "";
            if (tab.length === 0) {
                return intents.invalid("dashboard.show needs a tab");
            }
            Config.activeDashboardTab = tab;
            Config.dashboardVisible = true;
            return intents.applied();
        });
        intents.register("launcher.show", function (args) {
            const mode = (args && args.mode) ? String(args.mode) : "apps";
            Config.commandLauncherMode = mode;
            Config.commandLauncherVisible = true;
            // One modal at a time, exactly as the launcher used to arrange it.
            Config.overviewVisible = false;
            Config.dashboardVisible = false;
            return intents.applied();
        });
        intents.register("launcher.close", function () {
            Config.closeCommandLauncher();
            return intents.applied();
        });
        intents.register("launcher.open", function (args) {
            const panel = (args && args.panel) ? String(args.panel) : "";
            if (panel.length === 0) {
                return intents.invalid("launcher.open needs a panel");
            }
            Config.openCommandLauncher(panel, (args && args.arg) ? String(args.arg) : "");
            return intents.applied();
        });
        intents.register("shell.exit", function () {
            Config.exitShell();
            return intents.applied();
        });

        // Singletons load lazily: touch the exporter so palette broadcasting
        // (colors.toml / current-palette.json / agent-theme.env) really runs.
        ThemeExportService.scheduleExport();
        if (Log.debugEnabled("shell")) {
            Log.debug("shell", "onCompleted, disablePlasmaPanels: " + Config.disablePlasmaPanels
                + ", daemonBin: " + Config.daemonBin + ", pid: " + Quickshell.processId);
        }
        if (Config.disablePlasmaPanels && DesktopSessionFacade.profile === "kde") {
            const target = (typeof Config.disablePlasmaPanels === "string") ? Config.disablePlasmaPanels : "all";
            Quickshell.execDetached([Config.daemonBin, "plasma", "disable", target]);
        }
        // Closing the shell hands the global shortcuts back to Plasma - the
        // daemon's teardown restores them, and Plasma panels too - so every
        // start has to claim them again. The daemon's watcher binds them as
        // well; this call makes the claim independent of when that watcher
        // comes up, and it is a no-op when the shortcuts are already bound.
        if (DesktopSessionFacade.profile === "kde") {
            Quickshell.execDetached([Config.daemonBin, "shortcuts", "bind", "meta-space"]);
        }
    }

    Component.onDestruction: {
        if (Log.debugEnabled("shell")) {
            Log.debug("shell", "onDestruction, autoRestorePlasmaOnExit: " + Config.autoRestorePlasmaOnExit);
        }
        // No restore here: onDestruction also runs for a *reload*, which is not
        // the user quitting. The daemon's watchdog supervises this process and
        // hands the desktop back when it actually disappears, honouring
        // `plasma.autoRestoreOnExit`.
    }
}
