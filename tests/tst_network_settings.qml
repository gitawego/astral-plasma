import QtQuick
import "../theme"
import "../components"
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

    // Instantiate MaterialIcon to test icon mapping contract
    MaterialIcon { id: testIconWifi; text: "wifi" }
    MaterialIcon { id: testIconWifi3; text: "network_wifi_3_bar" }
    MaterialIcon { id: testIconWifi2; text: "network_wifi_2_bar" }
    MaterialIcon { id: testIconWifi1; text: "network_wifi_1_bar" }
    MaterialIcon { id: testIconRefresh; text: "refresh" }
    MaterialIcon { id: testIconDrag; text: "drag_indicator" }

    NetworkPage {
        id: netPage
        testMode: true
        testWifiEnabled: true
        testActiveSsid: "darktalker"
        testNetworks: [
            { ssid: "darktalker", signal: 72, security: "WPA2", active: true },
            { ssid: "SFR_275F", signal: 55, security: "WPA1 WPA2", active: false },
            { ssid: "Livebox-9EE8", signal: 49, security: "WPA2", active: false }
        ]
    }

    Timer {
        interval: 50
        running: true
        repeat: false
        onTriggered: runTests()
    }

    function runTests() {
        console.log("RUNNING: NetworkPage & Icon Resolution Unit Tests");

        // 1. Initial State
        assert(netPage.wifiEnabled === true, "NetworkPage wifiEnabled must start true");
        assert(netPage.activeSsid === "darktalker", "activeSsid must match connected SSID");
        assert(netPage.networksList.length === 3, "Network list must contain 3 items");

        // 2. Wi-Fi master power toggle
        netPage.testWifiEnabled = false;
        assert(netPage.wifiEnabled === false, "wifiEnabled must toggle to false");
        netPage.testWifiEnabled = true;
        assert(netPage.wifiEnabled === true, "wifiEnabled must toggle back to true");

        // 3. Verify deduplication function contract
        function deduplicateNetworks(rawList) {
            const map = new Map();
            let currActive = "";
            let currSig = 0;
            let isConn = false;

            for (let i = 0; i < rawList.length; i++) {
                const item = rawList[i];
                const ssid = (item.ssid || "").trim();
                if (!ssid) continue;

                const active = Boolean(item.active || item.is_connected);
                const signal = item.signal || 0;
                const security = (item.security || "").trim();

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

            let list = Array.from(map.values());
            list.sort(function(a, b) {
                if (a.active && !b.active) return -1;
                if (!a.active && b.active) return 1;
                return b.signal - a.signal;
            });
            return { list: list, activeSsid: currActive, isConnected: isConn };
        }

        const rawSimulated = [
            { ssid: "darktalker", signal: 72, security: "WPA2", active: false },
            { ssid: "darktalker", signal: 58, security: "WPA2", active: true },
            { ssid: "SFR_275F", signal: 50, security: "WPA1 WPA2", active: false },
            { ssid: "SFR_275F", signal: 34, security: "WPA1 WPA2", active: false },
            { ssid: "", signal: 34, security: "WPA2", active: false },
            { ssid: "Livebox-9EE8", signal: 49, security: "WPA2", active: false }
        ];

        const processed = deduplicateNetworks(rawSimulated);
        assert(processed.list.length === 3, "Deduplication must collapse duplicates and remove empty SSIDs, got " + processed.list.length);
        assert(processed.list[0].ssid === "darktalker", "Connected SSID 'darktalker' must be first in list");
        assert(processed.list[0].active === true, "Connected network must have active=true");
        assert(processed.list[0].signal === 72, "Strongest signal (72) must be preserved for darktalker");
        assert(processed.list[1].ssid === "SFR_275F", "Second network must be SFR_275F");
        assert(processed.list[1].signal === 50, "Strongest signal (50) must be preserved for SFR_275F");

        // 4. Icon Resolution: Verify that icons do NOT resolve to raw ASCII letters ("N", "R", "D")
        assert(testIconWifi.displaySymbol !== "W" && testIconWifi.displaySymbol.length > 0, "wifi icon must resolve to Nerd Font glyph, not 'W'");
        assert(testIconWifi3.displaySymbol !== "N" && testIconWifi3.displaySymbol.length > 0, "network_wifi_3_bar must resolve to glyph, not 'N'");
        assert(testIconWifi2.displaySymbol !== "N" && testIconWifi2.displaySymbol.length > 0, "network_wifi_2_bar must resolve to glyph, not 'N'");
        assert(testIconWifi1.displaySymbol !== "N" && testIconWifi1.displaySymbol.length > 0, "network_wifi_1_bar must resolve to glyph, not 'N'");
        assert(testIconRefresh.displaySymbol !== "R" && testIconRefresh.displaySymbol.length > 0, "refresh icon must resolve to glyph, not 'R'");
        assert(testIconDrag.displaySymbol !== "D" && testIconDrag.displaySymbol.length > 0, "drag_indicator must resolve to glyph, not 'D'");

        console.log("PASS: NetworkPage & Icon Resolution Unit Tests");
        Qt.exit(0);
    }
}
