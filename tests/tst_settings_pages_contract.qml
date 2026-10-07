import QtQuick
import "../settings_gui/pages"

// ============================================================================
// Every settings page adopts the hub contract
// ============================================================================
// The settings hub pins each page's identity (title, subtitle and the zone rail)
// above the scroll area and navigates between zones. A page that hand-writes its
// own header or keeps its sections private silently falls back to the old
// behaviour: the title scrolls away, there is no rail, and the deep links in
// `Config.settingsSection` land nowhere.
//
// So the contract is asserted per page, not per component:
//
//   * the root *is* `SettingsPage` (identity and zones declared, never redrawn
//     by hand);
//   * every page names itself and its sections;
//   * every zone's anchor resolves to a real offset, in document order, so the
//     rail can scroll to it;
//   * the four members the hub reads are present and answer.
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

    SystemPage {
        id: systemPage
        testMode: true
    }

    TimePage {
        id: timePage
        testMode: true
    }

    VoicePage {
        id: voicePage
        testMode: true
    }

    /// `[page, source path, expected zone ids]` - the document, in one table, so
    /// a page cannot satisfy the contract by accident of a similar neighbour.
    readonly property var pages: [
        {
            name: "WallpaperAndStylePage",
            source: "../settings_gui/pages/WallpaperAndStylePage.qml",
            page: wallpaperPage,
            zones: ["wallpaper", "palette", "mode", "gallery"]
        },
        {
            name: "ThemePage",
            source: "../settings_gui/pages/ThemePage.qml",
            page: themePage,
            zones: ["style", "colors", "shape", "preview"]
        },
        {
            name: "NetworkPage",
            source: "../settings_gui/pages/NetworkPage.qml",
            page: networkPage,
            zones: ["wifi", "networks"]
        },
        {
            name: "BluetoothPage",
            source: "../settings_gui/pages/BluetoothPage.qml",
            page: bluetoothPage,
            zones: ["power", "devices"]
        },
        {
            name: "AudioPage",
            source: "../settings_gui/pages/AudioPage.qml",
            page: audioPage,
            zones: ["output", "visualizer", "apps"]
        },
        {
            name: "DockPage",
            source: "../settings_gui/pages/DockPage.qml",
            page: dockPage,
            zones: ["dock", "tray", "topbar"]
        },
        {
            name: "StatusIconsPage",
            source: "../settings_gui/pages/StatusIconsPage.qml",
            page: statusPage,
            zones: ["icons"]
        },
        {
            name: "DashboardPage",
            source: "../settings_gui/pages/DashboardPage.qml",
            page: dashboardPage,
            zones: ["tabs", "calendar", "visualizer", "avatars"]
        },
        {
            name: "DownloadsPage",
            source: "../settings_gui/pages/DownloadsPage.qml",
            page: downloadsPage,
            zones: ["engine", "destination", "settings"]
        },
        {
            name: "SystemPage",
            source: "../settings_gui/pages/SystemPage.qml",
            page: systemPage,
            zones: ["services", "desktop", "session", "developer", "logging", "display"]
        },
        {
            name: "TimePage",
            source: "../settings_gui/pages/TimePage.qml",
            page: timePage,
            zones: ["cities", "local"]
        },
        {
            name: "VoicePage",
            source: "../settings_gui/pages/VoicePage.qml",
            page: voicePage,
            zones: ["engine", "model", "audio", "preferences"]
        }
    ]

    function assert(condition, message) {
        if (!condition) {
            console.error("FAIL: " + message);
            Qt.exit(1);
            throw new Error(message);
        }
    }

    property string lastZoneRequest: ""
    function zoneProbe(zoneId) { testRoot.lastZoneRequest = zoneId; }

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
                row.name + ": the root is SettingsPage (identity and zones declared once)");
            assert(src.indexOf("property Component stickyHeader") < 0,
                row.name + ": it does not hand-write the sticky header SettingsPage provides");
            assert(src.indexOf("zones:") >= 0, row.name + ": it declares its zones");

            // ------------------------------------------------------------------
            // Identity
            // ------------------------------------------------------------------
            assert(page.title !== "", row.name + ": the page names itself");
            assert(page.subtitle !== "", row.name + ": it says what it is for");
            assert(page.stickyHeader !== null && typeof page.stickyHeader === "object",
                row.name + ": the hub has a header to pin");
            assert(typeof page.sectionY === "function" && typeof page.isZoneCurrent === "function",
                row.name + ": the hub can ask it where a zone is and which one is current");
            assert(page.currentSection === "", row.name + ": the hub can write the current zone");

            // ------------------------------------------------------------------
            // Zones: declared, labelled, anchored, in order
            // ------------------------------------------------------------------
            assert(page.zones.length === row.zones.length,
                row.name + ": " + row.zones.length + " zones declared (got " + page.zones.length + ")");
            let previousY = -1;
            for (let z = 0; z < row.zones.length; ++z) {
                const id = row.zones[z];
                const zone = page.zones[z];
                assert(zone && zone.id === id,
                    row.name + ": zone " + z + " is \"" + id + "\" (got " + (zone ? zone.id : "none") + ")");
                assert(zone.label && zone.label !== "",
                    row.name + ": zone \"" + id + "\" carries a label for the rail");
                const y = page.sectionY(id);
                assert(y !== undefined && y !== null && !isNaN(y),
                    row.name + ": zone \"" + id + "\" resolves to a page offset");
                assert(y > previousY,
                    row.name + ": zone \"" + id + "\" is anchored below the previous one ("
                        + previousY + " -> " + y + ")");
                previousY = y;
            }
            assert(page.sectionY("nonsense") === undefined,
                row.name + ": an undeclared zone has no anchor");

            // ------------------------------------------------------------------
            // A rail press asks the host - it never writes a global
            // ------------------------------------------------------------------
            // The rail was dead because the page wrote `Config.settingsSection`
            // from a file that never imported `Config`: an unimported singleton
            // is not in a component's scope, so the guarded write was a no-op.
            // The page now asks the host with a signal.
            testRoot.lastZoneRequest = "";
            page.zoneRequested.connect(testRoot.zoneProbe);
            page.jumpToZone(row.zones[row.zones.length - 1]);
            page.zoneRequested.disconnect(testRoot.zoneProbe);
            assert(testRoot.lastZoneRequest === row.zones[row.zones.length - 1],
                row.name + ": a rail press asks the host for that zone");
            assert(src.indexOf("Config.settingsSection =") < 0,
                row.name + ": navigation is a request to the host, not a global write");

            // ------------------------------------------------------------------
            // The rail's one rule
            // ------------------------------------------------------------------
            assert(page.hasRail === (row.zones.length >= 2),
                row.name + ": a rail appears exactly when there are two or more zones");
            if (row.zones.length > 0) {
                page.currentSection = row.zones[0];
                assert(page.isZoneCurrent(row.zones[0]) === true,
                    row.name + ": the current zone is highlighted");
                if (row.zones.length > 1) {
                    assert(page.isZoneCurrent(row.zones[1]) === false,
                        row.name + ": only the current zone is highlighted");
                }
                page.currentSection = "";
                assert(page.isZoneCurrent(row.zones[0]) === false,
                    row.name + ": before the spy reports, nothing is highlighted");
            }
        }

        // ------------------------------------------------------------------
        // A zone whose section cannot be shown is not offered
        // ------------------------------------------------------------------
        // The rail is the page's live state, not a static menu: when a section
        // is hidden (no streams, Wi-Fi off, adapter off) its segment goes too,
        // instead of scrolling to a section that is not there.
        assert(audioPage.zones.length === 3, "audio: the apps zone is offered while a stream plays");
        audioPage.testAppStreams = [];
        assert(audioPage.zones.length === 2 && audioPage.sectionY("apps") === undefined,
            "audio: the apps zone leaves with the streams");

        assert(networkPage.zones.length === 2, "network: the networks zone is offered while Wi-Fi is on");
        networkPage.testWifiEnabled = false;
        assert(networkPage.zones.length === 1 && networkPage.sectionY("networks") === undefined,
            "network: the networks zone leaves when Wi-Fi is off");

        assert(bluetoothPage.zones.length === 2, "bluetooth: the devices zone is offered while powered on");
        bluetoothPage.testPowered = false;
        assert(bluetoothPage.zones.length === 1 && bluetoothPage.sectionY("devices") === undefined,
            "bluetooth: the devices zone leaves when the adapter is off");

        // ------------------------------------------------------------------
        // The hub recomputes the zone offsets when the page relayouts
        // ------------------------------------------------------------------
        // A page that is not laid out yet reports every anchor at y=0, and a
        // short page never changes the flickable's content height - so offsets
        // cannot be a one-shot snapshot (that is what highlighted the last zone
        // at the top of the audio page). They are recomputed after every event
        // that can move an anchor, one event-loop turn later.
        const hub = readLocalFile("../settings_gui/NexusHub.qml");
        assert(hub.indexOf("function recomputeZoneOffsets") >= 0
                && hub.indexOf("root.pageZoneOffsets = offsets") >= 0,
            "the hub recomputes the zone offsets instead of snapshotting them");
        assert(hub.indexOf("Qt.callLater(root.recomputeZoneOffsets)") >= 0,
            "the recompute is deferred past the page's layout pass");
        assert(hub.indexOf("onPageZonesChanged") >= 0,
            "zones that follow the page's live state refresh the offsets");
        assert(hub.indexOf("function onItemChanged") >= 0,
            "installing a page refreshes the offsets");
        assert(hub.indexOf("function onImplicitHeightChanged") >= 0,
            "the page's own height settling refreshes the offsets (short pages never change contentHeight)");
        const contentHeightHandler = hub.substring(hub.indexOf("function onContentHeightChanged"),
                                                  hub.indexOf("function onContentHeightChanged") + 200);
        assert(contentHeightHandler.indexOf("refreshZoneOffsets") >= 0,
            "growing content refreshes the offsets too");
        assert(hub.indexOf("function applyPendingSection") >= 0
                && hub.indexOf("property string pendingSectionId") >= 0,
            "a zone request that cannot be honoured yet is parked, not dropped");
        assert(hub.indexOf("onPageZoneOffsetsChanged: root.applyPendingSection()") >= 0,
            "and honoured as soon as the recalculated offsets are current (after the layout pass)");
        assert(hub.indexOf("function bindPageNavigation") >= 0
                && hub.indexOf("zoneRequested.connect(root.scrollToSection)") >= 0,
            "the page's rail is wired to the hub's scroller");
        assert(hub.indexOf("Config.settingsSection") >= 0,
            "external deep links still arrive through Config.openSettings");

        console.log("PASS: Settings Pages Contract");
        Qt.exit(0);
    }
}
