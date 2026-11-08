pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import "../config"

Singleton {
    id: root

    readonly property string serviceDir: Qt.resolvedUrl(".").toString().replace("file://", "").replace(/\/$/, "")
    readonly property string daemonBin: (typeof Config !== "undefined" && Config.daemonBin) ? Config.daemonBin : (root.serviceDir + "/../bin/astral-plasma")

    readonly property var adapter: (typeof Bluetooth !== "undefined") ? Bluetooth.defaultAdapter : null
    readonly property bool available: Boolean(adapter || sysAvailable)

    property bool sysPowered: false
    property bool sysAvailable: true
    property var sysDevices: []

    // Quickshell's BluetoothAdapter exposes `enabled` (not `powered`), though BlueZ/QML may expose powered in some environments.
    readonly property bool powered: {
        if (adapter) {
            if (typeof adapter.enabled !== "undefined") return adapter.enabled;
            if (typeof adapter.powered !== "undefined") return adapter.powered;
        }
        return sysPowered;
    }

    readonly property var devices: {
        if (typeof Bluetooth !== "undefined" && Bluetooth.devices) {
            const list = Bluetooth.devices.values || (Array.isArray(Bluetooth.devices) ? Bluetooth.devices : []);
            if (list.length > 0) {
                return list;
            }
        }
        return sysDevices;
    }

    function togglePower() {
        const nextState = !root.powered;
        if (adapter) {
            if (typeof adapter.enabled !== "undefined") {
                adapter.enabled = nextState;
            } else if (typeof adapter.powered !== "undefined") {
                adapter.powered = nextState;
            }
        }
        root.sysPowered = nextState;
        // Execute bluetoothctl power command directly via Quickshell.execDetached
        Quickshell.execDetached(["bluetoothctl", "power", nextState ? "on" : "off"]);
        // Trigger status refresh after brief delay for BlueZ to settle
        refreshTimer.restart();
    }

    function connectDevice(mac) {
        if (!mac) return;
        if (adapter && Bluetooth.devices && Bluetooth.devices.values) {
            const devs = Bluetooth.devices.values;
            for (let i = 0; i < devs.length; i++) {
                if ((devs[i].address === mac || devs[i].mac === mac) && devs[i].connect) {
                    devs[i].connect();
                    return;
                }
            }
        }
        Quickshell.execDetached(["bluetoothctl", "connect", mac]);
        refreshTimer.restart();
    }

    function disconnectDevice(mac) {
        if (!mac) return;
        if (adapter && Bluetooth.devices && Bluetooth.devices.values) {
            const devs = Bluetooth.devices.values;
            for (let i = 0; i < devs.length; i++) {
                if ((devs[i].address === mac || devs[i].mac === mac) && devs[i].disconnect) {
                    devs[i].disconnect();
                    return;
                }
            }
        }
        Quickshell.execDetached(["bluetoothctl", "disconnect", mac]);
        refreshTimer.restart();
    }

    function getIcon() {
        if (!powered) return "bluetooth_off";
        return "bluetooth";
    }

    function refresh() {
        if (!statusProc.running) {
            statusProc.running = true;
        }
    }

    Timer {
        id: refreshTimer
        interval: 600
        repeat: false
        onTriggered: root.refresh()
    }

    Process {
        id: statusProc
        command: [root.daemonBin, "settings", "bluetooth", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(this.text.trim());
                    if (data.powered !== undefined) {
                        root.sysPowered = Boolean(data.powered);
                    }
                    if (Array.isArray(data.devices)) {
                        let devList = [];
                        for (let i = 0; i < data.devices.length; i++) {
                            const d = data.devices[i];
                            const addr = d.mac || d.address || "";
                            devList.push({
                                mac: addr,
                                address: addr,
                                name: d.name || addr || "Bluetooth Device",
                                connected: Boolean(d.connected),
                                paired: Boolean(d.paired),
                                battery: d.battery_percent,
                                connect: function() { root.connectDevice(addr); },
                                disconnect: function() { root.disconnectDevice(addr); }
                            });
                        }
                        root.sysDevices = devList;
                    }
                } catch (e) {}
            }
        }
    }

    Component.onCompleted: {
        root.refresh();
    }
}
