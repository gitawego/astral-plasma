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

    function reboot() {
        Quickshell.execDetached(["systemctl", "reboot"]);
    }

    function poweroff() {
        Quickshell.execDetached(["systemctl", "poweroff"]);
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
