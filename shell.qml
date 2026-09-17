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
            if (page) Config.activeSettingsPage = page;
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
        target: "power"
        function logout(): void { PowerService.requestLogout(); }
        function reboot(): void { PowerService.requestReboot(); }
        function shutdown(): void { PowerService.requestPoweroff(); }
        function confirm(): void { PowerService.confirmAction(); }
        function cancel(): void { PowerService.cancelAction(); }
    }

    // Unified Desktop Shell (Flush Fused Left Dock + Top Bar with Corner Fillet)
    Variants {
        model: Quickshell.screens

        Scope {
            id: screenScope
            required property ShellScreen modelData

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

    // Settings GUI Window
    SettingsWindow {
        targetScreen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
    }

    Component.onCompleted: {
        if (Config.debugMode) {
            console.log("[shell.qml] onCompleted, disablePlasmaPanels:", Config.disablePlasmaPanels, "daemonBin:", Config.daemonBin, "pid:", Quickshell.processId);
        }
        if (Config.disablePlasmaPanels) {
            const target = (typeof Config.disablePlasmaPanels === "string") ? Config.disablePlasmaPanels : "all";
            Quickshell.execDetached([Config.daemonBin, "plasma", "disable", target, "" + Quickshell.processId]);
        }
    }
}
