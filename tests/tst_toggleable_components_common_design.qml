import QtQuick
import "../components"
import "../theme"

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

    // Mock Bluetooth Service
    QtObject {
        id: mockBtService
        property bool powered: true
        property var devices: [
            { name: "Stadia2T7G-e9d5", address: "00:1A:7D:DA:71:11", connected: true, paired: true },
            { name: "POP Icon Keys", address: "00:1A:7D:DA:71:22", connected: false, paired: true }
        ]
        property int toggleCallCount: 0

        function togglePower() {
            toggleCallCount++;
            powered = !powered;
        }
    }

    // Common ActionToggleItem instantiated for Bluetooth
    ActionToggleItem {
        id: btToggleItem
        icon: !mockBtService.powered ? "bluetooth_disabled" : (mockBtService.devices[0].connected ? "bluetooth_connected" : "bluetooth")
        iconColor: mockBtService.powered ? (mockBtService.devices[0].connected ? Colors.primary : Colors.textOnSurface) : Colors.textOnSurfaceVariant
        label: mockBtService.powered ? ("Bluetooth: " + mockBtService.devices[0].name) : "Bluetooth: Off"
        checked: mockBtService.powered
        onToggled: mockBtService.togglePower()
    }

    function getBtDeviceIcon(name) {
        const n = (name || "").toLowerCase();
        if (n.includes("key") || n.includes("pop")) return "keyboard";
        if (n.includes("mouse")) return "mouse";
        if (n.includes("stadia") || n.includes("pad") || n.includes("game")) return "sports_esports";
        if (n.includes("head") || n.includes("ear") || n.includes("buds") || n.includes("airpod")) return "headphones";
        return "bluetooth";
    }

    function readLocalFile(relativePath) {
        const xhr = new XMLHttpRequest();
        xhr.open("GET", relativePath, false);
        try {
            xhr.send();
            return xhr.responseText;
        } catch (e) {
            return "";
        }
    }

    Timer {
        interval: 50
        running: true
        repeat: false
        onTriggered: runTests()
    }

    function runTests() {
        console.log("RUNNING: Common Design for Toggleable Components Unit Tests");

        // 1. Bluetooth Toggle Item Initial State
        assert(btToggleItem.checked === true, "Bluetooth toggle must be checked when powered on");
        assert(btToggleItem.label === "Bluetooth: Stadia2T7G-e9d5", "Bluetooth label must display active connected device");
        assert(btToggleItem.icon === "bluetooth_connected", "Icon must be bluetooth_connected when active device connected");
        assert(btToggleItem.iconColor === Colors.primary, "Icon color must be primary when active");

        // 2. Toggle Bluetooth OFF
        const prevCount = mockBtService.toggleCallCount;
        btToggleItem.toggled();
        assert(mockBtService.toggleCallCount === prevCount + 1, "toggled signal must invoke togglePower()");
        assert(mockBtService.powered === false, "Bluetooth powered state must flip to false");
        assert(btToggleItem.checked === false, "Toggle switch must be unchecked when Bluetooth is off");
        assert(btToggleItem.label === "Bluetooth: Off", "Label must be Bluetooth: Off");
        assert(btToggleItem.icon === "bluetooth_disabled", "Icon must be bluetooth_disabled when powered off");

        // 3. Device Glyphs Resolution Contract
        assert(getBtDeviceIcon("Stadia2T7G-e9d5") === "sports_esports", "Stadia controller maps to sports_esports icon");
        assert(getBtDeviceIcon("POP Icon Keys") === "keyboard", "POP Icon Keys maps to keyboard icon");
        assert(getBtDeviceIcon("MX Master 3S Mouse") === "mouse", "Mouse maps to mouse icon");
        assert(getBtDeviceIcon("Sony WH-1000XM4") === "headphones", "Headphones map to headphones icon");
        assert(getBtDeviceIcon("Random Unknown Device") === "bluetooth", "Default device maps to bluetooth icon");

        // 4. Source Code Verification of FusedBottomPopout.qml
        const popoutSource = readLocalFile("../dock/popouts/FusedBottomPopout.qml");
        assert(popoutSource.length > 0, "FusedBottomPopout.qml must be readable");

        // Check that both Wi-Fi and Bluetooth use ActionToggleItem
        const wifiUsesToggle = /id:\s*networkSection[\s\S]*?ActionToggleItem/.test(popoutSource);
        assert(wifiUsesToggle, "Wi-Fi section must use ActionToggleItem");

        const btUsesToggle = /id:\s*bluetoothSection[\s\S]*?ActionToggleItem/.test(popoutSource);
        assert(btUsesToggle, "Bluetooth section must use ActionToggleItem");

        // Check that legacy "Turn Bluetooth Off" button is removed
        assert(popoutSource.indexOf("Turn Bluetooth Off") === -1,
            "Legacy 'Turn Bluetooth Off' text button must be removed in favor of common ActionToggleItem");

        // Check that Bluetooth Settings... footer action item is present
        assert(popoutSource.indexOf("Bluetooth Settings...") !== -1,
            "Bluetooth section must contain 'Bluetooth Settings...' footer action");

        console.log("PASS: Common Design for Toggleable Components Unit Tests");
        Qt.exit(0);
    }
}
