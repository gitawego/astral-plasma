pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property string currentProfile: "performance" // "power-saver", "balanced", "performance"
    property string batteryString: "No battery detected"
    property int batteryPercentage: 100
    readonly property real percentage: batteryPercentage / 100.0
    property bool hasBattery: false
    property bool isCharging: false

    // Confirmation dialog state
    property bool confirmDialogVisible: false
    property string pendingAction: "" // "logout", "restart", "shutdown"
    property string pendingTitle: ""
    property string pendingMessage: ""
    property string pendingIcon: ""
    property string pendingConfirmLabel: ""
    property color pendingAccentColor: (typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#6B4FA0"

    // Testing and safety guards
    property bool isTesting: false
    property string lastExecutedAction: ""

    function setProfile(profile) {
        currentProfile = profile;
        Quickshell.execDetached(["powerprofilesctl", "set", profile]);
    }

    function lock() {
        Quickshell.execDetached(["loginctl", "lock-session"]);
    }

    function suspend() {
        Quickshell.execDetached(["systemctl", "suspend"]);
    }

    // Request methods that trigger confirmation dialog
    function requestLogout() {
        if (typeof Config !== "undefined" && Config.closeBottomPopout) {
            Config.closeBottomPopout();
        }
        pendingAction = "logout";
        pendingTitle = "Log Out";
        pendingMessage = "Are you sure you want to end your current session and log out?";
        pendingIcon = "logout";
        pendingConfirmLabel = "Log Out";
        pendingAccentColor = (typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#6B4FA0";
        confirmDialogVisible = true;
    }

    function requestReboot() {
        if (typeof Config !== "undefined" && Config.closeBottomPopout) {
            Config.closeBottomPopout();
        }
        pendingAction = "restart";
        pendingTitle = "Restart";
        pendingMessage = "Are you sure you want to restart your computer? Any unsaved work will be lost.";
        pendingIcon = "restart_alt";
        pendingConfirmLabel = "Restart";
        pendingAccentColor = (typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#6B4FA0";
        confirmDialogVisible = true;
    }

    function requestPoweroff() {
        if (typeof Config !== "undefined" && Config.closeBottomPopout) {
            Config.closeBottomPopout();
        }
        pendingAction = "shutdown";
        pendingTitle = "Shut Down";
        pendingMessage = "Are you sure you want to shut down your computer? Any unsaved work will be lost.";
        pendingIcon = "power_settings_new";
        pendingConfirmLabel = "Shut Down";
        pendingAccentColor = (typeof Colors !== "undefined" && Colors.error) ? Colors.error : "#BA1A1A";
        confirmDialogVisible = true;
    }

    function cancelAction() {
        confirmDialogVisible = false;
        pendingAction = "";
        pendingTitle = "";
        pendingMessage = "";
        pendingIcon = "";
        pendingConfirmLabel = "";
    }

    function confirmAction() {
        const act = pendingAction;
        confirmDialogVisible = false;
        pendingAction = "";
        pendingTitle = "";
        pendingMessage = "";
        pendingIcon = "";
        pendingConfirmLabel = "";

        if (act === "logout") {
            executeLogout();
        } else if (act === "restart") {
            executeReboot();
        } else if (act === "shutdown") {
            executePoweroff();
        }
    }

    // Direct execution methods (called only after user confirmation)
    function executeLogout() {
        lastExecutedAction = "logout";
        if (isTesting) return;
        Quickshell.execDetached(["qdbus6", "org.kde.Shutdown", "/Shutdown", "org.kde.Shutdown.logout"]);
    }

    function executeReboot() {
        lastExecutedAction = "restart";
        if (isTesting) return;
        Quickshell.execDetached(["systemctl", "reboot"]);
    }

    function executePoweroff() {
        lastExecutedAction = "shutdown";
        if (isTesting) return;
        Quickshell.execDetached(["systemctl", "poweroff"]);
    }

    // Safe entry points: always require confirmation
    function logout() {
        requestLogout();
    }

    function reboot() {
        requestReboot();
    }

    function poweroff() {
        requestPoweroff();
    }

    function getIcon() {
        if (!hasBattery) {
            switch (currentProfile) {
                case "power-saver": return "energy_savings_leaf";
                case "balanced": return "balance";
                default: return "rocket_launch";
            }
        }
        if (isCharging) return "battery_charging_full";
        if (batteryPercentage < 20) return "battery_alert";
        if (batteryPercentage < 60) return "battery_3_bar";
        return "battery_full";
    }

    // Refresh profile on timer
    Process {
        id: readProfile
        command: ["powerprofilesctl", "get"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const p = this.text.trim();
                if (p === "performance" || p === "balanced" || p === "power-saver") {
                    root.currentProfile = p;
                }
            }
        }
    }

    // Refresh battery on timer
    Process {
        id: readBattery
        command: ["upower", "-i", "/org/freedesktop/UPower/devices/battery_BAT0"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const text = this.text;
                    if (text.includes("percentage:")) {
                        root.hasBattery = true;
                        const pctMatch = text.match(/percentage:\s+([0-9]+)%/);
                        if (pctMatch) root.batteryPercentage = parseInt(pctMatch[1]);

                        const stateMatch = text.match(/state:\s+([a-zA-Z-]+)/);
                        const state = stateMatch ? stateMatch[1] : "";
                        root.isCharging = (state === "charging" || state === "fully-charged");

                        root.batteryString = `Battery: ${root.batteryPercentage}% (${state})`;
                    } else {
                        root.hasBattery = false;
                        root.batteryString = "No battery detected";
                    }
                } catch (e) {
                    root.hasBattery = false;
                    root.batteryString = "No battery detected";
                }
            }
        }
    }

    Timer {
        interval: 10000
        running: true
        repeat: true
        onTriggered: {
            if (!readProfile.running) readProfile.running = true;
            if (!readBattery.running) readBattery.running = true;
        }
    }
}
