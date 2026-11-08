import QtQuick
import QtQuick.Controls
import "../settings_gui/pages"

// ============================================================================
// Apps page
// ============================================================================
// The page lists every app the desktop knows, with the three numbers a user needs
// (version, API level, state) and the platform's own actions: enable/disable and
// remove. It renders the daemon's list — it does not keep its own truth.
ApplicationWindow {
    id: testRoot
    visible: false
    width: 900
    height: 700

    function assert(condition, message) {
        if (!condition) {
            console.error("FAIL: " + message);
            Qt.exit(1);
            throw new Error(message);
        }
    }

    function readLocalFile(relUrl) {
        const xhr = new XMLHttpRequest();
        xhr.open("GET", Qt.resolvedUrl(relUrl) + "?v=" + Date.now(), false);
        xhr.send();
        return xhr.responseText || "";
    }

    readonly property var fixtures: [
        { id: "org.astralplasma.dock", name: "Dock", version: "0.1.0", kernelApi: 1,
          preinstalled: true, enabled: true, compatible: true, reason: null },
        { id: "org.astralplasma.media", name: "Media", version: "0.2.1", kernelApi: 1,
          preinstalled: true, enabled: false, compatible: true, reason: null },
        { id: "io.github.alice.clock", name: "World Clock", version: "1.4.0", kernelApi: 9,
          preinstalled: false, enabled: true, compatible: false,
          reason: "needs a newer Astral (API 9); this is API 1" }
    ]

    AppsPage {
        id: page
        anchors.fill: parent
        testMode: true
        testApps: testRoot.fixtures
    }

    Component.onCompleted: {
        // ---- the rows carry identity, version and API -----------------------
        assert(page.apps.length === 3, "the page lists every app it is given");
        assert(page.stateLabel(page.apps[0]) === "Enabled", "an enabled app reads Enabled");
        assert(page.stateLabel(page.apps[1]) === "Disabled", "a disabled app reads Disabled");
        assert(page.stateLabel(page.apps[2]) === "Incompatible", "an incompatible app says so");

        // ---- the page is data-driven and action-bearing ---------------------
        const source = readLocalFile("../settings_gui/pages/AppsPage.qml");
        assert(source.length > 1000, "the page must be readable");
        assert(source.indexOf("AppsService.refresh()") >= 0, "the page refreshes from the service");
        assert(source.indexOf("setEnabled(") >= 0, "the page must offer enable/disable");
        assert(source.indexOf("remove(") >= 0, "the page must offer remove");
        assert(source.indexOf("modelData.version") >= 0, "each row shows its version");
        assert(source.indexOf("modelData.kernelApi") >= 0, "each row shows its API level");
        assert(source.indexOf("Config.") === -1,
            "the page must not read Config directly; the service owns the daemon call");

        // ---- the service speaks the daemon's language -----------------------
        const service = readLocalFile("../modules/Astral/Kernel/services/AppsService.qml");
        assert(service.indexOf('"app", "list", "--json"') >= 0, "the service lists from the daemon");
        assert(service.indexOf('enabled ? "enable" : "disable"') >= 0,
            "the service toggles through the daemon");
        assert(service.indexOf('"app", "remove"') >= 0, "the service removes through the daemon");

        console.log("PASS: All Apps page tests passed!");
        Qt.exit(0);
    }
}
