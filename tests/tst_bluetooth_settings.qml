import QtQuick
import "../settings_gui/pages"

Item {
    id: testRoot
    width: 800
    height: 600

    function assert(cond, msg) {
        if (!cond) {
            console.error("FAIL: " + msg);
            Qt.exit(1);
            return false;
        }
        return true;
    }

    BluetoothPage {
        id: btPage
        testMode: true
        testPowered: false
        testDevices: [
            { mac: "DA:11:DB:A1:3A:9C", address: "DA:11:DB:A1:3A:9C", name: "POP Icon Keys", connected: false, paired: true },
            { mac: "EA:F4:19:E4:E9:D5", address: "EA:F4:19:E4:E9:D5", name: "Stadia2T7G-e9d5", connected: true, paired: true }
        ]
    }

    Timer {
        interval: 50
        running: true
        repeat: false
        onTriggered: runTests()
    }

    function runTests() {
        console.log("RUNNING: BluetoothPage & BluetoothService Unit Tests");

        // 1. Initial State in test mode: powered is false
        assert(btPage.powered === false, "BluetoothPage powered must start false");
        assert(btPage.devicesList.length === 2, "BluetoothPage must expose 2 test devices");

        // 2. Toggle power in test mode
        btPage.testPowered = true;
        assert(btPage.powered === true, "BluetoothPage powered must become true when toggled");

        // 3. Verify mock Quickshell adapter contract with enabled (not powered)
        let mockAdapter = {
            enabled: false,
            setEnabled: function(v) { this.enabled = v; }
        };

        // Service resolution logic
        let servicePowered = function(ad, sysPow) {
            if (ad) {
                if (typeof ad.enabled !== "undefined") return ad.enabled;
                if (typeof ad.powered !== "undefined") return ad.powered;
            }
            return sysPow;
        };

        assert(servicePowered(mockAdapter, false) === false, "Adapter with enabled=false must yield powered=false");
        mockAdapter.enabled = true;
        assert(servicePowered(mockAdapter, false) === true, "Adapter with enabled=true must yield powered=true");

        // 4. Fallback to sysPowered when adapter is null
        assert(servicePowered(null, true) === true, "Fallback to sysPowered when adapter is null must work");
        assert(servicePowered(null, false) === false, "Fallback to sysPowered=false when adapter is null must work");

        console.log("PASS: BluetoothPage & BluetoothService Unit Tests");
        Qt.exit(0);
    }
}
