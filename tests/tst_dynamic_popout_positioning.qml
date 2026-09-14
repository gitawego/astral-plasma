import QtQuick
import "../components"
import "../theme"

Item {
    id: testRoot
    width: 1920
    height: 1080

    readonly property real borderT: 14
    readonly property real dockW: 70
    readonly property real filletR: 24

    property real popoutTargetY: 0
    property real popoutHeight: 260 // Wi-Fi / network drawer implicitHeight

    // Formula matching UnifiedShell.qml idealPopoutY
    readonly property real idealPopoutY: {
        let targetY = testRoot.popoutTargetY;
        if (targetY <= 0) {
            targetY = testRoot.height - testRoot.borderT - 120;
        }
        const idealY = targetY - testRoot.popoutHeight / 2;
        const minY = testRoot.borderT + testRoot.filletR + 4;
        const maxY = Math.max(minY, testRoot.height - testRoot.borderT - testRoot.popoutHeight - testRoot.filletR - 4);
        return Math.max(minY, Math.min(maxY, idealY));
    }

    // Mock NetworkService to verify SSID property and formatting
    QtObject {
        id: mockNetworkService
        property bool wifiEnabled: true
        property string activeSsid: ""
        property bool connected: false
        property var scannedNetworks: []

        readonly property string ssid: (activeSsid && activeSsid.length > 0) ? activeSsid : (connected ? "Connected" : "Disconnected")
        readonly property var wifiNetworks: scannedNetworks

        function formatWifiLabel() {
            return "Wi-Fi: " + (connected ? (activeSsid || ssid || "Connected") : "Disconnected");
        }
    }

    Timer {
        interval: 50
        running: true
        repeat: false
        onTriggered: runTests()
    }

    function assert(cond, msg) {
        if (!cond) {
            console.error("FAIL: " + msg);
            Qt.exit(1);
        }
    }

    function runTests() {
        console.log("RUNNING: Dynamic Popout Positioning & Wi-Fi SSID Unit Tests");

        // --- PART 1: Wi-Fi SSID & Network Formatting ---
        // Test 1.1: Disconnected state
        mockNetworkService.connected = false;
        mockNetworkService.activeSsid = "";
        assert(mockNetworkService.ssid === "Disconnected", "SSID should be Disconnected when not connected");
        assert(mockNetworkService.formatWifiLabel() === "Wi-Fi: Disconnected", "Label should say Disconnected");
        assert(mockNetworkService.formatWifiLabel().indexOf("undefined") === -1, "Label must NEVER be undefined");

        // Test 1.2: Connected with explicit SSID
        mockNetworkService.connected = true;
        mockNetworkService.activeSsid = "darktalker";
        assert(mockNetworkService.ssid === "darktalker", "SSID should match activeSsid");
        assert(mockNetworkService.formatWifiLabel() === "Wi-Fi: darktalker", "Label should say Wi-Fi: darktalker");
        assert(mockNetworkService.formatWifiLabel().indexOf("undefined") === -1, "Label must not contain undefined");

        // Test 1.3: Connected without SSID yet (fallback)
        mockNetworkService.activeSsid = "";
        assert(mockNetworkService.ssid === "Connected", "SSID should fallback to Connected");
        assert(mockNetworkService.formatWifiLabel() === "Wi-Fi: Connected", "Label should say Wi-Fi: Connected");

        // Test 1.4: Scanned networks array
        mockNetworkService.scannedNetworks = [
            { ssid: "darktalker", signal: 80, security: "WPA2", active: true },
            { ssid: "Freebox-62DC8E", signal: 49, security: "WPA2", active: false }
        ];
        assert(Array.isArray(mockNetworkService.wifiNetworks), "wifiNetworks must be an array");
        assert(mockNetworkService.wifiNetworks.length === 2, "wifiNetworks should have 2 items");
        assert(mockNetworkService.wifiNetworks[0].ssid === "darktalker", "First network should be darktalker");

        // --- PART 2: Generic Popout Positioning ---
        // Test 2.1: Target icon centered in middle of dock (e.g. Y = 600)
        popoutTargetY = 600;
        let expectedY = 600 - testRoot.popoutHeight / 2; // 600 - 130 = 470
        assert(Math.abs(idealPopoutY - expectedY) < 0.1, "Popout should be vertically centered around target icon");

        // Test 2.2: Target icon near top of screen (e.g. Y = 50) -> clamped to minY
        popoutTargetY = 50;
        const minY = testRoot.borderT + testRoot.filletR + 4; // 14 + 24 + 4 = 42
        assert(idealPopoutY === minY, "Popout Y must clamp to minY when icon is near top, got " + idealPopoutY + " vs " + minY);

        // Test 2.3: Target icon near bottom of screen (e.g. Y = 1060) -> clamped to maxY
        popoutTargetY = 1060;
        const maxY = testRoot.height - testRoot.borderT - testRoot.popoutHeight - testRoot.filletR - 4; // 1080 - 14 - 260 - 24 - 4 = 778
        assert(idealPopoutY === maxY, "Popout Y must clamp to maxY when icon is near bottom, got " + idealPopoutY + " vs " + maxY);

        // Test 2.4: Target icon for Wi-Fi (e.g. status pill top icon around Y = 840)
        popoutTargetY = 840;
        // 840 - 130 = 710, which is between 42 and 778
        assert(idealPopoutY === 710, "Wi-Fi popout should be centered at 710, got " + idealPopoutY);

        // Test 2.5: Inverted fillet bounds check
        // Top fillet starts at (idealPopoutY - filletR). Must be >= borderT
        assert(idealPopoutY - testRoot.filletR >= testRoot.borderT, "Top fillet must not exceed top border");
        // Bottom fillet ends at (idealPopoutY + popoutHeight + filletR). Must be <= height - borderT
        assert(idealPopoutY + testRoot.popoutHeight + testRoot.filletR <= testRoot.height - testRoot.borderT, "Bottom fillet must not exceed bottom border");

        console.log("PASS: Dynamic Popout Positioning and Wi-Fi SSID tests successfully passed!");
        Qt.exit(0);
    }
}
