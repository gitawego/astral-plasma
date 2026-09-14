pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Networking
import Quickshell.Io

Singleton {
    id: root

    readonly property bool wifiEnabled: Networking.wifiEnabled
    property string activeSsid: ""
    property int signalStrength: 0
    property bool connected: false
    property var scannedNetworks: []

    function toggleWifi() {
        Networking.wifiEnabled = !Networking.wifiEnabled;
    }

    // Process to query active SSID & scan networks via nmcli for instant reactive list
    Process {
        id: nmcliStatus
        command: ["nmcli", "-t", "-f", "ACTIVE,SSID,SIGNAL,SECURITY", "dev", "wifi"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = this.text.split("\n");
                let list = [];
                let currActive = "";
                let currSig = 0;
                let isConn = false;

                for (let i = 0; i < lines.length; i++) {
                    const parts = lines[i].split(":");
                    if (parts.length >= 3) {
                        const active = parts[0] === "yes";
                        const ssid = parts[1];
                        const signal = parseInt(parts[2]) || 0;
                        const security = parts[3] || "";

                        if (ssid && ssid.length > 0) {
                            list.push({ ssid: ssid, signal: signal, security: security, active: active });
                            if (active) {
                                currActive = ssid;
                                currSig = signal;
                                isConn = true;
                            }
                        }
                    }
                }
                root.scannedNetworks = list;
                root.activeSsid = currActive;
                root.signalStrength = currSig;
                root.connected = isConn;
            }
        }
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
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
