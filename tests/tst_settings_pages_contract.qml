import QtQuick
import "../settings_gui/pages"

// ============================================================================
// Every settings page adopts the hub contract
// ============================================================================
// The hub pins each page's identity (icon, title, subtitle) above the scroll
// area. Pages then choose one of two shapes:
//
//   * **sections** (most pages): a vertical stack. `zones` names the anchors the
//     hub scrolls a deep link to; no in-page navigation strip is drawn.
//   * **tabs** (only pages that genuinely run several viewports): a horizontal
//     icon + label strip that swaps the body.
//
// The contract is asserted per page, not per component:
//
//   * the root *is* `SettingsPage`;
//   * every page names itself, says what it is for, and carries an icon;
//   * a sections page declares anchors in document order, and `sectionY`
//     resolves them;
//   * a tabs page declares id/label/icon tabs, selects the first by default,
//     and ignores unknown ids;
//   * live sections and tabs leave when their state disappears.
//
// The AiPage keeps its own root (it hosts absolutely positioned overlays) and is
// covered by `tst_settings_sticky_header.qml`; SkillsPage is covered by
// `tst_skills_app.qml`.
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

    /// `[page, source path, sections or tabs]` - the document, in one table, so
    /// a page cannot satisfy the contract by accident of a similar neighbour.
    /// An empty section list is a single-body page.
    readonly property var pages: [
        {
            name: "WallpaperAndStylePage",
            source: "../settings_gui/pages/WallpaperAndStylePage.qml",
            page: wallpaperPage,
            sections: ["wallpaper", "palette", "mode", "gallery"]
        },
        {
            name: "UpdatesPage",
            source: "../settings_gui/pages/UpdatesPage.qml",
            page: updatesPage,
            sections: ["version", "update", "notes", "maintenance"]
        },
        {
            name: "ThemePage",
            source: "../settings_gui/pages/ThemePage.qml",
            page: themePage,
            sections: ["style", "colors", "shape", "preview"]
        },
        {
            name: "NetworkPage",
            source: "../settings_gui/pages/NetworkPage.qml",
            page: networkPage,
            sections: ["wifi", "networks"]
        },
        {
            name: "BluetoothPage",
            source: "../settings_gui/pages/BluetoothPage.qml",
            page: bluetoothPage,
            sections: ["power", "devices"]
        },
        {
            name: "AudioPage",
            source: "../settings_gui/pages/AudioPage.qml",
            page: audioPage,
            sections: ["output", "visualizer", "apps"]
        },
        {
            name: "DockPage",
            source: "../settings_gui/pages/DockPage.qml",
            page: dockPage,
            sections: ["dock", "tray", "topbar"]
        },
        {
            name: "StatusIconsPage",
            source: "../settings_gui/pages/StatusIconsPage.qml",
            page: statusPage,
            sections: []
        },
        {
            name: "DashboardPage",
            source: "../settings_gui/pages/DashboardPage.qml",
            page: dashboardPage,
            sections: ["tabs", "calendar", "visualizer", "avatars"]
        },
        {
            name: "DownloadsPage",
            source: "../settings_gui/pages/DownloadsPage.qml",
            page: downloadsPage,
            sections: ["engine", "destination", "settings"]
        },
        {
            name: "AppsPage",
            source: "../settings_gui/pages/AppsPage.qml",
            page: appsPage,
            sections: []
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
            sections: ["cities", "local"]
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
            const isTabs = row.tabs !== undefined;

            // ------------------------------------------------------------------
            // The declaration lives in the page, not in a redrawn header
            // ------------------------------------------------------------------
            const src = readLocalFile(row.source);
            assert(src !== "", row.name + ": source is readable");
            assert(/\nSettingsPage \{/.test(src),
                row.name + ": the root is SettingsPage (identity declared once)");
            assert(src.indexOf("property Component stickyHeader") < 0,
                row.name + ": it does not hand-write the sticky header SettingsPage provides");

            // ------------------------------------------------------------------
            // Identity
            // ------------------------------------------------------------------
            assert(page.title !== "", row.name + ": the page names itself");
            assert(page.subtitle !== "", row.name + ": it says what it is for");
            assert(page.icon !== "", row.name + ": it carries a page icon");
            assert(page.stickyHeader !== null && typeof page.stickyHeader === "object",
                row.name + ": the hub has a header to pin");

            // ------------------------------------------------------------------
            // Sections: anchors for deep links, no in-page navigation strip
            // ------------------------------------------------------------------
            if (!isTabs) {
                const ids = row.sections;
                assert(page.hasTabs === false,
                    row.name + ": a sections page declares no tabs");
                assert(page.zones.length === ids.length,
                    row.name + ": " + ids.length + " section anchors (got " + page.zones.length + ")");
                assert(src.indexOf("tabs:") < 0,
                    row.name + ": its source declares no tabs");
                assert(src.indexOf("root.currentTab") < 0,
                    row.name + ": its source has no tab-switched bodies");
                assert(src.indexOf("zoneRequested") < 0,
                    row.name + ": it does not draw the old rail");

                let previousY = -1;
                for (let s = 0; s < ids.length; ++s) {
                    const id = ids[s];
                    const zone = page.zones[s];
                    assert(zone && zone.id === id,
                        row.name + ": section " + s + " is \"" + id + "\" (got "
                            + (zone ? zone.id : "none") + ")");
                    assert(zone.label && zone.label !== "",
                        row.name + ": section \"" + id + "\" carries a label");
                    const y = page.sectionY(id);
                    assert(y !== undefined && y !== null && !isNaN(y),
                        row.name + ": section \"" + id + "\" resolves to a page offset");
                    assert(y > previousY,
                        row.name + ": section \"" + id + "\" is anchored below the previous one ("
                            + previousY + " -> " + y + ")");
                    previousY = y;
                }
                assert(page.sectionY("nonsense") === undefined,
                    row.name + ": an undeclared section has no anchor");
                page.currentSection = ids.length > 0 ? ids[0] : "";
                assert(page.currentSection === (ids.length > 0 ? ids[0] : ""),
                    row.name + ": the hub can write the current section");
                continue;
            }

            // ------------------------------------------------------------------
            // Tabs: declared, labelled, iconed, in order
            // ------------------------------------------------------------------
            const ids = row.tabs;
            assert(page.hasTabs === true,
                row.name + ": a tabs page declares tabs");
            assert(page.zones.length === 0,
                row.name + ": a tabs page declares no scroll anchors");
            assert(src.indexOf("tabs:") >= 0,
                row.name + ": its source declares tabs");
            assert(page.tabs.length === ids.length,
                row.name + ": " + ids.length + " tabs declared (got " + page.tabs.length + ")");

            for (let t = 0; t < ids.length; ++t) {
                const id = ids[t];
                const tab = page.tabs[t];
                assert(tab && tab.id === id,
                    row.name + ": tab " + t + " is \"" + id + "\" (got " + (tab ? tab.id : "none") + ")");
                assert(tab.label && tab.label !== "",
                    row.name + ": tab \"" + id + "\" carries a label");
                assert(tab.icon && tab.icon !== "",
                    row.name + ": tab \"" + id + "\" carries an icon");
            }

            assert(page.currentTab === ids[0],
                row.name + ": the first tab is selected by default (got \"" + page.currentTab + "\")");
            const last = ids[ids.length - 1];
            page.selectTab(last);
            assert(page.currentTab === last,
                row.name + ": selectTab switches to \"" + last + "\"");
            page.selectTab("nonsense");
            assert(page.currentTab === last,
                row.name + ": an unknown tab id is ignored");
            page.selectTab(ids[0]);
        }

        // ------------------------------------------------------------------
        // A section whose content cannot be shown is not offered
        // ------------------------------------------------------------------
        assert(audioPage.zones.length === 3, "audio: the apps section is offered while a stream plays");
        audioPage.testAppStreams = [];
        assert(audioPage.zones.length === 2 && audioPage.sectionY("apps") === undefined,
            "audio: the apps section leaves with the streams");

        assert(networkPage.zones.length === 2, "network: the networks section is offered while Wi-Fi is on");
        networkPage.testWifiEnabled = false;
        assert(networkPage.zones.length === 1 && networkPage.sectionY("networks") === undefined,
            "network: the networks section leaves when Wi-Fi is off");

        assert(bluetoothPage.zones.length === 2, "bluetooth: the devices section is offered while powered on");
        bluetoothPage.testPowered = false;
        assert(bluetoothPage.zones.length === 1 && bluetoothPage.sectionY("devices") === undefined,
            "bluetooth: the devices section leaves when the adapter is off");

        // ------------------------------------------------------------------
        // The hub routes sections through scrollTo and tabs through selectTab
        // ------------------------------------------------------------------
        const hub = readLocalFile("../settings_gui/NexusHub.qml");
        assert(hub.indexOf("function scrollToSection") >= 0,
            "the hub keeps one entry point for deep links");
        assert(hub.indexOf("page.selectTab(zoneId)") >= 0,
            "a deep link selects a tabs page's tab");
        assert(hub.indexOf("page.hasTabs") >= 0,
            "the hub recognizes a tabs page");
        assert(hub.indexOf("page.sectionY(zoneId)") >= 0,
            "a deep link scrolls a sections page to its anchor");
        assert(hub.indexOf("Config.settingsSection") >= 0,
            "external deep links still arrive through Config.openSettings");
        assert(hub.indexOf("id: stickyHeaderLoader") >= 0,
            "the hub still pins the page header outside the flickable");

        console.log("PASS: Settings Pages Contract");
        Qt.exit(0);
    }
}
