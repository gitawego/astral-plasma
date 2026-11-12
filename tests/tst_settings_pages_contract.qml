import QtQuick
import "../settings_gui/pages"

// ============================================================================
// Every settings page adopts the hub contract — Atlas
// ============================================================================
// The hub pins each page's identity (icon, title, subtitle and its tab strip)
// above the scroll area, and a section is a tab rather than a scroll target. A
// page that hand-writes its own header or keeps its sections private silently
// falls back to the old behaviour: the title scrolls away, there is no tab
// strip, and the deep links in `Config.settingsSection` land nowhere.
//
// So the contract is asserted per page, not per component:
//
//   * the root *is* `SettingsPage` (identity and tabs declared, never redrawn
//     by hand);
//   * every page names itself, says what it is for, and carries an icon;
//   * every tab has an id, a label and an icon, in declaration order;
//   * the first tab is selected by default, `selectTab` switches the body, and
//     an unknown id is ignored;
//   * a tab that disappears with its live state (no streams, Wi-Fi off, adapter
//     off) hands the selection back to a tab that still exists.
//
// The AiPage keeps its own root (it hosts absolutely positioned overlays) and is
// covered by `tst_settings_sticky_header.qml`.
Item {
    id: testRoot
    width: 900
    height: 700

    WallpaperAndStylePage {
        id: wallpaperPage
        testMode: true
        testWallpapers: [
            { path: "/tmp/a.png", thumbnail_path: "/tmp/a.png" },
            { path: "/tmp/b.png", thumbnail_path: "/tmp/b.png" }
        ]
    }

    ThemePage {
        id: themePage
        testMode: true
    }

    NetworkPage {
        id: networkPage
        testMode: true
        testWifiEnabled: true
        testActiveSsid: "darktalker"
        testNetworks: [
            { ssid: "darktalker", active: true, signal: 92, security: "WPA2" },
            { ssid: "Cafe", active: false, signal: 40, security: "Open" }
        ]
    }

    BluetoothPage {
        id: bluetoothPage
        testMode: true
        testPowered: true
        testDevices: [
            { mac: "DA:11:DB:A1:3A:9C", name: "POP Icon Keys", connected: false, paired: true }
        ]
    }

    AudioPage {
        id: audioPage
        testMode: true
        testAppStreams: [
            { id: 1, app_name: "Elisa", volume: 0.5, is_muted: false }
        ]
    }

    DockPage {
        id: dockPage
    }

    StatusIconsPage {
        id: statusPage
    }

    DashboardPage {
        id: dashboardPage
        testMode: true
    }

    DownloadsPage {
        id: downloadsPage
        testMode: true
    }

    AppsPage {
        id: appsPage
        testMode: true
    }

    SystemPage {
        id: systemPage
        testMode: true
    }

    TimePage {
        id: timePage
        testMode: true
    }

    UpdatesPage {
        id: updatesPage
        testMode: true
        testStatus: ({})
        testChangelog: []
    }

    VoicePage {
        id: voicePage
        testMode: true
    }

    /// `[page, source path, expected tab ids]` - the document, in one table, so
    /// a page cannot satisfy the contract by accident of a similar neighbour.
    /// An empty list is a page with one section: one section is not navigation.
    readonly property var pages: [
        {
            name: "WallpaperAndStylePage",
            source: "../settings_gui/pages/WallpaperAndStylePage.qml",
            page: wallpaperPage,
            tabs: ["wallpaper", "palette", "mode", "gallery"]
        },
        {
            name: "UpdatesPage",
            source: "../settings_gui/pages/UpdatesPage.qml",
            page: updatesPage,
            tabs: ["version", "update", "notes", "maintenance"]
        },
        {
            name: "ThemePage",
            source: "../settings_gui/pages/ThemePage.qml",
            page: themePage,
            tabs: ["style", "colors", "shape", "preview"]
        },
        {
            name: "NetworkPage",
            source: "../settings_gui/pages/NetworkPage.qml",
            page: networkPage,
            tabs: ["wifi", "networks"]
        },
        {
            name: "BluetoothPage",
            source: "../settings_gui/pages/BluetoothPage.qml",
            page: bluetoothPage,
            tabs: ["power", "devices"]
        },
        {
            name: "AudioPage",
            source: "../settings_gui/pages/AudioPage.qml",
            page: audioPage,
            tabs: ["output", "visualizer", "apps"]
        },
        {
            name: "DockPage",
            source: "../settings_gui/pages/DockPage.qml",
            page: dockPage,
            tabs: ["dock", "tray", "topbar"]
        },
        {
            name: "StatusIconsPage",
            source: "../settings_gui/pages/StatusIconsPage.qml",
            page: statusPage,
            tabs: []
        },
        {
            name: "DashboardPage",
            source: "../settings_gui/pages/DashboardPage.qml",
            page: dashboardPage,
            tabs: ["tabs", "calendar", "visualizer", "avatars"]
        },
        {
            name: "DownloadsPage",
            source: "../settings_gui/pages/DownloadsPage.qml",
            page: downloadsPage,
            tabs: ["engine", "destination", "settings"]
        },
        {
            name: "AppsPage",
            source: "../settings_gui/pages/AppsPage.qml",
            page: appsPage,
            tabs: []
        },
        {
            name: "SystemPage",
            source: "../settings_gui/pages/SystemPage.qml",
            page: systemPage,
            tabs: ["services", "desktop", "session", "developer", "logging"]
        },
        {
            name: "TimePage",
            source: "../settings_gui/pages/TimePage.qml",
            page: timePage,
            tabs: ["cities", "local"]
        },
        {
            name: "VoicePage",
            source: "../settings_gui/pages/VoicePage.qml",
            page: voicePage,
            tabs: ["engine", "model", "audio", "preferences"]
        }
    ]

    function assert(condition, message) {
        if (!condition) {
            console.error("FAIL: " + message);
            Qt.exit(1);
            throw new Error(message);
        }
    }

    function readLocalFile(relUrl) {
        const xhr = new XMLHttpRequest();
        const bust = (relUrl.indexOf("?") < 0 ? "?v=" : "&v=") + Date.now() + Math.random();
        xhr.open("GET", Qt.resolvedUrl(relUrl) + bust, false);
        xhr.send();
        return xhr.responseText || "";
    }

    Timer {
        interval: 120
        running: true
        repeat: false
        onTriggered: runTests()
    }

    function runTests() {
        console.log("RUNNING: Settings Pages Contract");

        for (let i = 0; i < testRoot.pages.length; ++i) {
            const row = testRoot.pages[i];
            const page = row.page;

            // ------------------------------------------------------------------
            // The declaration lives in the page, not in a redrawn header
            // ------------------------------------------------------------------
            const src = readLocalFile(row.source);
            assert(src !== "", row.name + ": source is readable");
            assert(/\nSettingsPage \{/.test(src),
                row.name + ": the root is SettingsPage (identity and tabs declared once)");
            assert(src.indexOf("property Component stickyHeader") < 0,
                row.name + ": it does not hand-write the sticky header SettingsPage provides");
            assert(src.indexOf("zones:") < 0,
                row.name + ": it does not declare the legacy zone rail");

            // ------------------------------------------------------------------
            // Identity
            // ------------------------------------------------------------------
            assert(page.title !== "", row.name + ": the page names itself");
            assert(page.subtitle !== "", row.name + ": it says what it is for");
            assert(page.icon !== "", row.name + ": it carries a page icon");
            assert(page.stickyHeader !== null && typeof page.stickyHeader === "object",
                row.name + ": the hub has a header to pin");
            assert(page.hasRail === false,
                row.name + ": no page uses the legacy scroll rail");

            // ------------------------------------------------------------------
            // Tabs: declared, labelled, iconed, in order
            // ------------------------------------------------------------------
            assert(page.hasTabs === (row.tabs.length > 0),
                row.name + ": tabs appear exactly when there is more than one section");
            assert(page.tabs.length === row.tabs.length,
                row.name + ": " + row.tabs.length + " tabs declared (got " + page.tabs.length + ")");

            for (let t = 0; t < row.tabs.length; ++t) {
                const id = row.tabs[t];
                const tab = page.tabs[t];
                assert(tab && tab.id === id,
                    row.name + ": tab " + t + " is \"" + id + "\" (got " + (tab ? tab.id : "none") + ")");
                assert(tab.label && tab.label !== "",
                    row.name + ": tab \"" + id + "\" carries a label");
                assert(tab.icon && tab.icon !== "",
                    row.name + ": tab \"" + id + "\" carries an icon");
            }

            if (row.tabs.length > 0) {
                assert(page.currentTab === row.tabs[0],
                    row.name + ": the first tab is selected by default (got \"" + page.currentTab + "\")");

                const last = row.tabs[row.tabs.length - 1];
                page.selectTab(last);
                assert(page.currentTab === last,
                    row.name + ": selectTab switches to \"" + last + "\"");
                page.selectTab("nonsense");
                assert(page.currentTab === last,
                    row.name + ": an unknown tab id is ignored");
                page.selectTab(row.tabs[0]);
            } else {
                assert(page.currentTab === "",
                    row.name + ": a single-section page has no tab selected");
                page.selectTab("nonsense");
                assert(page.currentTab === "",
                    row.name + ": and selectTab is a no-op");
            }
        }

        // ------------------------------------------------------------------
        // A tab whose section cannot be shown is not offered
        // ------------------------------------------------------------------
        // The tab strip is the page's live state, not a static menu: when a
        // section is hidden (no streams, Wi-Fi off, adapter off) its tab goes
        // too, and the selection falls back to a tab that still exists.
        assert(audioPage.tabs.length === 3, "audio: the apps tab is offered while a stream plays");
        audioPage.selectTab("apps");
        audioPage.testAppStreams = [];
        assert(audioPage.tabs.length === 2,
            "audio: the apps tab leaves with the streams");
        assert(audioPage.currentTab === "output",
            "audio: a vanished tab hands the selection back to Output");

        assert(networkPage.tabs.length === 2, "network: the networks tab is offered while Wi-Fi is on");
        networkPage.selectTab("networks");
        networkPage.testWifiEnabled = false;
        assert(networkPage.tabs.length === 1,
            "network: the networks tab leaves when Wi-Fi is off");
        assert(networkPage.currentTab === "wifi",
            "network: a vanished tab hands the selection back to Wi-Fi");

        assert(bluetoothPage.tabs.length === 2, "bluetooth: the devices tab is offered while powered on");
        bluetoothPage.selectTab("devices");
        bluetoothPage.testPowered = false;
        assert(bluetoothPage.tabs.length === 1,
            "bluetooth: the devices tab leaves when the adapter is off");
        assert(bluetoothPage.currentTab === "power",
            "bluetooth: a vanished tab hands the selection back to Power");

        // ------------------------------------------------------------------
        // The hub routes sections through selectTab, not through scrollTo
        // ------------------------------------------------------------------
        const hub = readLocalFile("../settings_gui/NexusHub.qml");
        assert(hub.indexOf("function scrollToSection") >= 0,
            "the hub keeps one entry point for deep links");
        assert(hub.indexOf("page.selectTab(zoneId)") >= 0,
            "a deep link selects the page's tab");
        assert(hub.indexOf("page.hasTabs") >= 0,
            "the hub recognizes an Atlas page");
        assert(hub.indexOf("Config.settingsSection") >= 0,
            "external deep links still arrive through Config.openSettings");
        assert(hub.indexOf("id: stickyHeaderLoader") >= 0,
            "the hub still pins the page header outside the flickable");

        console.log("PASS: Settings Pages Contract");
        Qt.exit(0);
    }
}
