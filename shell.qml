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
        target: "settings"
        function toggle(): void { Config.settingsVisible = !Config.settingsVisible; }
        function open(): void { Config.settingsVisible = true; }
        function close(): void { Config.settingsVisible = false; }
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
    }

    IpcHandler {
        target: "notification"
        function show(summary: string, body: string, icon: string, appName: string): void {
            NotificationService.show(summary, body, icon, appName);
        }
        function dismiss(): void {
            NotificationService.dismiss();
        }
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
        if (Config.disablePlasmaPanels) {
            const target = (typeof Config.disablePlasmaPanels === "string") ? Config.disablePlasmaPanels : "all";
            Quickshell.execDetached([Config.scriptPath("manage_plasma_panel.sh"), "disable", target, "" + Quickshell.processId]);
        }
    }

    Component.onDestruction: {
        if (Config.disablePlasmaPanels && Config.autoRestorePlasmaOnExit) {
            Quickshell.execDetached([Config.scriptPath("manage_plasma_panel.sh"), "restore"]);
        }
    }
}
