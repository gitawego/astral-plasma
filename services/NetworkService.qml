pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Networking
import Quickshell.Io

Singleton {
    id: root

    readonly property bool wifiEnabled: Networking.wifiEnabled
    property string activeSsid: ""
    readonly property string ssid: (activeSsid && activeSsid.length > 0) ? activeSsid : (connected ? "Connected" : "Disconnected")
    property int signalStrength: 0
    property bool connected: false
    property var scannedNetworks: []
    readonly property var wifiNetworks: scannedNetworks

    function toggleWifi() {
        Networking.wifiEnabled = !Networking.wifiEnabled;
        if (Networking.wifiEnabled) {
            rescan();
        }
    }

    function connectToNetwork(targetSsid) {
        if (!targetSsid) return;
        Quickshell.execDetached(["nmcli", "dev", "wifi", "connect", targetSsid]);
    }

    Component.onCompleted: {
        if (!nmcliStatus.running) {
            nmcliStatus.running = true;
        }
    }

    // Process to query active SSID & scan networks via nmcli for instant reactive list
    Process {
        id: nmcliStatus
        command: ["nmcli", "-t", "-f", "ACTIVE,SSID,SIGNAL,SECURITY", "dev", "wifi"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = this.text.split("\n");
                let map = new Map();
                let currActive = "";
                let currSig = 0;
                let isConn = false;

                for (let i = 0; i < lines.length; i++) {
                    const parts = lines[i].split(":");
                    if (parts.length >= 3) {
                        const active = parts[0] === "yes";
                        const ssid = parts[1] ? parts[1].trim() : "";
                        const signal = parseInt(parts[2]) || 0;
                        const security = parts[3] ? parts[3].trim() : "";

                        if (!ssid) continue;

                        if (active) {
                            currActive = ssid;
                            currSig = signal;
                            isConn = true;
                        }

                        if (map.has(ssid)) {
                            const existing = map.get(ssid);
                            existing.active = existing.active || active;
                            if (signal > existing.signal) {
                                existing.signal = signal;
                            }
                            if (!existing.security && security) {
                                existing.security = security;
                            }
                        } else {
                            map.set(ssid, {
                                ssid: ssid,
                                signal: signal,
                                security: security || "Open",
                                active: active
                            });
                        }
                    }
                }

                let list = Array.from(map.values());
                list.sort(function(a, b) {
                    if (a.active && !b.active) return -1;
                    if (!a.active && b.active) return 1;
                    return b.signal - a.signal;
                });

                root.scannedNetworks = list;
                root.activeSsid = currActive;
                root.signalStrength = currSig;
                root.connected = isConn;
            }
        }
    }

    readonly property bool isUiActive: (typeof Config !== "undefined")
        ? ((Config.bottomPopoutVisible && Config.bottomPopoutMode === "network") ||
           (Config.activePopout === "network") ||
           (Config.settingsVisible && Config.activeSettingsPage === "network"))
        : false

    onIsUiActiveChanged: {
        if (isUiActive && wifiEnabled) {
            rescan();
        }
    }

    Timer {
        interval: 10000
        running: root.wifiEnabled && root.isUiActive
        repeat: true
        triggeredOnStart: false
        onTriggered: {
            if (root.wifiEnabled && !nmcliStatus.running) {
                nmcliStatus.running = true;
            }
        }
    }

    function rescan() {
        if (!nmcliStatus.running) nmcliStatus.running = true;
    }

    function getIcon() {
        if (!wifiEnabled) return "wifi_off";
        if (!connected) return "wifi_off";
        return "wifi";
    }
}
