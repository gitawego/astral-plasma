pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Bluetooth

Singleton {
    id: root

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool available: Boolean(adapter)
    readonly property bool powered: Boolean(adapter && adapter.powered)
    readonly property var devices: Bluetooth.devices

    function togglePower() {
        if (adapter) {
            adapter.powered = !adapter.powered;
        }
    }

    function getIcon() {
        if (!powered) return "bluetooth_off";
        return "bluetooth";
    }
}
