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
            // Qt.exit only schedules the exit: a suite that keeps running would
            // print its PASS line and override the code (docs/LESSONS.md 37).
            throw new Error(msg);
            return false;
        }
        return true;
    }

    // Mock NetworkService for unit testing
    QtObject {
        id: mockNetworkService
        property bool wifiEnabled: true
        property string activeSsid: ""
        property bool connected: false
        property var scannedNetworks: []
        property int toggleCallCount: 0

        readonly property string ssid: (activeSsid && activeSsid.length > 0) ? activeSsid : (connected ? "Connected" : "Disconnected")
        readonly property var wifiNetworks: scannedNetworks

        function toggleWifi() {
            toggleCallCount++;
            wifiEnabled = !wifiEnabled;
        }

        function formatWifiLabel() {
            if (!wifiEnabled) return "Wi-Fi: Off";
            return "Wi-Fi: " + (connected ? (activeSsid || ssid || "Connected") : "Disconnected");
        }
    }

    // Instantiate ActionToggleItem to test component contracts
    ActionToggleItem {
        id: testToggleItem
        icon: !mockNetworkService.wifiEnabled ? "wifi_off" : (mockNetworkService.connected ? "wifi" : "wifi_find")
        // Literal stand-ins for Colors.primary / textOnSurface / textOnSurfaceVariant:
        // the offscreen harness cannot load the theme singleton, and the popout's own
        // binding to those tokens is asserted from its source in part 2.
        iconColor: mockNetworkService.wifiEnabled ? (mockNetworkService.connected ? "#CFBCFF" : "#E6E1E6") : "#CAC4D0"
        label: mockNetworkService.formatWifiLabel()
        checked: mockNetworkService.wifiEnabled
        onToggled: mockNetworkService.toggleWifi()
    }

    Timer {
        interval: 50
        running: true
        repeat: false
        onTriggered: runTests()
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

    function runTests() {
        console.log("RUNNING: Wi-Fi Toggle vs Name Click Separation Unit Tests");

        // --- PART 1: ActionToggleItem Component Behavior ---
        // 1. Initial State: Wi-Fi ON and Connected to darktalker
        mockNetworkService.wifiEnabled = true;
        mockNetworkService.connected = true;
        mockNetworkService.activeSsid = "darktalker";

        assert(testToggleItem.checked === true, "Toggle switch must be checked when Wi-Fi is enabled");
        assert(testToggleItem.label === "Wi-Fi: darktalker", "Label must display connected SSID");
        assert(testToggleItem.icon === "wifi", "Icon must be wifi when connected");
        assert(Qt.colorEqual(testToggleItem.iconColor, "#CFBCFF"),
            "Icon color must be the primary stand-in when connected");
        assert(Qt.colorEqual(testToggleItem.iconItem.color, testToggleItem.iconColor),
            "the rendered glyph follows the toggle's iconColor");

        // 2. Toggle Wi-Fi OFF via toggle switch action
        const prevCalls = mockNetworkService.toggleCallCount;
        testToggleItem.toggled();
        assert(mockNetworkService.toggleCallCount === prevCalls + 1, "toggled signal must call toggleWifi()");
        assert(mockNetworkService.wifiEnabled === false, "wifiEnabled must now be false");
        assert(testToggleItem.checked === false, "Toggle switch must be unchecked when Wi-Fi is disabled");
        assert(testToggleItem.label === "Wi-Fi: Off", "Label must display 'Wi-Fi: Off' when disabled");
        assert(testToggleItem.icon === "wifi_off", "Icon must be wifi_off when disabled");
        assert(Qt.colorEqual(testToggleItem.iconColor, "#CAC4D0"),
            "Icon color must be the muted stand-in when disabled");

        // 3. Toggle Wi-Fi back ON
        testToggleItem.toggled();
        assert(mockNetworkService.wifiEnabled === true, "wifiEnabled must now be true again");
        assert(testToggleItem.checked === true, "Toggle switch must be checked again");

        // 4. Disconnected State while Wi-Fi is ON
        mockNetworkService.connected = false;
        mockNetworkService.activeSsid = "";
        assert(testToggleItem.label === "Wi-Fi: Disconnected", "Label must display 'Wi-Fi: Disconnected' when enabled but not connected");
        assert(testToggleItem.checked === true, "Toggle switch must remain checked when disconnected but enabled");

        // --- PART 2: Source Verification of FusedBottomPopout.qml ---
        const popoutSource = readLocalFile("../dock/popouts/FusedBottomPopout.qml");
        assert(popoutSource.length > 0, "FusedBottomPopout.qml source must be readable");

        // Must NOT use ActionItem that toggles on click of the Wi-Fi name
        const legacyPattern = /ActionItem\s*\{[\s\S]*?Wi-Fi:[\s\S]*?onClicked:\s*NetworkService\.toggleWifi\(\)/;
        assert(!legacyPattern.test(popoutSource),
            "CRITICAL: Wi-Fi name must NOT be an ActionItem whose onClicked toggles Wi-Fi");

        // The real binding: the popout derives the icon colour from the live state
        // and the theme tokens (the mirror above uses literals for the harness).
        const wifiToggleStart = popoutSource.indexOf("id: wifiToggleItem");
        assert(wifiToggleStart >= 0, "FusedBottomPopout must render the Wi-Fi toggle");
        const wifiToggleBlock = popoutSource.substring(wifiToggleStart, wifiToggleStart + 400);
        assert(wifiToggleBlock.indexOf("iconColor: NetworkService.wifiEnabled") >= 0
                && wifiToggleBlock.indexOf("Colors.primary") >= 0
                && wifiToggleBlock.indexOf("Colors.textOnSurfaceVariant") >= 0,
            "the Wi-Fi toggle's icon colour comes from the live state and the theme tokens");

        // Must have dedicated toggle switch item or ActionToggleItem
        assert(popoutSource.indexOf("ActionToggleItem") !== -1 || popoutSource.indexOf("wifiToggle") !== -1,
            "FusedBottomPopout must have dedicated Wi-Fi toggle component");

        // Must connect toggle to NetworkService.toggleWifi()
        assert(/onToggled:\s*NetworkService\.toggleWifi\(\)/.test(popoutSource),
            "Wi-Fi toggle must trigger NetworkService.toggleWifi()");

        console.log("PASS: Wi-Fi Toggle vs Name Click Separation Unit Tests");
        Qt.exit(0);
    }
}
